import Darwin
import Foundation
import os

public struct ConnectedIOSDevice: Identifiable, Hashable, Sendable {
    public let id: String // UDID
    public let deviceName: String
    public let productType: String
    public let productVersion: String
    public let buildVersion: String
    public let regionInfo: String
    public let modelNumber: String
    public let isPaired: Bool

    public var displayTitle: String {
        let model = productType.isEmpty ? "iPhone" : productType
        let ver = productVersion.isEmpty ? "" : " · iOS \(productVersion)"
        let reg = regionInfo.isEmpty ? "" : " · \(regionInfo)"
        return "\(deviceName.isEmpty ? model : deviceName)\(ver)\(reg)"
    }
}

/// Zero-dependency, read-only USB iOS syslog relay bridge dynamically loaded via macOS built-in `MobileDevice.framework`.
/// Never depends on `idevicesyslog`, `pymobiledevice3`, or `sudo`.
public final class USBiPhoneLogBridge: Sendable {
    private struct AMDeviceNotificationCallbackInfo {
        var dev: OpaquePointer?
        var msg: UInt32
    }

    private typealias FnNotificationSubscribe = @convention(c) (
        @convention(c) (UnsafeRawPointer?, UnsafeMutableRawPointer?) -> Void,
        UInt32,
        UInt32,
        UnsafeMutableRawPointer?,
        UnsafeMutablePointer<OpaquePointer?>
    ) -> Int32
    private typealias FnNotificationUnsubscribe = @convention(c) (OpaquePointer?) -> Int32
    private typealias FnDeviceConnect = @convention(c) (OpaquePointer?) -> Int32
    private typealias FnDeviceDisconnect = @convention(c) (OpaquePointer?) -> Int32
    private typealias FnDeviceIsPaired = @convention(c) (OpaquePointer?) -> Int32
    private typealias FnDeviceValidatePairing = @convention(c) (OpaquePointer?) -> Int32
    private typealias FnDeviceStartSession = @convention(c) (OpaquePointer?) -> Int32
    private typealias FnDeviceStopSession = @convention(c) (OpaquePointer?) -> Int32
    private typealias FnDeviceGetInterfaceType = @convention(c) (OpaquePointer?) -> Int32
    private typealias FnDeviceCopyUDID = @convention(c) (OpaquePointer?) -> Unmanaged<CFString>?
    private typealias FnDeviceCopyValue = @convention(c) (OpaquePointer?, CFString?, CFString?) -> Unmanaged<CFTypeRef>?
    private typealias FnSecureStartService = @convention(c) (OpaquePointer?, CFString, CFDictionary?, UnsafeMutablePointer<OpaquePointer?>) -> Int32
    private typealias FnServiceReceive = @convention(c) (OpaquePointer?, UnsafeMutableRawPointer, Int) -> Int32
    private typealias FnServiceInvalidate = @convention(c) (OpaquePointer?) -> Void
    private typealias FnServiceSendMessage = @convention(c) (OpaquePointer?, CFPropertyList, UInt32) -> Int32
    private typealias FnServiceReceiveMessage = @convention(c) (OpaquePointer?, UnsafeMutablePointer<Unmanaged<CFPropertyList>?>, UnsafeMutablePointer<UInt32>?) -> Int32

    private struct MobileDeviceSymbols: Sendable {
        let subscribe: FnNotificationSubscribe?
        let unsubscribe: FnNotificationUnsubscribe?
        let connect: FnDeviceConnect?
        let disconnect: FnDeviceDisconnect?
        let isPaired: FnDeviceIsPaired?
        let validatePairing: FnDeviceValidatePairing?
        let startSession: FnDeviceStartSession?
        let stopSession: FnDeviceStopSession?
        let getInterfaceType: FnDeviceGetInterfaceType?
        let copyUDID: FnDeviceCopyUDID?
        let copyValue: FnDeviceCopyValue?
        let secureStartService: FnSecureStartService?
        let serviceReceive: FnServiceReceive?
        let serviceInvalidate: FnServiceInvalidate?
        let serviceSendMessage: FnServiceSendMessage?
        let serviceReceiveMessage: FnServiceReceiveMessage?
    }

