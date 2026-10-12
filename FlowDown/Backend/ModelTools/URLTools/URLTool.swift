//
//  URLTool.swift
//  FlowDown
//
//  Created on 2025/3/1.
//

import AlertController
import ChatClientKit
import ConfigurableKit
import Foundation
import UIKit

class MTURLTool: ModelTool, @unchecked Sendable {
    override var shortDescription: String {
        "open URLs securely with user confirmation"
    }

    override var interfaceName: String {
        String(localized: "Open URL")
    }

    override var definition: ChatRequestBody.Tool {
        .function(
            name: "open_url",
            description: """
            Opens a URL after user confirmation. This can be used to direct users to websites, apps, email clients, phone calls, or other resources.

            URLs will only be opened after explicit user approval through a confirmation dialog.
            Supports various URL schemes including http, https, mailto, tel, app-specific schemes, etc.
            """,
            parameters: [
                "type": "object",
                "properties": [
                    "url": [
                        "type": "string",
                        "description": "The URL to open. Can be any valid URL including http, https, mailto, tel, or app-specific schemes. It should be supported by iOS or macOS system.",
                    ],
                    "reason": [
                        "type": "string",
                        "description": "Brief explanation of why the user should open this URL. Will be shown in the confirmation dialog. Avoid asking user for a reason.",
                    ],
                ],
                "required": ["url", "reason"],
                "additionalProperties": false,
            ],
            strict: true,
        )
    }

    override class var controlObject: ConfigurableObject {
        .init(
            icon: "link.circle",
            title: "URL Access",
            explain: "Allows LLM to suggest URLs for you to open.",
            key: "wiki.qaq.ModelTools.URLTool.enabled",
            defaultValue: true,
            annotation: .toggle,
        )
    }

    override func execute(with input: String, anchorTo view: UIView) async throws -> String {
        guard !input.isEmpty,
              let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let urlString = json["url"] as? String,
              let reason = json["reason"] as? String
        else {
            throw NSError(domain: String(localized: "Tool"), code: -1, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "Invalid URL or missing reason."),
            ])
        }

        guard let url = URL(string: urlString) else {
            throw NSError(domain: String(localized: "Tool"), code: -1, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "Invalid URL format."),
            ])
        }

        guard let viewController = await view.parentViewController else {
            throw NSError(domain: String(localized: "Tool"), code: -1, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "Unknown Error"),
            ])
        }

        return try await requestURLOpenWithUserInteraction(
            url: url, reason: reason, controller: viewController, referencedView: view,
        )
    }

    @MainActor
    func requestURLOpenWithUserInteraction(
        url: URL,
        reason: String,
        controller: UIViewController,
        referencedView: UIView,
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let scheme = url.scheme?.lowercased() ?? ""
            let isWebURL = scheme == "http" || scheme == "https"

            let urlTypeDescription = if isWebURL {
                String(localized: "website")
            } else if scheme == "mailto" {
                String(localized: "email client")
            } else if scheme == "tel" {
                String(localized: "phone call")
            } else {
                String(localized: "external application")
            }

            let alert = AlertViewController(
                title: "Open \(urlTypeDescription.capitalized)",
                message: "The AI assistant suggests opening this URL:\n\n\(url.absoluteString)\n\nReason: \(reason)",
            ) { context in
                context.addAction(title: "Cancel") {
                    context.dispose {
                        continuation.resume(
                            throwing: NSError(domain: String(localized: "Tool"), code: -1, userInfo: [
                                NSLocalizedDescriptionKey: String(localized: "User cancelled the operation."),
                            ]),
                        )
                    }
                }
                context.addAction(title: "Open", attribute: .accent) {
                    context.dispose {
                        if isWebURL {
                            Indicator.present(url, referencedView: referencedView)
                        } else {
                            UIApplication.shared.open(url, options: [:], completionHandler: nil)
                        }

                        continuation.resume(
                            returning: String(localized: "Operation completed."),
                        )
                    }
                }
            }

            // Check if controller already has a presented view controller
            guard controller.presentedViewController == nil else {
                continuation.resume(
                    throwing: NSError(domain: String(localized: "Tool"), code: -1, userInfo: [
                        NSLocalizedDescriptionKey: String(localized: "Tool execution failed: authorization dialog is already presented."),
                    ]),
                )
                return
            }

            controller.present(alert, animated: true) {
                guard alert.isVisible else {
                    continuation.resume(
                        throwing: NSError(domain: String(localized: "Tool"), code: -1, userInfo: [
                            NSLocalizedDescriptionKey: String(localized: "Failed to display URL open request dialog."),
                        ]),
                    )
                    return
                }
            }
        }
    }
}
