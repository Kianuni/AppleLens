import Darwin
import Foundation
import os
import SystemConfiguration

public struct SystemProxyInfo: Sendable, Hashable {
    public let httpEnabled: Bool
    public let httpHost: String?
    public let httpPort: Int?
    public let httpsEnabled: Bool
    public let httpsHost: String?
    public let httpsPort: Int?
    public let socksEnabled: Bool
    public let socksHost: String?
    public let socksPort: Int?
    public let exceptionsList: [String]

    public var activeLocalProxyPorts: Set<UInt16> {
        var ports: Set<UInt16> = []
        if httpEnabled, let host = httpHost, Self.isLoopback(host), let p = httpPort, p > 0 {
            ports.insert(UInt16(p))
        }
        if httpsEnabled, let host = httpsHost, Self.isLoopback(host), let p = httpsPort, p > 0 {
            ports.insert(UInt16(p))
        }
        if socksEnabled, let host = socksHost, Self.isLoopback(host), let p = socksPort, p > 0 {
            ports.insert(UInt16(p))
        }
        return ports
    }

    public static func isLoopback(_ host: String) -> Bool {
        host == "127.0.0.1" || host == "::1" || host.lowercased() == "localhost"
    }

    public static func current() -> SystemProxyInfo {
        guard let cfDict = SCDynamicStoreCopyProxies(nil),
              let dict = cfDict as NSDictionary as? [String: Any] else {
            return SystemProxyInfo(
                httpEnabled: false, httpHost: nil, httpPort: nil,
                httpsEnabled: false, httpsHost: nil, httpsPort: nil,
                socksEnabled: false, socksHost: nil, socksPort: nil,
                exceptionsList: []
            )
        }
        return SystemProxyInfo(
            httpEnabled: (dict[kSCPropNetProxiesHTTPEnable as String] as? Int ?? 0) == 1,
            httpHost: dict[kSCPropNetProxiesHTTPProxy as String] as? String,
            httpPort: dict[kSCPropNetProxiesHTTPPort as String] as? Int,
            httpsEnabled: (dict[kSCPropNetProxiesHTTPSEnable as String] as? Int ?? 0) == 1,
            httpsHost: dict[kSCPropNetProxiesHTTPSProxy as String] as? String,
            httpsPort: dict[kSCPropNetProxiesHTTPSPort as String] as? Int,
            socksEnabled: (dict[kSCPropNetProxiesSOCKSEnable as String] as? Int ?? 0) == 1,
            socksHost: dict[kSCPropNetProxiesSOCKSProxy as String] as? String,
            socksPort: dict[kSCPropNetProxiesSOCKSPort as String] as? Int,
            exceptionsList: dict[kSCPropNetProxiesExceptionsList as String] as? [String] ?? []
        )
    }
}

public struct ProcessBundleMetadata: Sendable, Hashable {
    public let executablePath: String
    public let executableName: String
    public let appName: String
    public let bundleID: String?
    public let appBundlePath: String?

    public var identityKey: String {
        bundleID ?? appBundlePath ?? executablePath
    }
}

public struct RawSocketConnection: Sendable, Hashable {
    public let pid: Int32
    public let metadata: ProcessBundleMetadata
    public let remoteIP: String
    public let remotePort: UInt16
    public let localPort: UInt16
    public let isUDP: Bool
}

public final class ProcessSocketScanner: Sendable {
    private static let maxMetadataCacheEntries = 512
    private let metadataCache = OSAllocatedUnfairLock(initialState: [String: ProcessBundleMetadata]())

    public init() {}

    public var cachedMetadataCount: Int {
        metadataCache.withLock { $0.count }
    }

    /// Resolves a binary executable path (e.g. `/Applications/Antigravity.app/Contents/Resources/bin/language_server`)
    /// to its outermost `.app` bundle metadata so helper subprocesses roll up cleanly to their desktop App.
    public func resolveBundleMetadata(executablePath: String) -> ProcessBundleMetadata {
        if let cached = metadataCache.withLock({ $0[executablePath] }) {
            return cached
        }

        let url = URL(fileURLWithPath: executablePath)
        let executableName = url.lastPathComponent
        var appName = executableName
        var bundleID: String?
        var appBundlePath: String?

        if let outerAppPath = Self.outermostAppBundlePath(for: executablePath) {
            appBundlePath = outerAppPath
            let plistURL = URL(fileURLWithPath: outerAppPath).appendingPathComponent("Contents/Info.plist")
            if let data = try? Data(contentsOf: plistURL),
               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                bundleID = plist["CFBundleIdentifier"] as? String
                appName = (plist["CFBundleDisplayName"] as? String)
                    ?? (plist["CFBundleName"] as? String)
                    ?? URL(fileURLWithPath: outerAppPath).deletingPathExtension().lastPathComponent
            } else {
                appName = URL(fileURLWithPath: outerAppPath).deletingPathExtension().lastPathComponent
            }
        }

        let meta = ProcessBundleMetadata(
            executablePath: executablePath,
            executableName: executableName,
            appName: appName,
            bundleID: bundleID,
            appBundlePath: appBundlePath
        )

