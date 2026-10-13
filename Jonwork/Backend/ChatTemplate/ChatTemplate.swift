//
//  ChatTemplate.swift
//  Jonwork
//
//  Created by 秋星桥 on 6/28/25.
//

import Foundation
import UIKit

struct ChatTemplate: Identifiable, Codable, Equatable {
    var id: UUID = .init()

    var name: String = .init(localized: "Template")
    var avatar: Data = "😶".textToImage(size: 64)?.pngData() ?? .init()
    var prompt: String = .init(localized: "Please help me to...")
    var inheritApplicationPrompt: Bool = true

    func with(_ modification: (inout ChatTemplate) -> Void) -> ChatTemplate {
        var template = self
        modification(&template)
        return template
    }
}
