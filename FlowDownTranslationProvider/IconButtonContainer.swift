//
//  IconButtonContainer.swift
//  FlowDown
//
//  Created by qaq on 13/12/2025.
//

import SwiftUI

struct IconButtonContainer: View {
    let icon: String
    let foregroundColor: Color

    var body: some View {
        RoundedRectangle(cornerRadius: Self.cornerRadius)
            .foregroundStyle(foregroundColor.opacity(foregroundColor == .accent ? 0.2 : 0.1))
            .overlay {
                Image(systemName: icon)
                    .fontWeight(.semibold)
                    .fontDesign(.rounded)
                    .foregroundStyle(foregroundColor)
            }
            .frame(height: Self.height)
    }
}

extension IconButtonContainer {
    static let height: CGFloat = 44
    static let cornerRadius: CGFloat = 12
}
