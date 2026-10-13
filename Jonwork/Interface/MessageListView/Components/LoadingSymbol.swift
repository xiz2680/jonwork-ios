//
//  Created by ktiays on 2025/2/20.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import Respring
import UIKit

final class LoadingSymbol: UIView {
    private var displayLink: CADisplayLink?
    private lazy var spring: Spring = .init(duration: 0.9)
    private var values: [CGFloat] = .init(repeating: 0, count: 3)
    private var velocities: [CGFloat] = .init(repeating: 0, count: 3)
    private var target: CGFloat = 0
    private var previousFinishTime: CFTimeInterval?
    private lazy var delays: [TimeInterval] = [0, delay, delay * 2]

    var dotRadius: CGFloat = 20
    var spacing: CGFloat = 16
    var delay: TimeInterval = 0.12 {
        didSet {
            delays = [0, delay, delay * 2]
        }
    }

    var animationInterval: TimeInterval = 0.3
    var animationDuration: TimeInterval = 0.9 {
        didSet {
            spring = .init(duration: animationDuration)
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()

        if superview != nil {
            displayLink = CADisplayLink(target: self, selector: #selector(handleDisplayLink(_:)))
            displayLink?.add(to: .main, forMode: .common)
            target = 1
        } else {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    override var intrinsicContentSize: CGSize {
        .init(width: dotRadius * 2 * 3 + spacing * 2, height: 44)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        .init(width: dotRadius * 2 * 3 + spacing * 2, height: size.height)
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }
        context.clear(rect)

        let contentWidth = dotRadius * 2 * 3 + spacing * 2
        for (index, value) in values.enumerated() {
            let distance = rect.height - dotRadius * 2
            let centerY = distance * value + dotRadius
            let dotRect = CGRect(
                x: (rect.width - contentWidth) / 2 + CGFloat(index) * (dotRadius * 2 + spacing),
                y: centerY - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2,
            )

            context.setFillColor(UIColor.label.cgColor)
            context.fillEllipse(in: dotRect)
        }
    }

    @objc
    private func handleDisplayLink(_ sender: CADisplayLink) {
        defer { setNeedsDisplay() }

        let interval: TimeInterval
        if let previousFinishTime {
            interval = CACurrentMediaTime() - previousFinishTime
            if interval < animationInterval {
                return
            }
        } else {
            interval = animationInterval
            previousFinishTime = CACurrentMediaTime() - interval
        }

        let duration = sender.targetTimestamp - sender.timestamp
        var isAnimating = false
        for (index, var value) in values.enumerated() {
            let delay = delays[index]
            if interval < delay + animationInterval {
                isAnimating = true
                continue
            }

            var velocity = velocities[index]
            defer {
                velocities[index] = velocity
                values[index] = value
            }
            spring.update(value: &value, velocity: &velocity, target: target, deltaTime: duration)
            if abs(target - value) < 1e-3 {
                value = target
                continue
            }
            isAnimating = true
        }

        if !isAnimating {
            target = 1 - target
            previousFinishTime = CACurrentMediaTime()
        }
    }
}
