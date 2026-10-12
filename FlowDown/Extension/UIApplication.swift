//
//  UIApplication.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/31/25.
//

import UIKit

extension UIApplication {
    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString)
        else { return }
        if Thread.isMainThread {
            if canOpenURL(url) {
                open(url)
            } else {
                open(URL(string: "x-apple.systempreferences:com.apple.preference.security")!)
            }
        } else {
            Task { @MainActor in
                self.openSettings()
            }
        }
    }
}