        metadataCache.withLock { cache in
            if cache[executablePath] == nil && cache.count >= Self.maxMetadataCacheEntries {
                let evictCount = cache.count / 2
                for key in cache.keys.prefix(evictCount) {
                    cache.removeValue(forKey: key)
                }
            }
            cache[executablePath] = meta
        }
        return meta
    }

    public static func outermostAppBundlePath(for executablePath: String) -> String? {
        let components = (executablePath as NSString).pathComponents
        var rebuilt: [String] = []
        for comp in components {
            rebuilt.append(comp)
            if comp.hasSuffix(".app") && comp.count > 4 {
                return NSString.path(withComponents: rebuilt)
            }
        }
        return nil
    }

    private struct PendingSocketDescriptor {
        let remoteIP: String
        let remotePort: UInt16
        let localPort: UInt16
        let isUDP: Bool
    }

    /// Scans active TCP (ESTABLISHED / SYN_SENT) and connected UDP :443 sockets across all readable PIDs
    /// using Darwin `libproc` without spawning child processes or requiring NetworkExtension.
    public func scanActiveOutboundSockets(localProxyPorts: Set<UInt16> = []) -> [RawSocketConnection] {
        var estimated = proc_listallpids(nil, 0)
        if estimated <= 0 { estimated = 1024 }
        var pids = [pid_t](repeating: 0, count: Int(estimated) * 2)
        let byteCount = Int32(pids.count * MemoryLayout<pid_t>.stride)
        let actualCount = Int(proc_listallpids(&pids, byteCount))
        guard actualCount > 0 else { return [] }

        var results: [RawSocketConnection] = []
        let fdStride = MemoryLayout<proc_fdinfo>.stride
        let sockSize = Int32(MemoryLayout<socket_fdinfo>.stride)
        var pathBuf = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)

        for index in 0..<actualCount {
            let pid = pids[index]
            if pid <= 0 { continue }

            let bufSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
            guard bufSize > 0 else { continue }

            let fdCapacity = Int(bufSize) / fdStride
            guard fdCapacity > 0 else { continue }
            var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: fdCapacity)
            let actualFdBytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, bufSize)
            guard actualFdBytes > 0 else { continue }
            let fdCount = min(Int(actualFdBytes) / fdStride, fdCapacity)

            var pendingSockets: [PendingSocketDescriptor] = []

            for j in 0..<fdCount where fds[j].proc_fdtype == PROX_FDTYPE_SOCKET {
                var sock = socket_fdinfo()
                let got = proc_pidfdinfo(pid, fds[j].proc_fd, PROC_PIDFDSOCKETINFO, &sock, sockSize)
                guard got == sockSize else { continue }

                let kind = sock.psi.soi_kind
                if kind == SOCKINFO_TCP {
                    let state = sock.psi.soi_proto.pri_tcp.tcpsi_state
                    guard state == TSI_S_ESTABLISHED || state == TSI_S_SYN_SENT else { continue }
                    let ini = sock.psi.soi_proto.pri_tcp.tcpsi_ini
                    let remotePort = UInt16(truncatingIfNeeded: ini.insi_fport).bigEndian
                    let localPort = UInt16(truncatingIfNeeded: ini.insi_lport).bigEndian
                    guard remotePort == 443 || localProxyPorts.contains(remotePort) else { continue }

                    if let remoteIP = Self.extractRemoteIP(from: ini) {
                        pendingSockets.append(PendingSocketDescriptor(
                            remoteIP: remoteIP,
                            remotePort: remotePort,
                            localPort: localPort,
                            isUDP: false
                        ))
                    }
                } else if kind == SOCKINFO_IN {
                    let ini = sock.psi.soi_proto.pri_in
                    let remotePort = UInt16(truncatingIfNeeded: ini.insi_fport).bigEndian
                    let localPort = UInt16(truncatingIfNeeded: ini.insi_lport).bigEndian
                    guard remotePort == 443 else { continue }

                    if let remoteIP = Self.extractRemoteIP(from: ini) {
                        pendingSockets.append(PendingSocketDescriptor(
                            remoteIP: remoteIP,
                            remotePort: remotePort,
                            localPort: localPort,
                            isUDP: true
                        ))
                    }
                }
            }

            guard !pendingSockets.isEmpty else { continue }

            // Lazy resolution: only invoke proc_pidpath + Info.plist lookup once for PIDs with matching sockets.
            pathBuf[0] = 0
            let pathLen = proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count))
            let execPath: String
            if pathLen > 0 {
                execPath = LLMEndpointCatalog.decodeNullTerminatedCString(pathBuf)
            } else {
                execPath = "pid:\(pid)"
            }

            let meta = resolveBundleMetadata(executablePath: execPath)
            if LLMEndpointCatalog.isExcludedProxyProcess(
                executableName: meta.executableName,
                bundleID: meta.bundleID,
                bundlePath: meta.appBundlePath
            ) {
                continue
            }

            for pending in pendingSockets {
                results.append(RawSocketConnection(
                    pid: pid,
                    metadata: meta,
                    remoteIP: pending.remoteIP,
                    remotePort: pending.remotePort,
                    localPort: pending.localPort,
                    isUDP: pending.isUDP
                ))
            }
        }

        return results
    }

    private static func extractRemoteIP(from ini: in_sockinfo) -> String? {
        if ini.insi_vflag == UInt8(INI_IPV4) {
            var addr = ini.insi_faddr.ina_46.i46a_addr4
            if addr.s_addr == 0 { return nil }
            var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &addr, &buf, socklen_t(INET_ADDRSTRLEN)) != nil else {
                return nil
            }
            return LLMEndpointCatalog.decodeNullTerminatedCString(buf)
        } else if ini.insi_vflag == UInt8(INI_IPV6) {
            var addr6 = ini.insi_faddr.ina_6
            var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            guard inet_ntop(AF_INET6, &addr6, &buf, socklen_t(INET6_ADDRSTRLEN)) != nil else {
                return nil
            }
            let ip = LLMEndpointCatalog.decodeNullTerminatedCString(buf)
            if ip == "::" || ip == "::1" { return nil }
            return ip
        }
        return nil
    }
}
