//
//  AppGroup.swift
//  Jonwork
//
//  Created by qaq on 13/12/2025.
//

import Foundation

enum AppGroup {
    static let identifier = "group.com.jonwork.ios"

    static var containerURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: identifier,
        )
    }

    static var sharedCloudModelsURL: URL? {
        // Retain the established shared-data path for existing model files.
        containerURL?
            .appendingPathComponent("FlowDown")
            .appendingPathComponent("Models")
            .appendingPathComponent("Cloud")
    }
}
