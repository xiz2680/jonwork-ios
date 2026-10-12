//
//  OpenSourceLicenseController 2.swift
//  FlowDown
//
//  Created by 秋星桥 on 3/1/25.
//

import UIKit

class PrivacyPolicyController: CodeEditorController {
    init() {
        var text = String(localized: "Resource not found, please check your installation.")
        if let item = Bundle.main.url(forResource: "PrivacyPolicy", withExtension: "md"),
           let content = try? String(contentsOf: item)
        { text = content }

        super.init(language: "markdown", text: text)

        title = String(localized: "Privacy Policy")

        textView.isLineWrappingEnabled = true
        textView.isEditable = false
    }
}
