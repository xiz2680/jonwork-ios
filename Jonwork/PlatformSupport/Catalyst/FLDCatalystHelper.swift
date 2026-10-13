//
//  Created by ktiays on 2025/2/28.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

#if targetEnvironment(macCatalyst)

    import ObjectiveC
    import UIKit

    final class FLDCatalystHelper {
        static let shared = FLDCatalystHelper()

        private init() {}

        func install() {
            swizzleDidCreateUIScene()
        }

        private func swizzleDidCreateUIScene() {
            guard let appDelegateClass = NSClassFromString("UINSApplicationDelegate") else {
                return
            }

            let selector = sel_registerName("didCreateUIScene:transitionContext:")
            guard let method = class_getInstanceMethod(appDelegateClass, selector) else {
                return
            }

            let originalIMP = method_getImplementation(method)

            let block: @convention(block) (AnyObject, UIScene, AnyObject) -> Void = { _self, scene, context in
                // Call original implementation
                typealias OriginalFunction = @convention(c) (AnyObject, Selector, UIScene, AnyObject) -> Void
                let originalFunc = unsafeBitCast(originalIMP, to: OriginalFunction.self)
                originalFunc(_self, selector, scene, context)

                // Apply visual effect view
                FLDCatalystHelper.applyVisualEffectView(to: scene)
            }

            let newIMP = imp_implementationWithBlock(block as Any)
            method_setImplementation(method, newIMP)
        }

        private static func applyVisualEffectView(to scene: UIScene) {
            guard let windowScene = scene as? UIWindowScene,
                  let uiWindow = windowScene.keyWindow
            else {
                return
            }

            guard let nsApplicationClass = NSClassFromString("NSApplication") as? NSObject.Type,
                  let application = nsApplicationClass.perform(NSSelectorFromString("sharedApplication"))?.takeUnretainedValue() as? NSObject,
                  let delegate = application.perform(NSSelectorFromString("delegate"))?.takeUnretainedValue() as? NSObject
            else {
                return
            }

            let hostWindowSelector = sel_registerName("hostWindowForUIWindow:")
            guard delegate.responds(to: hostWindowSelector),
                  let windowProxy = delegate.perform(hostWindowSelector, with: uiWindow)?.takeUnretainedValue() as? NSObject
            else {
                return
            }

            let attachedWindowSelector = NSSelectorFromString("attachedWindow")
            guard windowProxy.responds(to: attachedWindowSelector),
                  let nsWindow = windowProxy.perform(attachedWindowSelector)?.takeUnretainedValue() as? NSObject
            else {
                return
            }

            guard let nsWindowClass = NSClassFromString("UINSWindow"),
                  nsWindow.isKind(of: nsWindowClass)
            else {
                return
            }

            let contentViewSelector = NSSelectorFromString("contentView")
            guard nsWindow.responds(to: contentViewSelector),
                  let contentView = nsWindow.perform(contentViewSelector)?.takeUnretainedValue() as? NSObject
            else {
                return
            }

            let superviewSelector = NSSelectorFromString("superview")
            guard contentView.responds(to: superviewSelector),
                  let themeFrame = contentView.perform(superviewSelector)?.takeUnretainedValue() as? NSObject,
                  let themeFrameClass = NSClassFromString("NSThemeFrame"),
                  themeFrame.isKind(of: themeFrameClass)
            else {
                return
            }

            let subviewsSelector = NSSelectorFromString("subviews")
            guard contentView.responds(to: subviewsSelector),
                  let subviews = contentView.perform(subviewsSelector)?.takeUnretainedValue() as? [AnyObject],
                  let sceneView = subviews.first
            else {
                return
            }

            let effectViewClass: NSObject.Type

            if let glassEffectViewClass = NSClassFromString("NSGlassEffectView") as? NSObject.Type {
                effectViewClass = glassEffectViewClass
            } else {
                // Create NSVisualEffectView
                guard let visualEffectViewClass = NSClassFromString("NSVisualEffectView") as? NSObject.Type else {
                    return
                }
                effectViewClass = visualEffectViewClass
            }

            let visualEffectView = effectViewClass.init()

            if visualEffectView.responds(to: NSSelectorFromString("material")) {
                // NSVisualEffectMaterialSidebar = 7
                visualEffectView.setValue(7, forKey: "material")
            }
            if visualEffectView.responds(to: NSSelectorFromString("blendingMode")) {
                // NSVisualEffectBlendingModeBehindWindow = 0
                visualEffectView.setValue(0, forKey: "blendingMode")
            }
            if visualEffectView.responds(to: NSSelectorFromString("style")) {
                // 3> NSGlassEffectView.Style.regular.rawValue
                // $R1: Int = 0
                visualEffectView.setValue(0, forKey: "style")
            }

            let addSubviewSelector = sel_registerName("addSubview:")
            _ = contentView.perform(addSubviewSelector, with: visualEffectView)
            _ = contentView.perform(addSubviewSelector, with: sceneView)

            // Setup constraints
            visualEffectView.setValue(false, forKey: "translatesAutoresizingMaskIntoConstraints")

            guard let nsLayoutConstraintClass = NSClassFromString("NSLayoutConstraint") as? NSObject.Type else {
                return
            }

            guard let topAnchor = visualEffectView.value(forKey: "topAnchor") as? NSObject,
                  let leadingAnchor = visualEffectView.value(forKey: "leadingAnchor") as? NSObject,
                  let trailingAnchor = visualEffectView.value(forKey: "trailingAnchor") as? NSObject,
                  let bottomAnchor = visualEffectView.value(forKey: "bottomAnchor") as? NSObject
            else {
                return
            }

            guard let contentTopAnchor = contentView.value(forKey: "topAnchor") as? NSObject,
                  let contentLeadingAnchor = contentView.value(forKey: "leadingAnchor") as? NSObject,
                  let contentTrailingAnchor = contentView.value(forKey: "trailingAnchor") as? NSObject,
                  let contentBottomAnchor = contentView.value(forKey: "bottomAnchor") as? NSObject
            else {
                return
            }

            let constraintEqualToAnchorSelector = sel_registerName("constraintEqualToAnchor:")

            guard let topConstraint = topAnchor.perform(constraintEqualToAnchorSelector, with: contentTopAnchor)?.takeUnretainedValue() as? NSObject,
                  let leadingConstraint = leadingAnchor.perform(constraintEqualToAnchorSelector, with: contentLeadingAnchor)?.takeUnretainedValue() as? NSObject,
                  let trailingConstraint = trailingAnchor.perform(constraintEqualToAnchorSelector, with: contentTrailingAnchor)?.takeUnretainedValue() as? NSObject,
                  let bottomConstraint = bottomAnchor.perform(constraintEqualToAnchorSelector, with: contentBottomAnchor)?.takeUnretainedValue() as? NSObject
            else {
                return
            }

            let constraints = [topConstraint, leadingConstraint, trailingConstraint, bottomConstraint]
            let activateConstraintsSelector = sel_registerName("activateConstraints:")
            _ = nsLayoutConstraintClass.perform(activateConstraintsSelector, with: constraints)
        }
    }

#endif
