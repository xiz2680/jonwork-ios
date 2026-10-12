//
//  SettingButton.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/22/25.
//

import UIKit

class SettingButton: UIButton {
    init() {
        super.init(frame: .zero)
        setImage(UIImage(systemName: "gear"), for: .normal)
        tintColor = .label
        imageView?.contentMode = .scaleAspectFit

        addTarget(self, action: #selector(buttonAction), for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    @objc func buttonAction() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let controller = SettingController()
        parentViewController?.present(controller, animated: true)
    }
}
