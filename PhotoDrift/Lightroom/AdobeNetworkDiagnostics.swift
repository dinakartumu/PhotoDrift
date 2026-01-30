import Foundation
import Network
import Security

enum AdobeNetworkDiagnostics {
    static func run(host: String) async -> String {
        var lines: [String] = []
        lines.append("[AdobeNetworkDiagnostics] host=\(host)")
        lines.append("[AdobeNetworkDiagnostics] date=\(ISO8601DateFormatter().string(from: Date()))")
        lines.append(contentsOf: entitlementsSummary())

        if let path = await firstPathUpdate(timeoutSeconds: 2.0) {
            lines.append("[AdobeNetworkDiagnostics] path.status=\(path.status)")
            lines.append("[AdobeNetworkDiagnostics] path.isExpensive=\(path.isExpensive)")
            lines.append("[AdobeNetworkDiagnostics] path.isConstrained=\(path.isConstrained)")
            lines.append("[AdobeNetworkDiagnostics] path.usesWiFi=\(path.usesInterfaceType(.wifi))")
            lines.append("[AdobeNetworkDiagnostics] path.usesCellular=\(path.usesInterfaceType(.cellular))")
            lines.append("[AdobeNetworkDiagnostics] path.usesWired=\(path.usesInterfaceType(.wiredEthernet))")
            lines.append("[AdobeNetworkDiagnostics] path.usesOther=\(path.usesInterfaceType(.other))")
        } else {
            lines.append("[AdobeNetworkDiagnostics] path.status=timeout")
        }

        let dnsResult = resolveHost(host)
        lines.append("[AdobeNetworkDiagnostics] dns.result=\(dnsResult.summary)")
        for address in dnsResult.addresses {
            lines.append("[AdobeNetworkDiagnostics] dns.address=\(address)")
        }
        if let error = dnsResult.error {
            lines.append("[AdobeNetworkDiagnostics] dns.error=\(error)")
        }

        return lines.joined(separator: "\n")
    }

    private static func entitlementsSummary() -> [String] {
        guard let task = SecTaskCreateFromSelf(nil) else {
            return ["[AdobeNetworkDiagnostics] entitlements=unavailable"]
        }
        let sandbox = boolEntitlement(task, "com.apple.security.app-sandbox")
        let networkClient = boolEntitlement(task, "com.apple.security.network.client")
        let networkServer = boolEntitlement(task, "com.apple.security.network.server")
        return [
            "[AdobeNetworkDiagnostics] entitlements.app-sandbox=\(sandbox ?? false)",
            "[AdobeNetworkDiagnostics] entitlements.network-client=\(networkClient ?? false)",
            "[AdobeNetworkDiagnostics] entitlements.network-server=\(networkServer ?? false)",
        ]
    }

    private static func boolEntitlement(_ task: SecTask, _ name: String) -> Bool? {
        let value = SecTaskCopyValueForEntitlement(task, name as CFString, nil)
        guard let boolValue = value as? Bool else { return nil }
        return boolValue
    }

    private static func firstPathUpdate(timeoutSeconds: TimeInterval) async -> NWPath? {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "AdobeNetworkDiagnostics.NWPathMonitor")
            var didResume = false

            func resume(with path: NWPath?) {
                guard !didResume else { return }
                didResume = true
                monitor.cancel()
                continuation.resume(returning: path)
            }

            monitor.pathUpdateHandler = { path in
                resume(with: path)
            }
            monitor.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeoutSeconds) {
                resume(with: nil)
            }
        }
    }

    private struct DNSResult {
        let addresses: [String]
        let error: String?
        let summary: String
    }

    private static func resolveHost(_ host: String) -> DNSResult {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP

        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, nil, &hints, &result)
        guard status == 0 else {
            let message = String(cString: gai_strerror(status))
            return DNSResult(addresses: [], error: message, summary: "error")
        }
        defer { freeaddrinfo(result) }

        var addresses: [String] = []
        var cursor = result
        while let addr = cursor?.pointee {
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let infoStatus = getnameinfo(
                addr.ai_addr,
                addr.ai_addrlen,
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            if infoStatus == 0 {
                let ip = String(cString: hostname)
                if !addresses.contains(ip) {
                    addresses.append(ip)
                }
            }
            cursor = addr.ai_next
        }

        return DNSResult(addresses: addresses, error: nil, summary: "ok")
    }
}
