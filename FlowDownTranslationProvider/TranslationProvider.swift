//
//  TranslationProvider.swift
//  FlowDownTranslationProvider
//
//  Created by qaq on 13/12/2025.
//

import ExtensionKit
import SwiftUI
import TranslationUIProvider

@MainActor
class TranslationProviderExtension: TranslationUIProviderExtension {
    required init() {}

    var body: some TranslationUIProviderExtensionScene {
        TranslationUIProviderSelectedTextScene { context in
            TranslationProviderView(context: context)
        }
    }
}
