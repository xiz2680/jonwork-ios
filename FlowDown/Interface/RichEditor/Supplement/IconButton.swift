//
//  IconButton.swift
//  RichEditor
//
//  Created by 秋星桥 on 2025/1/16.
//

import UIKit

class IconButton: UIView {
    let imageView = UIImageView()

    var tapAction: () -> Void = {}

    required init() {
        super.init(frame: .zero)
        addSubview(imageView)
        imageView.tintColor = .label
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit

        let tap = UITapGestureRecognizer(target: self, action: #selector(buttonAction))
        addGestureRecognizer(tap)

        isUserInteractionEnabled = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    required convenience init(icon: String) {
        self.init()
        imageView.image = UIImage(named: icon)?
            .withRenderingMode(.alwaysTemplate)
    }

    func change(icon: String, animated: Bool = true) {
        if animated {
            UIView.transition(with: imageView, duration: 0.3, options: .transitionCrossDissolve, animations: {
                self.change(icon: icon, animated: false)
            }, completion: nil)
        } else {
            imageView.image = UIImage(named: icon)?
                .withRenderingMode(.alwaysTemplate)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds.insetBy(dx: 2, dy: 2)
    }

    @objc private func buttonAction() {
        guard !isHidden else { return }
        guard alpha > 0 else { return }
        puddingAnimate()
        tapAction()
    }
}