    private struct WeakBridgeBox {
        weak var bridge: USBiPhoneLogBridge?
    }

    private final class CallbackBox: Sendable {
        private let lock: OSAllocatedUnfairLock<WeakBridgeBox>

        init(bridge: USBiPhoneLogBridge) {
            self.lock = OSAllocatedUnfairLock(uncheckedState: WeakBridgeBox(bridge: bridge))
        }

        var bridge: USBiPhoneLogBridge? {
            lock.withLockUnchecked { $0.bridge }
        }

        func clear() {
            lock.withLockUnchecked { $0.bridge = nil }
        }
    }

    private struct BridgeState {
        var frameworkHandle: UnsafeMutableRawPointer?
        var notificationRef: OpaquePointer?
        var callbackBox: Unmanaged<CallbackBox>?
        var deviceRefs: [String: OpaquePointer] = [:]
        var discoveredDevices: [String: ConnectedIOSDevice] = [:]
        var isStreamingActive = false
        var streamGeneration: UInt64 = 0
        var activeServiceConn: OpaquePointer?
        var onDevicesChanged: (@Sendable ([ConnectedIOSDevice]) -> Void)?
        var onStatusMessage: (@Sendable (String) -> Void)?
    }

    private static let relevantProcessNames: Set<String> = [
        // Apple Intelligence, Siri, Photos & PCC daemons
        "mobileslideshow", "photos", "mediaanalysisd", "photoanalysisd",
        "vcpmediaanalysisservice", "assistantd", "siriinferenced",
        "privatecloudcomputed", "eligibilityd", "modelmanagerd",
        "generativeexperiencesd", "generativeexperiencessafetyinferenceprovider",
        "tgondeviceinferenceproviderservice", "aned", "cameraoverlayangel",
        "grace", "writingtools", "imageplayground",
        // Third-party AI clients logging directly
        "claude", "chatgpt", "sora", "gemini", "deepseek",
        "doubao", "nova", "kimi", "kimichat", "tongyi",
        "qingyan", "grok", "grokapp", "perplexity"
    ]

    private static let relevantSubsystemTokens: [String] = [
        "siri", "photoimaging", "visualintelligence", "generativemodels",
        "generativefunctions", "privatecloudcompute", "cloudattestation",
        "unifiedassetframework", "intelligenceflow", "foundationmodels"
    ]

    private static let highPrecisionTokens: [String] = [
        "code=32033", "code = 32033", "error 32033",
        "code=1009", "code = 1009", "rate-limited",
        "guzzoni", "issuer.apple.com", "apple-relay",
        "mask-api", "mask.icloud.com", "mask-h2.icloud.com",
        "ropes.apple.com", "ss-cleanup-proxy", "cleanup-proxy",
        "remoteinpaint", "photocleanup", "visualintelligence",
        "lens.google", "montara", "siriexternalai", "external-ai",
        "thimble", "ohttp", "tgondeviceinference",
        "privatecloudcompute", "generativefunctions", "unifiedassetframework",
        "personal translator", "no cn region policy"
    ]

    private static let knownAIClientTokens: [String] = [
        "claude", "anthropic", "chatgpt", "openai", "sora", "gemini",
        "deepseek", "doubao", "com.bot.doubao", "larus.nova",
        "kimichat", "moonshot", "tongyi", "qingyan", "grokapp", "perplexity",
        "com.x.grok", "com.google.opa"
    ]

    private static let knownAppleAIBundleTokens: [String] = [
        "com.apple.mobileslideshow", "com.apple.photos", "com.apple.siri",
        "com.apple.generative", "com.apple.imageplayground",
        "com.apple.writingtools", "com.apple.visualintelligence",
        "com.apple.privatecloudcompute", "com.apple.cameraoverlayangel"
    ]

