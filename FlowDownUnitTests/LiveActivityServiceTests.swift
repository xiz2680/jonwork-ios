@testable import FlowDown
import Foundation
import Testing

#if canImport(ActivityKit) && os(iOS) && !targetEnvironment(macCatalyst)
    @Suite(.serialized)
    struct LiveActivityServiceTests {
        @Test
        @MainActor
        func `update creates a live activity and forwards later updates through the injected controller`() async throws {
            let controller = LiveActivityControllerSpy()
            let service = LiveActivityService(
                existingActivityProvider: { nil },
                activityControllerFactory: { _, state in
                    controller.recordRequest(state)
                    return controller
                },
                executingSessionCountProvider: { 1 },
            )

            service.update(
                conversationCount: 2,
                streamingSessionTextCount: 8,
                enabled: true,
            )
            service.update(
                conversationCount: 3,
                streamingSessionTextCount: 13,
                enabled: true,
            )
            try await waitUntil {
                controller.requestedStates().count == 1 && controller.updatedStates().count == 1
            }

            let requestedStates = controller.requestedStates()
            let updatedStates = controller.updatedStates()

            #expect(requestedStates.count == 1)
            #expect(requestedStates.first?.conversationCount == 2)
            #expect(updatedStates.last?.conversationCount == 3)
            #expect(updatedStates.last?.streamingSessionTextCount == 13)
        }

        @Test
        @MainActor
        func `appDidEnterForeground ends existing activities when no sessions are running`() async throws {
            let controller = LiveActivityControllerSpy()
            let service = LiveActivityService(
                existingActivityProvider: { controller },
                activityControllerFactory: { _, _ in
                    Issue.record("No new live activity should be requested in this scenario")
                    return controller
                },
                executingSessionCountProvider: { 0 },
            )

            service.appWillEnterBackground()
            service.appDidEnterForeground()
            try await waitUntil {
                controller.endCount() == 1
            }

            #expect(controller.endCount() == 1)
        }

        @MainActor
        private func waitUntil(
            timeout: Duration = .seconds(1),
            pollInterval: Duration = .milliseconds(10),
            _ condition: @MainActor () -> Bool,
        ) async throws {
            let deadline = ContinuousClock.now + timeout
            while ContinuousClock.now < deadline {
                if condition() {
                    return
                }
                try await Task.sleep(for: pollInterval)
            }

            throw NSError(
                domain: "LiveActivityServiceTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for Live Activity state."],
            )
        }
    }

    private final class LiveActivityControllerSpy: LiveActivityControlling {
        private var requested: [FlowDownWidgetsAttributes.ContentState] = []
        private var updated: [FlowDownWidgetsAttributes.ContentState] = []
        private var ended = 0

        func recordRequest(_ state: FlowDownWidgetsAttributes.ContentState) {
            requested.append(state)
        }

        func requestedStates() -> [FlowDownWidgetsAttributes.ContentState] {
            requested
        }

        func updatedStates() -> [FlowDownWidgetsAttributes.ContentState] {
            updated
        }

        func endCount() -> Int {
            ended
        }

        func update(state: FlowDownWidgetsAttributes.ContentState) async {
            updated.append(state)
        }

        func endImmediately() async {
            ended += 1
        }
    }
#endif
