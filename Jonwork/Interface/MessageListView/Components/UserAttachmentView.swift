//
//  Created by ktiays on 2025/1/31.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import UIKit

final class UserAttachmentView: MessageListRowView {
    private lazy var attachmentsBar: AttachmentsBar = .init()
    private var imageTask: Task<Void, Never>?
    private var imageGeneration = UUID()
    private var imageURLs: [URL] = []
    private var isOutput = false

    override init(frame: CGRect) {
        super.init(frame: frame)

        attachmentsBar.inset = .zero
        attachmentsBar.isDeletable = false
        attachmentsBar.collectionView.alwaysBounceHorizontal = false
        contentView.addSubview(attachmentsBar)
    }

    @available(*, unavailable)
    @MainActor required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        imageTask?.cancel()
        imageTask = nil
        imageGeneration = UUID()
        imageURLs = []
        attachmentsBar.deleteAllItems()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let idealWidth = attachmentsBar.idealSize().width
        let bounds = contentView.bounds
        let width = min(idealWidth, bounds.width)
        attachmentsBar.frame = .init(
            x: isOutput ? 0 : bounds.width - width,
            y: 0,
            width: width,
            height: bounds.height,
        )
    }

    func update(with attachments: MessageListView.Attachments) {
        isOutput = false
        imageTask?.cancel()
        imageGeneration = UUID()
        imageURLs = []
        attachmentsBar.deleteAllItems()
        for element in attachments.items {
            attachmentsBar.insert(item: element)
        }
    }

    func update(outputImages urls: [URL]) {
        isOutput = true
        guard imageURLs != urls else { return }
        imageTask?.cancel()
        imageGeneration = UUID()
        let generation = imageGeneration
        imageURLs = urls
        attachmentsBar.deleteAllItems()
        imageTask = Task { [weak self] in
            for url in urls {
                guard !Task.isCancelled else { return }
                guard let data = try? await MarkdownOutputImages.load(url),
                      let thumbnail = MarkdownOutputImages.thumbnail(data),
                      let filenameExtension = MarkdownOutputImages.filenameExtension(data) else { continue }
                guard let self, !Task.isCancelled, imageGeneration == generation else { return }
                attachmentsBar.insert(item: .init(
                    type: .image,
                    name: String(localized: "Image"),
                    previewImage: thumbnail,
                    imageRepresentation: data,
                    textRepresentation: "",
                    storageSuffix: "output-preview.\(filenameExtension)",
                ))
                setNeedsLayout()
            }
        }
        setNeedsLayout()
    }

    deinit { imageTask?.cancel() }

}
