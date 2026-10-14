import Foundation

struct PiGatewayDeploymentConfiguration: Equatable, Sendable {
    enum Environment: String, CaseIterable, Sendable {
        case debug
        case qa
        case productionCandidate = "production-candidate"
        case production

        var requiredBaseURL: URL {
            switch self {
            case .debug: URL(string: "https://jonwork.com")!
            case .qa: URL(string: "https://qa.agent.jonwork.com")!
            case .productionCandidate: URL(string: "https://candidate.agent.jonwork.com")!
            case .production: URL(string: "https://jonwork.com")!
            }
        }
    }

    static let environmentInfoKey = "JonworkGatewayEnvironment"
    static let baseURLInfoKey = "JonworkGatewayBaseURL"

    let environment: Environment
    let baseURL: URL

    static var live: Self {
        do {
            return try resolve(infoDictionary: Bundle.main.infoDictionary ?? [:])
        } catch {
            preconditionFailure("Invalid bundled Jonwork Gateway deployment configuration: \(error)")
        }
    }

    static func resolve(infoDictionary: [String: Any]) throws -> Self {
        guard let rawEnvironment = infoDictionary[environmentInfoKey] as? String,
              let environment = Environment(rawValue: rawEnvironment)
        else { throw PiGatewayDeploymentConfigurationError.invalidEnvironment }
        guard let rawBaseURL = infoDictionary[baseURLInfoKey] as? String,
              let baseURL = URL(string: rawBaseURL),
              baseURL.scheme?.lowercased() == "https",
              baseURL.user == nil,
              baseURL.password == nil,
              baseURL.query == nil,
              baseURL.fragment == nil,
              baseURL.path.isEmpty
        else { throw PiGatewayDeploymentConfigurationError.invalidBaseURL }
        guard baseURL == environment.requiredBaseURL else {
            throw PiGatewayDeploymentConfigurationError.environmentURLMismatch
        }
        return .init(environment: environment, baseURL: baseURL)
    }

    func accepts(_ profile: PiServerProfile?) -> Bool {
        profile?.baseURL == baseURL
    }
}

enum PiGatewayDeploymentConfigurationError: Error, Equatable {
    case invalidEnvironment
    case invalidBaseURL
    case environmentURLMismatch
}
