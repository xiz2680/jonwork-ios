//
//  MainController+SidbarDragger.swift
//  FlowDown
//
//  Created by 秋星桥 on 7/2/25.
//

import Combine
import SnapKit
import UIKit

class SidebarDraggerView: UIView {
    let allowedMinimalValue = 200
    let initialValue = 256
    let allowedMaximalValue = 512

    @Published var currentValue: Int {
        didSet {
            if currentValue < allowedMinimalValue { currentValue = allowedMinimalValue }
            if currentValue > allowedMaximalValue { currentValue = allowedMaximalValue }
            UserDefaults.standard.set(currentValue, forKey: "SidebarWidth")
        }
    }

    var onSuggestCollapse: (() -> Bool) = { false }

    let handlerView = UIView().with {
        $0.backgroundColor = .label.withAlphaComponent(0.5)
        $0.clipsToBounds = true
        $0.alpha = 0
    }

    init() {
        currentValue = UserDefaults.standard.integer(forKey: "SidebarWidth")
        super.init(frame: .zero)
        backgroundColor = .background.withAlphaComponent(0.001)

        if currentValue < allowedMinimalValue { currentValue = allowedMinimalValue }
        if currentValue > allowedMaximalValue { currentValue = allowedMaximalValue }

        addSubview(handlerView)
        handlerView.snp.makeConstraints { make in
            make.width.equalTo(4)
            make.height.equalToSuperview()
            make.center.equalToSuperview()
        }

        isUserInteractionEnabled = true

        let hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
        addGestureRecognizer(hover)

        let dragGesture = UIPanGestureRecognizer(target: self, action: #selector(handleDrag(_:)))
        dragGesture.minimumNumberOfTouches = 1
        dragGesture.maximumNumberOfTouches = 1
        addGestureRecognizer(dragGesture)

        let doubleClickReset = UITapGestureRecognizer(target: self, action: #selector(handleDoubleClickReset(_:)))
        doubleClickReset.numberOfTapsRequired = 2
        addGestureRecognizer(doubleClickReset)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    @objc private func handleHover(_ gesture: UIHoverGestureRecognizer) {
        switch gesture.state {
        case .began, .changed: showDragger()
        default: hideDragger()
        }
    }

    func showDragger() {
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            self.handlerView.alpha = 1
        }
    }

    func hideDragger() {
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            self.handlerView.alpha = 0
        }
    }

    private var gestureBeginValue: Int = 0

    @objc func handleDrag(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)
        switch gesture.state {
        case .began:
            gestureBeginValue = currentValue
            fallthrough
        case .changed:
            showDragger()
            var decisionValue = gestureBeginValue + Int(translation.x - frame.width)
            if decisionValue < allowedMinimalValue {
                if decisionValue < allowedMinimalValue / 2 {
                    if onSuggestCollapse() {
                        gesture.isEnabled = false
                        gesture.isEnabled = true
                        return
                    }
                }
                decisionValue = allowedMinimalValue
            }
            if decisionValue > allowedMaximalValue {
                decisionValue = allowedMaximalValue
            }
            currentValue = decisionValue
        default:
            hideDragger()
        }
    }

    @objc func handleDoubleClickReset(_ gesture: UITapGestureRecognizer) {
        if gesture.state == .ended { currentValue = initialValue }
    }
}
