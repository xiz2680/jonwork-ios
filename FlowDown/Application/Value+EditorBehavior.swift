//
//  Value+EditorBehavior.swift
//  FlowDown
//
//  Created by 秋星桥 on 2/22/25.
//

import Combine
import ConfigurableKit
import Foundation

extension EditorBehavior {
    static let pasteAsFileStorageKey = "app.editor.paste.as.file"
    static let compressImageStorageKey = "app.editor.compress.image"
    static let useConfirmationOnSendKey = "app.editor.confirmation.on.send"

    private static var cancellables: Set<AnyCancellable> = []

    static let useConfirmationOnSendConfigurableObject: ConfigurableObject = .init(
        icon: "checkmark.circle",
        title: "Confirmation on Send",
        explain: "Enable this to require Command + Enter to send message. On touch devices, you will need to tap the send button manually.",
        key: useConfirmationOnSendKey,
        defaultValue: false,
        annotation: .toggle,
    )

    static let pasteAsFileConfigurableObject: ConfigurableObject = .init(
        icon: "doc.text",
        title: "Paste as File",
        explain: "When enabled, large content pasted into the editor will be attached as a file. You can tap on the file to edit it.",
        key: pasteAsFileStorageKey,
        defaultValue: true,
        annotation: .toggle,
    )

    static let compressImageConfigurableObject: ConfigurableObject = .init(
        icon: "text.below.photo",
        title: "Compress Image",
        explain: "If enabled, images will be compressed before added to chat. Compressed image will be easier to upload but may lose some quality.",
        key: compressImageStorageKey,
        defaultValue: true,
        annotation: .toggle,
    )

    static func subscribeToConfigurableItem() {
        assert(cancellables.isEmpty)
        ConfigurableKit.publisher(forKey: useConfirmationOnSendKey, type: Bool.self)
            .sink { input in
                guard let input else { return }
                Logger.ui.debugFile("applying editor behavior: confirmation on send: \(input)")
                useConfirmationOnSend = input
            }
            .store(in: &cancellables)
        ConfigurableKit.publisher(forKey: pasteAsFileStorageKey, type: Bool.self)
            .sink { input in
                guard let input else { return }
                Logger.ui.debugFile("applying editor behavior: paste as file: \(input)")
                pasteLargeTextContentAsFile = input
            }
            .store(in: &cancellables)
        ConfigurableKit.publisher(forKey: compressImageStorageKey, type: Bool.self)
            .sink { input in
                guard let input else { return }
                Logger.ui.debugFile("applying editor behavior: compress image: \(input)")
                compressImage = input
            }
            .store(in: &cancellables)
    }
}
