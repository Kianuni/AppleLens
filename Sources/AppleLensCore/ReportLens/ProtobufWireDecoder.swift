import Foundation

public enum ProtoWireType: Int, Sendable {
    case varint = 0
    case fixed64 = 1
    case lengthDelimited = 2
    case startGroup = 3
    case endGroup = 4
    case fixed32 = 5
}

public enum ProtoWireValue: Sendable, Hashable {
    case varint(UInt64)
    case fixed64(UInt64)
    case lengthDelimited(Data)
    case fixed32(UInt32)

    public var asData: Data? {
        if case .lengthDelimited(let data) = self { return data }
        return nil
    }

    public var asString: String? {
        guard case .lengthDelimited(let data) = self else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public var asUInt64: UInt64? {
        switch self {
        case .varint(let v): return v
        case .fixed64(let v): return v
        case .fixed32(let v): return UInt64(v)
        case .lengthDelimited: return nil
        }
    }

    public var asSubmessageFields: [ProtoField]? {
        guard case .lengthDelimited(let data) = self else { return nil }
        return try? ProtobufWireDecoder.decodeFields(from: data)
    }
}

public struct ProtoField: Sendable, Hashable {
    public let number: Int
    public let value: ProtoWireValue

    public init(number: Int, value: ProtoWireValue) {
        self.number = number
        self.value = value
    }
}

public enum ProtobufWireError: Error, LocalizedError {
    case truncatedVarint
    case truncatedPayload
    case invalidFieldNumber
    case unsupportedWireType(Int)

    public var errorDescription: String? {
        switch self {
        case .truncatedVarint: return "Truncated protobuf varint"
        case .truncatedPayload: return "Truncated protobuf payload"
        case .invalidFieldNumber: return "Invalid protobuf field number (0)"
        case .unsupportedWireType(let t): return "Unsupported protobuf wire type \(t)"
        }
    }
}

/// Pure Swift bounds-checked Protobuf Wire-Format decoder + minimal encoder for fixtures.
/// Avoids external SwiftProtobuf dependencies and works on retail macOS without SIP `allow-research-guests`.
public enum ProtobufWireDecoder {
    public static func decodeFields(from data: Data) throws -> [ProtoField] {
        var fields: [ProtoField] = []
        var offset = data.startIndex
        let end = data.endIndex

        while offset < end {
            let tag = try readVarint(data: data, offset: &offset)
            let fieldNumber = Int(tag >> 3)
            let rawWireType = Int(tag & 0x07)
            guard fieldNumber > 0 else {
                throw ProtobufWireError.invalidFieldNumber
            }
            guard let wireType = ProtoWireType(rawValue: rawWireType) else {
                throw ProtobufWireError.unsupportedWireType(rawWireType)
            }

            switch wireType {
            case .varint:
                let val = try readVarint(data: data, offset: &offset)
                fields.append(ProtoField(number: fieldNumber, value: .varint(val)))

            case .fixed64:
                guard offset + 8 <= end else { throw ProtobufWireError.truncatedPayload }
                var raw: UInt64 = 0
                for i in 0..<8 {
                    raw |= UInt64(data[offset + i]) << (i * 8)
                }
                offset += 8
                fields.append(ProtoField(number: fieldNumber, value: .fixed64(raw)))

            case .lengthDelimited:
                let lenU64 = try readVarint(data: data, offset: &offset)
                guard lenU64 <= UInt64(end - offset) else { throw ProtobufWireError.truncatedPayload }
                let length = Int(lenU64)
                let slice = data.subdata(in: offset..<(offset + length))
                offset += length
                fields.append(ProtoField(number: fieldNumber, value: .lengthDelimited(slice)))

            case .fixed32:
                guard offset + 4 <= end else { throw ProtobufWireError.truncatedPayload }
                var raw: UInt32 = 0
                for i in 0..<4 {
                    raw |= UInt32(data[offset + i]) << (i * 8)
                }
                offset += 4
                fields.append(ProtoField(number: fieldNumber, value: .fixed32(raw)))

            case .startGroup, .endGroup:
                throw ProtobufWireError.unsupportedWireType(rawWireType)
            }
        }
        return fields
    }

    public static func decodeTimestamp(_ data: Data) -> Date? {
        guard let fields = try? decodeFields(from: data) else { return nil }
        var seconds: Int64 = 0
        var nanos: Int32 = 0
        for f in fields {
            if f.number == 1, let v = f.value.asUInt64 {
                seconds = Int64(bitPattern: v)
            } else if f.number == 2, let v = f.value.asUInt64 {
                nanos = Int32(truncatingIfNeeded: v)
            }
        }
        guard seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds) + TimeInterval(nanos) / 1_000_000_000.0)
    }

    private static func readVarint(data: Data, offset: inout Int) throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while offset < data.endIndex {
            let byte = data[offset]
            offset += 1
            result |= UInt64(byte & 0x7F) << shift
            if (byte & 0x80) == 0 {
                return result
            }
            shift += 7
            if shift >= 64 {
                throw ProtobufWireError.truncatedVarint
            }
        }
        throw ProtobufWireError.truncatedVarint
    }
}

public enum ProtobufWireEncoder {
    public static func encodeVarint(_ value: UInt64) -> Data {
        var v = value
        var out = Data()
        while v >= 0x80 {
            out.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        out.append(UInt8(v))
        return out
    }

    public static func varintField(_ number: Int, value: UInt64) -> Data {
        var d = encodeVarint(UInt64((number << 3) | 0))
        d.append(encodeVarint(value))
        return d
    }

    public static func bytesField(_ number: Int, data: Data) -> Data {
        var d = encodeVarint(UInt64((number << 3) | 2))
        d.append(encodeVarint(UInt64(data.count)))
        d.append(data)
        return d
    }

    public static func stringField(_ number: Int, _ string: String) -> Data {
        bytesField(number, data: Data(string.utf8))
    }

    public static func timestampField(_ number: Int, date: Date) -> Data {
        let secs = UInt64(max(0, Int64(date.timeIntervalSince1970)))
        var payload = varintField(1, value: secs)
        payload.append(varintField(2, value: 0))
        return bytesField(number, data: payload)
    }
}
