//
//  OpenSourceLicenseController.swift
//  FlowDown
//
//  Created by 秋星桥 on 3/1/25.
//

import UIKit

class OpenSourceLicenseController: CodeEditorController {
    init() {
        var text = String(localized: "Resource not found, please check your installation.")
        if let item = Bundle.main.url(forResource: "OpenSourceLicenses", withExtension: "md"),
           let content = try? String(contentsOf: item)
        { text = content }

        super.init(language: "markdown", text: text)

        title = String(localized: "Open Source Licenses")

        textView.isLineWrappingEnabled = false
        textView.isEditable = false
    }
}
