//
//  TemporaryStorage.swift
//  RichEditor
//
//  Created by 秋星桥 on 1/17/25.
//

import Foundation

class TemporaryStorage {
    let storageDir: URL

    init(id: String) {
        storageDir = RichEditorView.temporaryStorage
            .appendingPathComponent(id)
        try? FileManager.default.createDirectory(
            at: storageDir,
            withIntermediateDirectories: true,
        )
    }

    func random() -> String {
        UUID().uuidString
    }

    func absoluteURL(_ suffix: String) -> URL {
        storageDir.appendingPathComponent(suffix)
    }

    func duplicateIfNeeded(_ file: URL) -> URL? {
        assert(file.isFileURL)
        if file.path.hasPrefix(storageDir.path) { return file }
        var suffix = random()
        let ext = file.pathExtension
        if !ext.isEmpty { suffix += ".\(ext)" }
        let url = absoluteURL(suffix)
        do {
            try FileManager.default.copyItem(at: file, to: url)
        } catch {
            return nil
        }
        return url
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: storageDir)
        try? FileManager.default.createDirectory(
            at: storageDir,
            withIntermediateDirectories: true,
        )
    }
}
