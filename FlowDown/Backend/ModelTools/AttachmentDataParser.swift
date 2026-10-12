//
//  AttachmentDataParser.swift
//  FlowDown
//
//  Created by GPT-5 Codex on 2025/12/06.
//

import Foundation

enum AttachmentDataParser {
    /// Decode data from common string encodings (data URLs, base64, plain text).
    static func decodeData(from dataString: String) -> Data? {
        // Handle data URL format: data:image/png;base64,<base64_string>
        if dataString.hasPrefix("data:") {
            // Extract the part after ";base64," or after the first comma
            if let base64Range = dataString.range(of: ";base64,") {
                let base64String = String(dataString[base64Range.upperBound...])
                return Data(base64Encoded: base64String)
            } else if let commaIndex = dataString.firstIndex(of: ",") {
                // Handle data URL without base64 encoding
                let afterComma = String(dataString[dataString.index(after: commaIndex)...])
                // Try base64 first, then fallback to URL-encoded or plain text
                return Data(base64Encoded: afterComma) ?? afterComma.data(using: .utf8)
            }
            return nil
        }

        // Handle URL string (for data URLs parsed as URL)
        if let url = URL(string: dataString), url.scheme == "data" {
            let absoluteString = url.absoluteString
            if let base64Range = absoluteString.range(of: ";base64,") {
                let base64String = String(absoluteString[base64Range.upperBound...])
                return Data(base64Encoded: base64String)
            } else if let commaIndex = absoluteString.firstIndex(of: ",") {
                let afterComma = String(absoluteString[absoluteString.index(after: commaIndex)...])
                return Data(base64Encoded: afterComma) ?? afterComma.data(using: .utf8)
            }
            return nil
        }

        // Try as direct base64 string (most common case for MCP tools)
        if let data = Data(base64Encoded: dataString, options: .ignoreUnknownCharacters) {
            return data
        }

        // Fallback: treat as UTF-8 string data (should rarely happen)
        return dataString.data(using: .utf8)
    }
}
