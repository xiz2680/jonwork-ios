//
//  TranslateSegmentView.swift
//  FlowDown
//
//  Created by qaq on 13/12/2025.
//

import SwiftUI

struct TranslateSegmentView: View {
    let segment: TranslationSegment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(segment.input)
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
                .font(.body)
                .opacity(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Text(segment.translated)
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
