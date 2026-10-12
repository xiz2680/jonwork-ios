//
//  InputEditor+Delegate.swift
//  RichEditor
//
//  Created by 秋星桥 on 2025/1/17.
//

import UIKit

extension InputEditor {
    protocol Delegate: AnyObject {
        func onInputEditorCaptureButtonTapped()
        func onInputEditorPickAttachmentTapped()
        func onInputEditorMicButtonTapped()
        func onInputEditorToggleMoreButtonTapped()
        func onInputEditorBeginEditing()
        func onInputEditorEndEditing()
        func onInputEditorSubmitButtonTapped()
        func onInputEditorPasteAsAttachmentTapped()
        func onInputEditorTextChanged(text: String)
        func onInputEditorPastingLargeTextAsDocument(content: String)
        func onInputEditorPastingImage(image: UIImage)
    }
}
