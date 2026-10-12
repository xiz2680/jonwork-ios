//
//  HubModelDownloadController+Delegates.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/27/25.
//

import BetterCodable
import ConfigurableKit
import Foundation
import UIKit

extension HubModelDownloadController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let model = dataSource.itemIdentifier(for: indexPath) else {
            return
        }

        let detail = HubModelDetailController(model: model)
        navigationController?.pushViewController(detail, animated: true)
    }
}

extension HubModelDownloadController: UISearchBarDelegate, UISearchControllerDelegate {
    func searchBar(_: UISearchBar, textDidChange _: String) {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(commitSearch), object: nil)
        perform(#selector(commitSearch), with: nil, afterDelay: 0.25)
    }

    @objc func commitSearch() {
        updateDataSource()
    }
}
