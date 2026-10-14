//
//  EditorBehavior.swift
//  RichEditor
//
//  Created by 秋星桥 on 2/22/25.
//

import Foundation

extension Notification.Name {
    static let EditorBehaviorChanged = Notification.Name("EditorBehaviorChanged")
}

enum EditorBehavior {
    static var pasteLargeTextContentAsFile: Bool = true {
        didSet {
            NotificationCenter.default.post(name: .EditorBehaviorChanged, object: nil)
        }
    }

    static var useConfirmationOnSend: Bool = false {
        didSet {
            NotificationCenter.default.post(name: .EditorBehaviorChanged, object: nil)
        }
    }

    static var compressImage: Bool = true {
        didSet {
            NotificationCenter.default.post(name: .EditorBehaviorChanged, object: nil)
        }
    }
}
