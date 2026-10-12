//
//  CircleImageView.swift
//  FlowDown
//
//  Created by 秋星桥 on 2025/1/2.
//

import UIKit

class CircleImageView: UIImageView {
    init() {
        super.init(frame: .zero)
        clipsToBounds = true
        masksToBounds = true
        contentMode = .scaleAspectFill
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override var frame: CGRect {
        didSet {
            layer.cornerRadius = frame.width / 2
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = frame.width / 2
    }
}
