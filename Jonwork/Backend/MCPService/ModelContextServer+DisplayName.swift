import Foundation
import Storage

extension ModelContextServer {
    var displayName: String {
        if !name.isEmpty {
            return name
        }
        if let host = URL(string: endpoint)?.host, !host.isEmpty {
            return host
        }
        return String(localized: "Unknown Server")
    }

    var decoratedDisplayName: String {
        guard let host = URL(string: endpoint)?.host, !host.isEmpty else {
            return displayName
        }
        if !name.isEmpty {
            return "\(name) • @\(host)"
        }
        return "@\(host)"
    }
}
