//
//  ControlPanel.swift
//  RichEditor
//
//  Created by 秋星桥 on 2025/1/16.
//

import Combine
import UIKit

class ControlPanel: EditorSectionView {
    let isPanelOpen: CurrentValueSubject<Bool, Never> = .init(false)

    let buttonHeight: CGFloat = 100
    let buttonSpacing: CGFloat = 10

    let cameraButton = GiantButton(
        title: NSLocalizedString("Camera", comment: ""),
        icon: "camera",
    )
    let photoButton = GiantButton(
        title: NSLocalizedString("Photo", comment: ""),
        icon: "image.up",
    )
    let fileButton = GiantButton(
        title: NSLocalizedString("File", comment: ""),
        icon: "attachment",
    )
    let webButton = GiantButton(
        title: NSLocalizedString("Web", comment: ""),
        icon: "link",
    )

    #if targetEnvironment(macCatalyst)
        lazy var buttonViews: [GiantButton] = [
            photoButton,
            fileButton,
            webButton,
        ]
    #else
        lazy var buttonViews: [GiantButton] = [
            cameraButton,
            photoButton,
            fileButton,
            webButton,
        ]
    #endif

    weak var delegate: Delegate?

    override func initializeViews() {
        super.initializeViews()

        for view in buttonViews {
            view.alpha = 0
            addSubview(view)
        }

        cameraButton.actionBlock = { [weak self] in
            self?.delegate?.onControlPanelCameraButtonTapped()
        }

        photoButton.actionBlock = { [weak self] in
            self?.delegate?.onControlPanelPickPhotoButtonTapped()
        }

        fileButton.actionBlock = { [weak self] in
            self?.delegate?.onControlPanelPickFileButtonTapped()
        }

        webButton.actionBlock = { [weak self] in
            self?.delegate?.onControlPanelRequestWebScrubber()
        }

        isPanelOpen
            .removeDuplicates()
            .ensureMainThread()
            .sink { [weak self] input in
                guard let self else { return }
                heightPublisher.send(input ? buttonHeight : 0)
                if input {
                    delegate?.onControlPanelOpen()
                } else {
                    delegate?.onControlPanelClose()
                }
            }
            .store(in: &cancellables)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let buttonWidth = ceil(bounds.width + buttonSpacing) / CGFloat(buttonViews.count) - buttonSpacing
        for (idx, view) in buttonViews.enumerated() {
            view.frame = .init(
                x: CGFloat(idx) * (buttonWidth + buttonSpacing),
                y: 0,
                width: buttonWidth,
                height: buttonHeight,
            )
            view.alpha = isPanelOpen.value ? 1 : 0
        }
    }

    func toggle() {
        doWithAnimation { [self] in isPanelOpen.send(!isPanelOpen.value) }
    }

    func close() {
        guard isPanelOpen.value else { return }
        toggle()
    }
}
