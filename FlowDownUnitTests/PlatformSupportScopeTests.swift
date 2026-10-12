@testable import FlowDown
import Testing

struct PlatformSupportScopeTests {
    @MainActor
    @Test
    func `platform support helpers remain safe to evaluate during unit tests`() {
        #if targetEnvironment(macCatalyst)
            FLDCatalystHelper.shared.install()
        #endif

        #expect(Bool(true))
    }
}