    private let stateLock: OSAllocatedUnfairLock<BridgeState>
    private let symbols: MobileDeviceSymbols?

    public var isStreaming: Bool {
        stateLock.withLockUnchecked { $0.isStreamingActive }
    }

    public var onDevicesChanged: (@Sendable ([ConnectedIOSDevice]) -> Void)? {
        get { stateLock.withLockUnchecked { $0.onDevicesChanged } }
        set { stateLock.withLockUnchecked { $0.onDevicesChanged = newValue } }
    }

    public var onStatusMessage: (@Sendable (String) -> Void)? {
        get { stateLock.withLockUnchecked { $0.onStatusMessage } }
        set { stateLock.withLockUnchecked { $0.onStatusMessage = newValue } }
    }

    public init() {
        let loaded = Self.loadFrameworkSymbols()
        self.symbols = loaded.symbols
        self.stateLock = OSAllocatedUnfairLock(uncheckedState: BridgeState(frameworkHandle: loaded.handle))
    }

    deinit {
        stopMonitoring()
        let handle = stateLock.withLockUnchecked { state -> UnsafeMutableRawPointer? in
            let h = state.frameworkHandle
            state.frameworkHandle = nil
            return h
        }
        if let handle {
            dlclose(handle)
        }
    }

    public var isFrameworkAvailable: Bool {
        guard let symbols else { return false }
        return symbols.subscribe != nil
            && symbols.connect != nil
            && symbols.secureStartService != nil
            && symbols.serviceReceive != nil
    }

    public var currentDevices: [ConnectedIOSDevice] {
        stateLock.withLockUnchecked {
            Array($0.discoveredDevices.values).sorted { $0.deviceName < $1.deviceName }
        }
    }

