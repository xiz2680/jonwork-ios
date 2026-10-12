import FlowDownModelExchange
import Foundation

extension ModelExchangeCapability {
    var displayName: String {
        switch self {
        case .audio:
            String(localized: "Audio")
        case .visual:
            String(localized: "Visual")
        case .tool:
            String(localized: "Tool")
        case .developerRole:
            String(localized: "Role")
        }
    }

    static func summary(from capabilities: [ModelExchangeCapability]) -> String {
        let names = capabilities.map(\.displayName)
        return names.isEmpty ? String(localized: "None") : names.joined(separator: ", ")
    }
}
