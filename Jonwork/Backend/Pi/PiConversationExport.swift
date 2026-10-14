import CoreText
import Foundation
import UIKit

/// Export the authoritative domain projection, never legacy local history.
enum PiConversationExport {
    static func markdown(title: String, messages: [PiPresentationMessage]) -> String {
        let blocks = messages.map { message in
            var parts = ["## \(String(describing: message.role).capitalized)"]
            if !message.text.isEmpty { parts.append(message.text) }
            if !message.reasoning.isEmpty { parts.append(message.reasoning.split(separator: "\n", omittingEmptySubsequences: false).map { "> \($0)" }.joined(separator: "\n")) }
            if let tool = message.tool { parts.append("### \(tool.name)\n\n\(tool.detail)") }
            return parts.joined(separator: "\n\n")
        }
        return (["# \(title)"] + blocks).joined(separator: "\n\n---\n\n") + "\n"
    }

    @MainActor
    static func pdf(title: String, messages: [PiPresentationMessage]) -> Data {
        let text = markdown(title: title, messages: messages)
        let attributed = NSAttributedString(string: text, attributes: [.font: UIFont(name: "Helvetica", size: 12)!, .foregroundColor: UIColor.black])
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        return UIGraphicsPDFRenderer(bounds: bounds).pdfData { renderer in
            var location = 0
            repeat {
                renderer.beginPage()
                let context = renderer.cgContext
                context.saveGState()
                context.textMatrix = .identity
                context.translateBy(x: 0, y: bounds.height)
                context.scaleBy(x: 1, y: -1)
                let path = CGPath(rect: bounds.insetBy(dx: 40, dy: 40), transform: nil)
                let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
                CTFrameDraw(frame, context)
                let count = CTFrameGetVisibleStringRange(frame).length
                context.restoreGState()
                precondition(count > 0 || attributed.length == 0)
                location += count
            } while location < attributed.length
        }
    }
}
