//
//  UIFont.swift
//  FlowDown
//
//  Created by 秋星桥 on 2024/12/31.
//

import UIKit

extension UIFont {
    static let title: UIFont = .preferredFont(forTextStyle: .title3)
    static let body: UIFont = .preferredFont(forTextStyle: .body)
    static let headline: UIFont = .preferredFont(forTextStyle: .headline)
    static let footnote: UIFont = .preferredFont(forTextStyle: .footnote)

    class func rounded(ofSize size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let systemFont = UIFont.systemFont(ofSize: size, weight: weight)
        return if let descriptor = systemFont.fontDescriptor.withDesign(.rounded) {
            UIFont(descriptor: descriptor, size: size)
        } else {
            systemFont
        }
    }
}
