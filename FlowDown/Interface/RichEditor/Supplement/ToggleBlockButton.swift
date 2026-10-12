//
//  ToggleBlockButton.swift
//  RichEditor
//
//  Created by 秋星桥 on 1/17/25.
//

import UIKit

class ToggleBlockButton: BlockButton {
    var isOn: Bool = false {
        didSet {
            let changed = isOn != oldValue
            updateUI()
            guard changed else { return }
            onValueChanged()
        }
    }

    var onValueChanged: () -> Void = {}

    override init(text: String, icon: String) {
        super.init(text: text, icon: icon)
        super.actionBlock = { [weak self] in self?.toggle() }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func toggle() {
        isOn.toggle()
    }

    override var actionBlock: () -> Void {
        get { super.actionBlock }
        set {
            super.actionBlock = { [weak self] in
                guard let self else { return }
                toggle()
                newValue()
            }
        }
    }

    override func updateAppearanceAfterTraitChange() {
        super.updateAppearanceAfterTraitChange()
        updateUI()
    }

    func updateUI() {
        if isOn {
            applyOnAppearance()
        } else {
            applyDefaultAppearance()
        }
    }

    func applyOnAppearance() {
        borderView.layer.borderColor = UIColor.accent.cgColor
        borderView.backgroundColor = .accent
        iconView.tintColor = .white
        textLabel.textColor = .white
        updateStrikes()
    }

    override func applyDefaultAppearance() {
        super.applyDefaultAppearance()
        updateStrikes()
    }
}
