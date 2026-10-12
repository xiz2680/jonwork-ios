@testable import FlowDown
import Foundation
import Storage
import Testing

struct LocalModelConfigurationSmokeTests {
    @Test
    func `root fdmodel files decode as cloud models when present`() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let candidates = try FileManager.default.contentsOfDirectory(
            at: repositoryRoot,
            includingPropertiesForKeys: nil,
        )
        .filter { $0.pathExtension == ModelManager.flowdownModelConfigurationExtension }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !candidates.isEmpty else {
            return
        }

        let decoder = PropertyListDecoder()

        for url in candidates {
            let model = try decoder.decode(CloudModel.self, from: Data(contentsOf: url))

            #expect(!model.model_identifier.isEmpty)
            #expect(!model.endpoint.isEmpty)
            #expect(!model.token.isEmpty)

            if let inferredFormat = CloudModel.ResponseFormat.inferredFormat(fromEndpoint: model.endpoint) {
                #expect(inferredFormat == model.response_format)
            }
        }
    }
}
