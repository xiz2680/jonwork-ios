//
//  AttachmentsBar+Type.swift
//  RichEditor
//
//  Created by 秋星桥 on 1/17/25.
//

import UIKit

extension AttachmentsBar {
    enum Section { case main }
    typealias Item = RichEditorView.Object.Attachment
    typealias ItemIdentifier = Item.ID
    typealias DataSource = UICollectionViewDiffableDataSource<Section, ItemIdentifier>
    typealias Snapshot = NSDiffableDataSourceSnapshot<Section, ItemIdentifier>
}
