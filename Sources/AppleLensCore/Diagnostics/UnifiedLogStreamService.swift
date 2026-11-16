import Foundation
import os

public final class UnifiedLogStreamService: Sendable {
    public static let defaultPredicate =
        #"process IN {"privatecloudcomputed", "eligibilityd", "assistantd", "modelmanagerd", "generativeexperiencesd", "TGOnDeviceInferenceProviderService", "GenerativeExperiencesSafetyInferenceProvider", "Photos"} OR subsystem CONTAINS "PrivateCloudCompute" OR subsystem CONTAINS "Generative" OR subsystem CONTAINS "UnifiedAssetFramework""#

    private struct StreamState: Sendable {
        var liveProcess: Process?
        var lineBuffer = Data()
    }

    private let stateLock = OSAllocatedUnfairLock(initialState: StreamState())

    public var isStreaming: Bool {
        stateLock.withLock { $0.liveProcess?.isRunning == true }
    }

    public init() {}

    deinit {
        stopLiveStream()
    }

    /// Starts streaming live macOS Unified Logs using `/usr/bin/log stream --style ndjson`.
    public func startLiveStream(
        predicate: String = UnifiedLogStreamService.defaultPredicate,
        onEvent: @escaping @Sendable (UnifiedLogEvent) -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) {
        stopLiveStream()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        proc.arguments = [
            "stream",
            "--style", "ndjson",
            "--level", "info",
            "--predicate", predicate
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        stateLock.withLock { state in
            state.lineBuffer.removeAll(keepingCapacity: false)
            state.liveProcess = proc
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            self?.consumeChunk(chunk, onEvent: onEvent)
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            if let text = String(data: chunk, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                onError(text)
            }
        }

        proc.terminationHandler = { [weak self] terminatedProc in
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            self?.stateLock.withLock { state in
                if state.liveProcess === terminatedProc {
                    state.liveProcess = nil
                }
            }
        }

        do {
            try proc.run()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            stateLock.withLock { state in
                if state.liveProcess === proc {
                    state.liveProcess = nil
                }
            }
            onError(error.localizedDescription)
        }
    }

    public func stopLiveStream() {
        let proc = stateLock.withLock { state -> Process? in
            let existing = state.liveProcess
            state.liveProcess = nil
            state.lineBuffer.removeAll(keepingCapacity: false)
            return existing
        }

        if let proc, proc.isRunning {
            proc.terminate()
        }
    }

    /// Scans recent historical logs (`log show --last <minutes>m --style ndjson`) using bounded chunked I/O
    /// so large log windows never trigger multi-hundred-megabyte transient memory spikes.
    public func scanRecentHistory(
        minutes: Int = 15,
        predicate: String = UnifiedLogStreamService.defaultPredicate,
        maxEvents: Int = 2000
    ) async -> [UnifiedLogEvent] {
        guard maxEvents > 0 else { return [] }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/log")
                proc.arguments = [
                    "show",
                    "--last", "\(max(1, minutes))m",
                    "--style", "ndjson",
                    "--info",
                    "--predicate", predicate
                ]

                let pipe = Pipe()
                proc.standardOutput = pipe
                proc.standardError = FileHandle.nullDevice

                do {
                    try proc.run()
                    let events = try Self.parseNDJSONStream(
                        from: pipe.fileHandleForReading,
                        sourceDevice: "This Mac",
                        maxEvents: maxEvents,
                        chunkSize: 65_536
                    )
                    try? pipe.fileHandleForReading.close()
                    proc.waitUntilExit()
                    continuation.resume(returning: events)
                } catch {
                    try? pipe.fileHandleForReading.close()
                    if proc.isRunning {
                        proc.terminate()
                        proc.waitUntilExit()
                    }
                    continuation.resume(returning: [])
                }
            }
        }
    }

    /// Incrementally reads NDJSON chunks from `handle`, keeping a bounded tail window of at most `maxEvents` events.
    public static func parseNDJSONStream(
        from handle: FileHandle,
        sourceDevice: String = "This Mac",
        maxEvents: Int = 2000,
        chunkSize: Int = 65_536
    ) throws -> [UnifiedLogEvent] {
        guard maxEvents > 0 else { return [] }
        let effectiveChunkSize = max(1, chunkSize)
        let decoder = JSONDecoder()
        var lineBuffer = Data()
        var tailBuffer: [UnifiedLogEvent] = []
        tailBuffer.reserveCapacity(min(maxEvents, 256))
        var writeIndex = 0

        func appendBounded(_ event: UnifiedLogEvent) {
            if tailBuffer.count < maxEvents {
                tailBuffer.append(event)
            } else {
                tailBuffer[writeIndex] = event
                writeIndex = (writeIndex + 1) % maxEvents
            }
        }

        func drain(includeTrailing: Bool) {
            let consumed = scanLines(in: lineBuffer, includeTrailing: includeTrailing) { lineSlice in
                if let event = parseSingleNDJSONLine(lineSlice, sourceDevice: sourceDevice, decoder: decoder) {
                    appendBounded(event)
                }
            }
            if includeTrailing || consumed == lineBuffer.endIndex {
                lineBuffer.removeAll(keepingCapacity: !includeTrailing && lineBuffer.count <= 262_144)
            } else if consumed > lineBuffer.startIndex {
                lineBuffer.removeSubrange(lineBuffer.startIndex..<consumed)
            }
        }

        while let chunk = try handle.read(upToCount: effectiveChunkSize), !chunk.isEmpty {
            lineBuffer.append(chunk)
            drain(includeTrailing: false)
        }
        drain(includeTrailing: true)

        if tailBuffer.count < maxEvents || writeIndex == 0 {
            return tailBuffer
        }
        return Array(tailBuffer[writeIndex...] + tailBuffer[..<writeIndex])
    }

    private func consumeChunk(_ chunk: Data, onEvent: @Sendable (UnifiedLogEvent) -> Void) {
        let completeLines = stateLock.withLock { state -> [Data] in
            state.lineBuffer.append(chunk)
            var lines: [Data] = []
            let consumed = Self.scanLines(in: state.lineBuffer, includeTrailing: false) { lineSlice in
                lines.append(Data(lineSlice))
            }
            if consumed == state.lineBuffer.endIndex {
                state.lineBuffer.removeAll(keepingCapacity: state.lineBuffer.count <= 262_144)
            } else if consumed > state.lineBuffer.startIndex {
                state.lineBuffer.removeSubrange(state.lineBuffer.startIndex..<consumed)
            }
            return lines
        }

        guard !completeLines.isEmpty else { return }
        let decoder = JSONDecoder()
        for line in completeLines {
            if let event = Self.parseSingleNDJSONLine(line, sourceDevice: "This Mac", decoder: decoder) {
                onEvent(event)
            }
        }
    }

    public static func parseNDJSONData(_ data: Data, sourceDevice: String = "This Mac") -> [UnifiedLogEvent] {
        guard !data.isEmpty else { return [] }
        let decoder = JSONDecoder()
        var events: [UnifiedLogEvent] = []
        _ = scanLines(in: data, includeTrailing: true) { lineSlice in
            if let ev = parseSingleNDJSONLine(lineSlice, sourceDevice: sourceDevice, decoder: decoder) {
                events.append(ev)
            }
        }
        return events
    }

    private static func scanLines(
        in buffer: Data,
        includeTrailing: Bool,
        onLine: (Data) -> Void
    ) -> Data.Index {
        var scanIndex = buffer.startIndex
        while scanIndex < buffer.endIndex {
            let lineEnd: Data.Index
            if let newlineIndex = buffer[scanIndex...].firstIndex(of: 0x0A) {
                lineEnd = newlineIndex
            } else if includeTrailing {
                lineEnd = buffer.endIndex
            } else {
                break
            }
            var lineSlice = buffer[scanIndex..<lineEnd]
            if lineSlice.last == 0x0D {
                lineSlice = lineSlice.dropLast()
            }
            if !lineSlice.isEmpty {
                onLine(lineSlice)
            }
            scanIndex = lineEnd < buffer.endIndex ? buffer.index(after: lineEnd) : buffer.endIndex
        }
        return scanIndex
    }

    private struct RawLogRecord: Decodable, Sendable {
        let timestamp: String?
        let processImagePath: String?
        let processID: Int32?
        let subsystem: String?
        let category: String?
        let eventMessage: String?
        let eventType: String?
    }

    /// Thread-safe pure-Swift parser for Unified Log timestamps (`"yyyy-MM-dd HH:mm:ss.SSSSSSZ"` and ISO-8601 variants).
    public static func parseLogTimestamp(_ text: String) -> Date? {
        let bytes = Array(text.utf8)
        let count = bytes.count
        var i = 0

        func readDigits(_ n: Int) -> Int? {
            guard i + n <= count else { return nil }
            var value = 0
            for offset in 0..<n {
                let b = bytes[i + offset]
                guard b >= 0x30 && b <= 0x39 else { return nil }
                value = value * 10 + Int(b - 0x30)
            }
            i += n
            return value
        }

        func expectByte(_ expected: UInt8) -> Bool {
            guard i < count, bytes[i] == expected else { return false }
            i += 1
            return true
        }

        guard let year = readDigits(4),
              expectByte(0x2D),
              let month = readDigits(2),
              expectByte(0x2D),
              let day = readDigits(2),
              i < count, (bytes[i] == 0x20 || bytes[i] == 0x54 || bytes[i] == 0x74)
        else {
            return nil
        }
        i += 1

        guard let hour = readDigits(2),
              expectByte(0x3A),
              let minute = readDigits(2),
              expectByte(0x3A),
              let second = readDigits(2)
        else {
            return nil
        }

        guard (1...12).contains(month),
              (0...23).contains(hour),
              (0...59).contains(minute),
              (0...59).contains(second) else {
            return nil
        }

        let isLeap = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
        let maxDay: Int
        switch month {
        case 2: maxDay = isLeap ? 29 : 28
        case 4, 6, 9, 11: maxDay = 30
        default: maxDay = 31
        }
        guard (1...maxDay).contains(day) else { return nil }

        var fractionalSeconds: Double = 0
        if i < count && bytes[i] == 0x2E {
            i += 1
            let fracStart = i
            var fracInt = 0
            var scale = 1.0
            while i < count && bytes[i] >= 0x30 && bytes[i] <= 0x39 {
                if i - fracStart < 9 {
                    fracInt = fracInt * 10 + Int(bytes[i] - 0x30)
                    scale *= 10.0
                }
                i += 1
            }
            guard i > fracStart else { return nil }
            fractionalSeconds = Double(fracInt) / scale
        }

        guard i < count else { return nil }
        let offsetSeconds: Int
        let tzSignByte = bytes[i]
        if tzSignByte == 0x5A || tzSignByte == 0x7A {
            i += 1
            offsetSeconds = 0
        } else if tzSignByte == 0x2B || tzSignByte == 0x2D {
            let sign = (tzSignByte == 0x2B) ? 1 : -1
            i += 1
            guard let tzHour = readDigits(2), (0...23).contains(tzHour) else {
                return nil
            }
            var tzMinute = 0
            if i < count {
                if bytes[i] == 0x3A {
                    i += 1
                    guard let m = readDigits(2), (0...59).contains(m) else { return nil }
                    tzMinute = m
                } else if i + 2 <= count && bytes[i] >= 0x30 && bytes[i] <= 0x39 {
                    guard let m = readDigits(2), (0...59).contains(m) else { return nil }
                    tzMinute = m
                }
            }
            offsetSeconds = sign * (tzHour * 3600 + tzMinute * 60)
        } else {
            return nil
        }

        guard i == count else { return nil }

        var adjustedYear = year
        if month <= 2 {
            adjustedYear -= 1
        }
        let era = (adjustedYear >= 0 ? adjustedYear : adjustedYear - 399) / 400
        let yoe = adjustedYear - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        let daysSince1970 = era * 146_097 + doe - 719_468

        let wholeSeconds = Int64(daysSince1970) * 86_400
            + Int64(hour) * 3_600
            + Int64(minute) * 60
            + Int64(second)
            - Int64(offsetSeconds)
        return Date(timeIntervalSince1970: Double(wholeSeconds) + fractionalSeconds)
    }

    public static func parseSingleNDJSONLine(_ data: Data, sourceDevice: String = "This Mac") -> UnifiedLogEvent? {
        parseSingleNDJSONLine(data, sourceDevice: sourceDevice, decoder: JSONDecoder())
    }

    private static func parseSingleNDJSONLine(
        _ data: Data,
        sourceDevice: String,
        decoder: JSONDecoder
    ) -> UnifiedLogEvent? {
        var trimmed = data
        while let first = trimmed.first,
              first == 0x20 || first == 0x09 || first == 0x0D || first == 0x0A {
            trimmed = trimmed.dropFirst()
        }
        guard trimmed.first == UInt8(ascii: "{") else {
            return nil
        }
        guard let rec = try? decoder.decode(RawLogRecord.self, from: trimmed),
              let msg = rec.eventMessage,
              !msg.isEmpty else {
            return nil
        }
        let procName: String
        if let path = rec.processImagePath, !path.isEmpty {
            procName = URL(fileURLWithPath: path).lastPathComponent
        } else {
            procName = "unknown"
        }
        let ts = rec.timestamp.flatMap { parseLogTimestamp($0) } ?? Date()
        return UnifiedLogEvent(
            timestamp: ts,
            processName: procName,
            processID: rec.processID ?? 0,
            subsystem: rec.subsystem ?? "",
            category: rec.category ?? "",
            message: msg,
            sourceDevice: sourceDevice
        )
    }
}
