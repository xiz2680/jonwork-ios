//
//  ImageCircleButton.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/22/25.
//

import UIKit

class ImageCircleButton: UIView {
    let imageView = UIImageView()

    var actionBlock: (() -> Void) = {}

    enum DistinctStyle {
        case none
        case shadow
        case border
    }

    init(name: String, distinctStyle: DistinctStyle = .none, inset: CGFloat = 10) {
        super.init(frame: .zero)

        switch distinctStyle {
        case .shadow:
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOffset = .zero
            layer.shadowRadius = 8
            layer.shadowOpacity = 0.1
            backgroundColor = .background
        case .border:
            layer.borderWidth = 2
            layer.borderColor = UIColor.gray.withAlphaComponent(0.1).cgColor
            backgroundColor = .background
        case .none:
            break
        }

        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .label
        if let image = UIImage(named: name) {
            imageView.image = image
        } else if let image = UIImage(
            systemName: name,
            withConfiguration: UIImage.SymbolConfiguration(weight: .semibold),
        ) {
            imageView.image = image
        }
        addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(inset)
        }

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismiss))
        addGestureRecognizer(tap)
        isUserInteractionEnabled = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        layer.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    @objc private func dismiss() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        puddingAnimate()
        actionBlock()
    }
}

class EasyHitImageCircleButton: ImageCircleButton {
    open var easyHitInsets: UIEdgeInsets = .init(top: -16, left: -16, bottom: -16, right: -16)

    override open func point(inside point: CGPoint, with _: UIEvent?) -> Bool {
        bounds.inset(by: easyHitInsets).contains(point)
    }
}
