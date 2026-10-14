//
//  JonworkWidgetsLiveActivity.swift
//  JonworkWidgets
//
//  Created by qaq on 7/1/2026.
//

import ActivityKit
import SwiftUI
import WidgetKit

struct JonworkWidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: JonworkWidgetsAttributes.self) { context in
            let finished = context.state.conversationCount <= 0
            let text = finished
                ? String(localized: "All conversation(s) completed.")
                : String(localized: "Streaming \(context.state.conversationCount) conversation(s).")

            VStack {
                HStack(spacing: 16) {
                    Image(systemName: "bird")
                        .font(.largeTitle)
                        .bold()
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .center, spacing: 4) {
                            Text(String("Jonwork"))
                                .bold()
                            Spacer()
                            Group {
                                if finished {
                                    Image(systemName: "checkmark.circle.fill")
                                } else {
                                    Image(systemName: "arrow.down")
                                    Text(String(context.state.streamingSessionTextCount))
                                }
                            }
                            .monospaced()
                            .opacity(0.5)
                        }
                        Text(text)
                            .contentTransition(.numericText())
                    }
                    .font(.body)
                }
            }
            .foregroundStyle(.white)
            .padding()
            .animation(.interactiveSpring, value: context.state)
            .activityBackgroundTint(.accent)
            .activitySystemActionForegroundColor(.white)
            .widgetURL(URL(string: "jonwork://live-activity"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    let finished = context.state.conversationCount <= 0
                    let text = finished
                        ? String(localized: "All conversation(s) completed.")
                        : String(localized: "Streaming \(context.state.conversationCount) conversation(s).")

                    VStack(spacing: 8) {
                        Spacer()

                        Image(systemName: "bird.fill")
                            .bold()

                        Text(text)
                            .contentTransition(.numericText())
                            .animation(.interactiveSpring, value: context.state)
                    }
                    .font(.footnote)
                }
            } compactLeading: {
                let finished = context.state.conversationCount <= 0

                Image(systemName: "bird.fill")
                    .foregroundStyle(finished ? .accent : .white)
                    .animation(.interactiveSpring, value: context.state)
            } compactTrailing: {
                let finished = context.state.conversationCount <= 0
                let tokenCount = context.state.streamingSessionTextCount

                if finished {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(finished ? .accent : .white)
                        .animation(.interactiveSpring, value: context.state)
                } else {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.down")
                        Text(String(tokenCount))
                            .contentTransition(.numericText())
                    }
                    .font(.footnote)
                    .animation(.interactiveSpring, value: context.state)
                }
            } minimal: {
                let finished = context.state.conversationCount <= 0

                Image(systemName: "bird.fill")
                    .foregroundStyle(finished ? .accent : .white)
                    .animation(.interactiveSpring, value: context.state)
                    .widgetURL(URL(string: "jonwork://live-activity"))
            }
        }
    }
}

private extension JonworkWidgetsAttributes {
    static var preview: JonworkWidgetsAttributes {
        JonworkWidgetsAttributes()
    }
}

private extension JonworkWidgetsAttributes.ContentState {
    static var none: JonworkWidgetsAttributes.ContentState {
        JonworkWidgetsAttributes.ContentState(
            runningSession: 0,
            incomingTokens: 0,
            conversationCount: 0,
            streamingSessionTextCount: 0,
        )
    }

    static var doing: JonworkWidgetsAttributes.ContentState {
        JonworkWidgetsAttributes.ContentState(
            runningSession: 1,
            incomingTokens: 100,
            conversationCount: 1,
            streamingSessionTextCount: 100,
        )
    }

    static var done: JonworkWidgetsAttributes.ContentState {
        JonworkWidgetsAttributes.ContentState(
            runningSession: 0,
            incomingTokens: 114_514,
            conversationCount: 0,
            streamingSessionTextCount: 114_514,
        )
    }
}

@available(iOS 17.0, *)
#Preview("Notification", as: .content, using: JonworkWidgetsAttributes.preview) {
    JonworkWidgetsLiveActivity()
} contentStates: {
    JonworkWidgetsAttributes.ContentState.none
    JonworkWidgetsAttributes.ContentState.doing
    JonworkWidgetsAttributes.ContentState.done
}
