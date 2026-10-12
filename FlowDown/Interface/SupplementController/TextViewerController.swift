//
//  TextViewerController.swift
//  FlowDown
//
//  Created by 秋星桥 on 2/24/25.
//

import UIKit

class TextViewerController: TextEditorContentController {
    let editable: Bool
    init(editable: Bool) {
        self.editable = editable
        super.init()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        textView.isEditable = editable
        navigationItem.leftBarButtonItem = nil
    }

    override func done() {
        dispose()
    }

    override func cancelDone() {
        dispose()
    }

    func dispose() {
        if navigationController?.viewControllers.count == 1 {
            dismiss(animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }
}
