//
//  UIViewController.swift
//  FlowDown
//
//  Created by qaq on 8/12/2025.
//

import UIKit

extension UIViewController {
    /// Returns the currently visible controller from this point in the hierarchy.
    var topMostController: UIViewController {
        var current: UIViewController = self

        while true {
            if let presentedViewController = current.presentedViewController {
                current = presentedViewController
                continue
            }

            let possibleSelectors: [Selector] = [
                NSSelectorFromString("topViewController"),
                NSSelectorFromString("visibleViewController"),
                NSSelectorFromString("contentViewController"),
                NSSelectorFromString("rootViewController"),
                NSSelectorFromString("selectedViewController"),
                NSSelectorFromString("detailViewController"),
            ]
            for selector in possibleSelectors {
                guard current.responds(to: selector),
                      let next = current.perform(selector)?
                      .takeUnretainedValue()
                      as? UIViewController
                else {
                    continue
                }
                current = next
            }

            // loook for child controller that has the same frame as current
            for child in current.children {
                if child.view.frame == current.view.frame {
                    current = child
                    continue
                }
            }

            break
        }

        return current
    }
}
