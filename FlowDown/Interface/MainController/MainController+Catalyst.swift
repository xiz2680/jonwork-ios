//
//  MainController+Catalyst.swift
//  FlowDown
//
//  Created by 秋星桥 on 7/3/25.
//

import Foundation
import UIKit

#if targetEnvironment(macCatalyst)
    extension UIResponder {
        func dispatchTouchAsWindowMovement() {
            guard let appType = NSClassFromString("NSApplication") as? NSObject.Type,
                  let nsApp = appType.value(forKey: "sharedApplication") as? NSObject,
                  let currentEvent = nsApp.value(forKey: "currentEvent") as? NSObject,
                  let nsWindow = currentEvent.value(forKey: "window") as? NSObject
            else { return }
            nsWindow.perform(
                NSSelectorFromString("performWindowDragWithEvent:"),
                with: currentEvent,
            )
        }
    }

    extension MainController {
        func performZoom() {
            guard let appClass = NSClassFromString("NSApplication") as? NSObject.Type,
                  let sharedApp = appClass.value(forKey: "sharedApplication") as? NSObject,
                  sharedApp.responds(to: NSSelectorFromString("windows")),
                  let windowsArray = sharedApp.value(forKey: "windows") as? [NSObject]
            else {
                return
            }
            assert(!windowsArray.isEmpty, "No windows found in shared application")
            for window in windowsArray {
                if window.responds(to: NSSelectorFromString("performZoom:")) {
                    window.perform(NSSelectorFromString("performZoom:"), with: nil)
                }
            }
        }
    }
#endif
