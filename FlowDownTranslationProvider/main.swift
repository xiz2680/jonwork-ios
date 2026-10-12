//
//  main.swift
//  FlowDownTranslationProvider
//
//  Created by qaq on 13/12/2025.
//

import ExtensionKit
import Foundation

func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    let text = items
        .map { "\($0)" }
        .joined(separator: separator)
        + terminator
    NSLog(text)
}

print("[*] starting translation provider")

_ = scanModels()

try TranslationProviderExtension.main()
