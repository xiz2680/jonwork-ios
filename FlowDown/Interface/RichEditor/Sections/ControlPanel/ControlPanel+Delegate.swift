//
//  ControlPanel+Delegate.swift
//  RichEditor
//
//  Created by 秋星桥 on 1/17/25.
//

import Foundation

extension ControlPanel {
    protocol Delegate: AnyObject {
        func onControlPanelOpen()
        func onControlPanelClose()
        func onControlPanelCameraButtonTapped()
        func onControlPanelPickPhotoButtonTapped()
        func onControlPanelPickFileButtonTapped()
        func onControlPanelRequestWebScrubber()
    }
}
