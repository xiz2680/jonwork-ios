//
//  ConversationSession+Rename.swift
//  FlowDown
//
//  Created by 秋星桥 on 3/19/25.
//

import ChatClientKit
import Foundation
import Storage

extension ConversationSession {
    func updateTitleAndIcon() async {
        guard let metadata = await generateConversationMetadata(),
              metadata.hasGeneratedContent
        else {
            return
        }

        ConversationManager.shared.editConversation(identifier: id) {
            if let title = metadata.title {
                $0.update(\.title, to: title)
            }
            if let icon = metadata.icon {
                let iconData = icon.textToImage(size: 128)?.pngData() ?? .init()
                $0.update(\.icon, to: iconData)
            }
            $0.update(\.shouldAutoRename, to: false)
        }
    }
}
