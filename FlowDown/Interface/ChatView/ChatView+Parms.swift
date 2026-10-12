//
//  ChatView+Parms.swift
//  FlowDown
//
//  Created by 秋星桥 on 2/2/25.
//

import ConfigurableKit
import Foundation

extension ChatView {
    enum EditorModelNameStyle: String, CaseIterable, Codable {
        case full
        case trimmed
        case none

        var icon: String {
            switch self {
            case .full: "text.quote"
            case .trimmed: "text.alignleft"
            case .none: "minus"
            }
        }

        var title: String.LocalizationValue {
            switch self {
            case .full: "Unique Model Name"
            case .trimmed: "Model Name Only"
            case .none: "Do Not Display"
            }
        }
    }

    static let editorModelNameStyle: ConfigurableObject = .init(
        icon: "increase.quotelevel",
        title: "Model Name Style",
        explain: "Show full model name and information in the quick setting bar under the input box or not.",
        key: "app.chat.model.picker.style",
        defaultValue: EditorModelNameStyle.trimmed.rawValue,
        annotation: .menu {
            EditorModelNameStyle.allCases.map {
                .init(
                    icon: $0.icon,
                    title: $0.title,
                    rawValue: $0.rawValue,
                )
            }
        },
    )

    static let editorApplyModelToDefault: ConfigurableObject = .init(
        icon: "checkmark.seal",
        title: "Select as Default",
        explain: "When selecting a new chat model, also set it as the default model.",
        key: "app.chat.model.picker.apply.to.default",
        defaultValue: true,
        annotation: .toggle,
    )
}
