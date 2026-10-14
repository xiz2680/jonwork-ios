//
//  TranslationSegment.swift
//  Jonwork
//
//  Created by qaq on 13/12/2025.
//

import Foundation

struct TranslationSegment: Identifiable, Equatable, Hashable {
    let id: UUID = .init()

    let input: String
    let translated: String
}
