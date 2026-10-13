//
//  EmojiPicker+Cell.swift
//  Kimis
//
//  Created by Lakr Aream on 2022/5/5.
//

import UIKit

extension EmojiPickerView {
    class EmojiPickerCell: UICollectionViewCell {
        let label = UILabel()

        static let cellId = "wiki.qaq.emoji.cell"

        override init(frame: CGRect) {
            super.init(frame: frame)
            label.font = .systemFont(ofSize: 32)
            label.textAlignment = .center
            contentView.addSubview(label)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            label.frame = bounds
        }

        override func prepareForReuse() {
            label.text = ""
        }

        func apply(item: EmojiElement) {
            label.text = item.emoji.emoji
        }
    }

    class EmojiPickerSectionHeader: UICollectionReusableView {
        let label = UILabel()
        let effect: UIView

        static let headerId = "wiki.qaq.EmojiPickerSectionHeader"

        override init(frame: CGRect) {
            let blur = UIBlurEffect(style: .regular)
            let effect = UIVisualEffectView(effect: blur)
            self.effect = effect

            label.textAlignment = .left
            label.font = .systemFont(ofSize: 12, weight: .semibold)
            label.alpha = 0.5

            super.init(frame: frame)

            addSubview(effect)
            addSubview(label)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            label.frame = bounds.inset(by: UIEdgeInsets(horizontal: 4, vertical: 0))
            effect.frame = bounds.inset(by: UIEdgeInsets(horizontal: -50, vertical: 0))
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }

        override func prepareForReuse() {
            label.text = ""
        }
    }
}