    @inline(__always)
    private static func retainDeviceRef(_ dev: OpaquePointer) {
        _ = Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(dev)).retain()
    }

    @inline(__always)
    private static func releaseDeviceRef(_ dev: OpaquePointer) {
        Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(dev)).release()
    }

    private static func loadFrameworkSymbols() -> (handle: UnsafeMutableRawPointer?, symbols: MobileDeviceSymbols?) {
        let candidates = [
            "/System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice",
            "/Library/Apple/System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice"
        ]
        var loaded: UnsafeMutableRawPointer?
        for path in candidates {
            if let h = dlopen(path, RTLD_LAZY) {
                loaded = h
                break
            }
        }
        guard let handle = loaded else { return (nil, nil) }

        let resolved = MobileDeviceSymbols(
            subscribe: resolveSymbol(handle, "AMDeviceNotificationSubscribe", as: FnNotificationSubscribe.self),
            unsubscribe: resolveSymbol(handle, "AMDeviceNotificationUnsubscribe", as: FnNotificationUnsubscribe.self),
            connect: resolveSymbol(handle, "AMDeviceConnect", as: FnDeviceConnect.self),
            disconnect: resolveSymbol(handle, "AMDeviceDisconnect", as: FnDeviceDisconnect.self),
            isPaired: resolveSymbol(handle, "AMDeviceIsPaired", as: FnDeviceIsPaired.self),
            validatePairing: resolveSymbol(handle, "AMDeviceValidatePairing", as: FnDeviceValidatePairing.self),
            startSession: resolveSymbol(handle, "AMDeviceStartSession", as: FnDeviceStartSession.self),
            stopSession: resolveSymbol(handle, "AMDeviceStopSession", as: FnDeviceStopSession.self),
            getInterfaceType: resolveSymbol(handle, "AMDeviceGetInterfaceType", as: FnDeviceGetInterfaceType.self),
            copyUDID: resolveSymbol(handle, "AMDeviceCopyDeviceIdentifier", as: FnDeviceCopyUDID.self),
            copyValue: resolveSymbol(handle, "AMDeviceCopyValue", as: FnDeviceCopyValue.self),
            secureStartService: resolveSymbol(handle, "AMDeviceSecureStartService", as: FnSecureStartService.self),
            serviceReceive: resolveSymbol(handle, "AMDServiceConnectionReceive", as: FnServiceReceive.self),
            serviceInvalidate: resolveSymbol(handle, "AMDServiceConnectionInvalidate", as: FnServiceInvalidate.self),
            serviceSendMessage: resolveSymbol(handle, "AMDServiceConnectionSendMessage", as: FnServiceSendMessage.self),
            serviceReceiveMessage: resolveSymbol(handle, "AMDServiceConnectionReceiveMessage", as: FnServiceReceiveMessage.self)
        )
        return (handle, resolved)
    }

    private static func resolveSymbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String, as type: T.Type) -> T? {
        guard let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: type)
    }

    public func startDeviceDiscovery() {
        let alreadySubscribed = stateLock.withLockUnchecked { $0.notificationRef != nil }
        guard !alreadySubscribed, let subscribe = symbols?.subscribe else { return }

        let box = CallbackBox(bridge: self)
        let retainedBox = Unmanaged.passRetained(box)
        var ref: OpaquePointer?
        let rc = subscribe({ infoPtr, userPtr in
            guard let infoPtr, let userPtr else { return }
            let callbackBox = Unmanaged<CallbackBox>.fromOpaque(userPtr).takeUnretainedValue()
            guard let bridge = callbackBox.bridge else { return }
            bridge.handleNotification(info: infoPtr.load(as: AMDeviceNotificationCallbackInfo.self))
        }, 0, 0, retainedBox.toOpaque(), &ref)

        if rc == 0, let ref {
            let (duplicateRef, shouldReleaseBox) = stateLock.withLockUnchecked { state -> (OpaquePointer?, Bool) in
                if state.notificationRef != nil {
                    return (ref, true)
                }
                state.notificationRef = ref
                state.callbackBox = retainedBox
                return (nil, false)
            }
            if let duplicateRef, let unsub = symbols?.unsubscribe {
                _ = unsub(duplicateRef)
            }
            if shouldReleaseBox {
                box.clear()
                retainedBox.release()
            }
        } else {
            box.clear()
            retainedBox.release()
        }
    }

    public func stopMonitoring() {
        stopSyslogStream()
        let (ref, retainedDevs, retainedBox) = stateLock.withLockUnchecked { state -> (OpaquePointer?, [OpaquePointer], Unmanaged<CallbackBox>?) in
            let r = state.notificationRef
            state.notificationRef = nil
            let box = state.callbackBox
            state.callbackBox = nil
            let devs = Array(state.deviceRefs.values)
            state.deviceRefs.removeAll()
            state.discoveredDevices.removeAll()
            return (r, devs, box)
        }
        retainedBox?.takeUnretainedValue().clear()
        if let ref, let unsub = symbols?.unsubscribe {
            _ = unsub(ref)
        }
        retainedBox?.release()
        for dev in retainedDevs {
            Self.releaseDeviceRef(dev)
        }
    }

    private func handleNotification(info: AMDeviceNotificationCallbackInfo) {
        guard let dev = info.dev, let symbols else { return }
        if info.msg == 1 {
            // 1 = Connected (prefer USB interface type == 1, or accept if unknown)
            let ifType = symbols.getInterfaceType?(dev) ?? 1
            if ifType != 1 { return }

            guard let udidCF = symbols.copyUDID?(dev)?.takeRetainedValue() else { return }
            let udid = udidCF as String

            let device = inspectDevice(dev, udid: udid)
            let (replacedDev, snapshot, callback) = stateLock.withLockUnchecked { state -> (OpaquePointer?, [ConnectedIOSDevice], (@Sendable ([ConnectedIOSDevice]) -> Void)?) in
                Self.retainDeviceRef(dev)
                let replaced = state.deviceRefs.updateValue(dev, forKey: udid)
                state.discoveredDevices[udid] = device
                let snap = Array(state.discoveredDevices.values).sorted { $0.deviceName < $1.deviceName }
                return (replaced, snap, state.onDevicesChanged)
            }
            if let replacedDev {
                Self.releaseDeviceRef(replacedDev)
            }
            callback?(snapshot)
        } else if info.msg == 2 {
            // 2 = Disconnected
            let udid: String?
            if let udidCF = symbols.copyUDID?(dev)?.takeRetainedValue() {
                udid = udidCF as String
            } else {
                udid = stateLock.withLockUnchecked { state in
                    state.deviceRefs.first(where: { $0.value == dev })?.key
                }
            }
            guard let udid else { return }

            let (removedDev, snapshot, callback) = stateLock.withLockUnchecked { state -> (OpaquePointer?, [ConnectedIOSDevice], (@Sendable ([ConnectedIOSDevice]) -> Void)?) in
                let removed = state.deviceRefs.removeValue(forKey: udid)
                state.discoveredDevices.removeValue(forKey: udid)
                let snap = Array(state.discoveredDevices.values).sorted { $0.deviceName < $1.deviceName }
                return (removed, snap, state.onDevicesChanged)
            }
            if let removedDev {
                Self.releaseDeviceRef(removedDev)
            }
            callback?(snapshot)
        }
    }

    private func inspectDevice(_ dev: OpaquePointer, udid: String) -> ConnectedIOSDevice {
        var paired = false
        var name = "iPhone"
        var productType = ""
        var productVersion = ""
        var buildVersion = ""
        var regionInfo = ""
        var modelNumber = ""

        if let symbols, symbols.connect?(dev) == 0 {
            defer { _ = symbols.disconnect?(dev) }
            let rawPaired = (symbols.isPaired?(dev) ?? 0) != 0
            paired = rawPaired && ((symbols.validatePairing?(dev) ?? 0) == 0)

            if paired, symbols.startSession?(dev) == 0 {
                name = copyStringValue(dev, key: "DeviceName") ?? name
                productType = copyStringValue(dev, key: "ProductType") ?? ""
                productVersion = copyStringValue(dev, key: "ProductVersion") ?? ""
                buildVersion = copyStringValue(dev, key: "BuildVersion") ?? ""
                regionInfo = copyStringValue(dev, key: "RegionInfo") ?? ""
                modelNumber = copyStringValue(dev, key: "RegulatoryModelNumber")
                    ?? copyStringValue(dev, key: "ModelNumber")
                    ?? ""
                discoverInstalledAIAppsLockedSession(dev)
                _ = symbols.stopSession?(dev)
            } else {
                name = copyStringValue(dev, key: "DeviceName") ?? name
            }
        }

        return ConnectedIOSDevice(
            id: udid,
            deviceName: name,
            productType: productType,
            productVersion: productVersion,
            buildVersion: buildVersion,
            regionInfo: regionInfo,
            modelNumber: modelNumber,
            isPaired: paired
        )
    }

    private func discoverInstalledAIAppsLockedSession(_ dev: OpaquePointer) {
        guard let fnSecureStartService = symbols?.secureStartService,
              let fnServiceSendMessage = symbols?.serviceSendMessage,
              let fnServiceReceiveMessage = symbols?.serviceReceiveMessage,
              let fnServiceInvalidate = symbols?.serviceInvalidate else { return }

        var instConn: OpaquePointer?
        guard fnSecureStartService(dev, "com.apple.mobile.installation_proxy" as CFString, nil, &instConn) == 0,
              let conn = instConn else {
            return
        }
        defer { fnServiceInvalidate(conn) }

        let req: NSDictionary = [
            "Command": "Lookup",
            "ClientOptions": [
                "ApplicationType": "User",
                "ReturnAttributes": [
                    "CFBundleIdentifier",
                    "CFBundleExecutable",
                    "CFBundleDisplayName",
                    "CFBundleName"
                ]
            ]
        ]

        // kCFPropertyListBinaryFormat_v1_0 = 200
        guard fnServiceSendMessage(conn, req, 200) == 0 else { return }
        var resp: Unmanaged<CFPropertyList>?
        guard fnServiceReceiveMessage(conn, &resp, nil) == 0,
              let dict = resp?.takeRetainedValue() as? [String: Any],
              let lookup = dict["LookupResult"] as? [String: [String: Any]] else {
            return
        }

        var discovered: [(bundleID: String, executable: String, displayName: String)] = []
        for (bundleID, info) in lookup {
            let exec = (info["CFBundleExecutable"] as? String) ?? ""
            let display = (info["CFBundleDisplayName"] as? String)
                ?? (info["CFBundleName"] as? String)
                ?? exec
            discovered.append((bundleID: bundleID, executable: exec, displayName: display))
        }
        LLMEndpointCatalog.registerDynamicIOSApps(discovered)
    }

    private func copyStringValue(_ dev: OpaquePointer, key: String) -> String? {
        guard let fnCopyValue = symbols?.copyValue else { return nil }
        guard let unmanaged = fnCopyValue(dev, nil, key as CFString) else { return nil }
        let val = unmanaged.takeRetainedValue()
        return val as? String
    }

    /// Connects to `com.apple.syslog_relay` over USB and streams filtered AI/PCC log lines read-only,
    /// automatically reconnecting if iOS resets or idles out the service socket.
    public func startSyslogStream(
        udid: String,
        onEvent: @escaping @Sendable (UnifiedLogEvent) -> Void,
        onStateChange: (@Sendable (Bool) -> Void)? = nil,
        onError: @escaping @Sendable (String) -> Void
    ) {
        let startResult = stateLock.withLockUnchecked { state -> (started: Bool, myGen: UInt64, oldConn: OpaquePointer?) in
            guard state.deviceRefs[udid] != nil, state.discoveredDevices[udid] != nil else {
                return (false, 0, nil)
            }
            state.streamGeneration &+= 1
            let gen = state.streamGeneration
            let old = state.activeServiceConn
            state.activeServiceConn = nil
            state.isStreamingActive = true
            return (true, gen, old)
        }

        guard startResult.started else {
            onStateChange?(false)
            onError("USB device \(udid) is not connected.")
            return
        }

        if let oldConn = startResult.oldConn {
            symbols?.serviceInvalidate?(oldConn)
        }
        onStateChange?(true)

        let myGen = startResult.myGen
        let symbols = self.symbols

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            guard let symbols,
                  let fnConnect = symbols.connect,
                  let fnDisconnect = symbols.disconnect,
                  let fnIsPaired = symbols.isPaired,
                  let fnValidatePairing = symbols.validatePairing,
                  let fnStartSession = symbols.startSession,
                  let fnStopSession = symbols.stopSession,
                  let fnSecureStartService = symbols.secureStartService,
                  let fnServiceReceive = symbols.serviceReceive,
                  let fnServiceInvalidate = symbols.serviceInvalidate else {
                let didFail = self.stateLock.withLockUnchecked { state -> Bool in
                    guard state.streamGeneration == myGen else { return false }
                    state.isStreamingActive = false
                    return true
                }
                if didFail {
                    onStateChange?(false)
                }
                onError("MobileDevice.framework symbols unavailable.")
                return
            }

            var buffer = [UInt8](repeating: 0, count: 8192)
            var lineAccumulator = Data()
            var consecutiveFailures = 0

            while true {
                let iteration = self.stateLock.withLockUnchecked { state -> (validGen: Bool, dev: OpaquePointer?, deviceInfo: ConnectedIOSDevice?) in
                    guard state.streamGeneration == myGen,
                          let dev = state.deviceRefs[udid],
                          let deviceInfo = state.discoveredDevices[udid] else {
                        return (false, nil, nil)
                    }
                    Self.retainDeviceRef(dev)
                    return (true, dev, deviceInfo)
                }

                guard iteration.validGen, let dev = iteration.dev, let deviceInfo = iteration.deviceInfo else {
                    break
                }
                defer { Self.releaseDeviceRef(dev) }

                guard fnConnect(dev) == 0 else {
                    consecutiveFailures += 1
                    if consecutiveFailures >= 6 {
                        onError("Failed to connect to USB device.")
                        break
                    }
                    Thread.sleep(forTimeInterval: 0.8)
                    continue
                }

                if fnIsPaired(dev) == 0 || fnValidatePairing(dev) != 0 {
                    _ = fnDisconnect(dev)
                    onError("PAIRING_REQUIRED: 请在 iPhone 屏幕点击「信任此电脑」并输入锁屏密码 / Please tap Trust This Computer on iPhone and enter passcode.")
                    break
                }

                guard fnStartSession(dev) == 0 else {
                    _ = fnDisconnect(dev)
                    consecutiveFailures += 1
                    if consecutiveFailures >= 6 {
                        onError("Failed to start lockdown session with iPhone.")
                        break
                    }
                    Thread.sleep(forTimeInterval: 0.8)
                    continue
                }

                var serviceConn: OpaquePointer?
                let startRC = fnSecureStartService(dev, "com.apple.syslog_relay" as CFString, nil, &serviceConn)
                _ = fnStopSession(dev)
                _ = fnDisconnect(dev)

                guard startRC == 0, let conn = serviceConn else {
                    consecutiveFailures += 1
                    if consecutiveFailures >= 6 {
                        onError("Unable to start com.apple.syslog_relay (code \(startRC)). Ensure iPhone is unlocked.")
                        break
                    }
                    Thread.sleep(forTimeInterval: 0.8)
                    continue
                }

                consecutiveFailures = 0
                lineAccumulator.removeAll(keepingCapacity: true)

                let attached = self.stateLock.withLockUnchecked { state -> Bool in
                    guard state.streamGeneration == myGen else { return false }
                    state.activeServiceConn = conn
                    return true
                }
                if !attached {
                    fnServiceInvalidate(conn)
                    break
                }

                let deviceLabel = deviceInfo.displayTitle

                while true {
                    let keepRunning = self.stateLock.withLockUnchecked { $0.streamGeneration == myGen }
                    if !keepRunning { break }

                    let bytesRead = fnServiceReceive(conn, &buffer, buffer.count)
                    if bytesRead <= 0 { break }

                    lineAccumulator.append(contentsOf: buffer[0..<Int(bytesRead)])
                    var scanIndex = lineAccumulator.startIndex
                    while scanIndex < lineAccumulator.endIndex,
                          let sepIdx = lineAccumulator[scanIndex...].firstIndex(where: { $0 == 0x0A || $0 == 0x00 }) {
                        let slice = lineAccumulator[scanIndex..<sepIdx]
                        if !slice.isEmpty,
                           let rawText = String(data: slice, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                           !rawText.isEmpty,
                           let event = Self.parseSyslogRelayLine(rawText, sourceDevice: deviceLabel) {
                            onEvent(event)
                        }
                        scanIndex = lineAccumulator.index(after: sepIdx)
                    }
                    if scanIndex > lineAccumulator.startIndex {
                        lineAccumulator.removeSubrange(lineAccumulator.startIndex..<scanIndex)
                    }
                }

                fnServiceInvalidate(conn)
                let shouldReconnect = self.stateLock.withLockUnchecked { state -> Bool in
                    if state.activeServiceConn == conn {
                        state.activeServiceConn = nil
                    }
                    return state.streamGeneration == myGen && state.deviceRefs[udid] != nil
                }

                guard shouldReconnect else { break }
                Thread.sleep(forTimeInterval: 0.4)
            }

            let didStopOwner = self.stateLock.withLockUnchecked { state -> Bool in
                guard state.streamGeneration == myGen else { return false }
                state.isStreamingActive = false
                state.activeServiceConn = nil
                return true
            }
            if didStopOwner {
                onStateChange?(false)
            }
        }
    }

    public func stopSyslogStream() {
        let conn = stateLock.withLockUnchecked { state -> OpaquePointer? in
            state.streamGeneration &+= 1
            state.isStreamingActive = false
            let existing = state.activeServiceConn
            state.activeServiceConn = nil
            return existing
        }
        if let conn {
            symbols?.serviceInvalidate?(conn)
        }
    }

    public static func parseSyslogRelayLine(_ rawLine: String, sourceDevice: String) -> UnifiedLogEvent? {
        // Typical iOS syslog_relay prefix:
        // "Nov 15 22:10:05 iPhone Claude(CFNetwork)[1234] <Notice>: message..."
        var proc = "iOS"
        var pid: Int32 = 0
        var sub = "ios.syslog_relay"
        if let bracketIdx = rawLine.firstIndex(of: "[") {
            let prefix = rawLine[..<bracketIdx].split(separator: " ")
            if let lastToken = prefix.last {
                let rawProcToken = String(lastToken)
                proc = LLMEndpointCatalog.normalizeProcessName(rawProcToken)
                if let openParen = rawProcToken.firstIndex(of: "("),
                   let closeParen = rawProcToken.lastIndex(of: ")"),
                   openParen < closeParen {
                    let framework = String(rawProcToken[rawProcToken.index(after: openParen)..<closeParen])
                    if !framework.isEmpty {
                        sub = framework
                    }
                }
            }
            let afterBracket = rawLine[rawLine.index(after: bracketIdx)...]
            if let closeBracket = afterBracket.firstIndex(of: "]"),
               let parsedPID = Int32(afterBracket[..<closeBracket]) {
                pid = parsedPID
            }
        }

        let lowerProc = proc.lowercased()
        let lowerSub = sub.lowercased()
        let lowerLine = rawLine.lowercased()
        if lowerProc == "kernel" || pid == 0
            || lowerLine.contains("appleh16aneinterface")
            || lowerLine.contains("cleanuprtbuddyendpoints") {
            return nil
        }

        let matchesProcess = relevantProcessNames.contains(lowerProc)
            || lowerProc.contains("visualintelligence")
            || lowerProc.contains("generativeexperiences")
            || lowerProc.contains("tgondeviceinference")
        let matchesSubsystem = relevantSubsystemTokens.contains { lowerSub.contains($0) }

        let dynamicExecs = LLMEndpointCatalog.dynamicIOSExecutableKeywords()
        let matchesDynamicApp = dynamicExecs.contains { token in
            if token.contains(".") {
                return lowerLine.contains(token)
            }
            return lowerProc == token || lowerLine.contains("<\(token)") || lowerLine.contains(" \(token)(")
        }

        let matchesHighPrecisionToken = highPrecisionTokens.contains { lowerLine.contains($0) }
        let matchesAIClientToken = knownAIClientTokens.contains { lowerLine.contains($0) }

        let hasBundleLifecycleMarker = lowerLine.contains("app<com.")
            || lowerLine.contains("application<com.")
            || lowerLine.contains("sceneid:")
        let matchesRelevantBundleLifecycle = hasBundleLifecycleMarker && (
            matchesAIClientToken
                || knownAppleAIBundleTokens.contains { lowerLine.contains($0) }
                || matchesDynamicApp
        )

        guard matchesProcess
                || matchesSubsystem
                || matchesHighPrecisionToken
                || matchesAIClientToken
                || matchesRelevantBundleLifecycle
                || matchesDynamicApp else {
            return nil
        }

        return UnifiedLogEvent(
            timestamp: Date(),
            processName: proc,
            processID: pid,
            subsystem: sub,
            category: "",
            message: rawLine,
            sourceDevice: sourceDevice
        )
    }

    /// Offline read-only importer for `.log` / `.txt` / `.ips` log snippets.
    public static func importLogTextFile(url: URL) throws -> [UnifiedLogEvent] {
        let text = try String(contentsOf: url, encoding: .utf8)
        let label = "Imported (\(url.lastPathComponent))"
        return text
            .split(separator: "\n")
            .map { String($0) }
            .compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return UnifiedLogEvent(
                    timestamp: Date(),
                    processName: "ImportedLog",
                    subsystem: "file.import",
                    message: trimmed,
                    sourceDevice: label
                )
            }
    }
}
