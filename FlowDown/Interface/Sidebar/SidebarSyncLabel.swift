//
//  SidebarSyncLabel.swift
//  FlowDown
//
//  Created by qaq on 24/10/2025.
//

import Combine
import GlyphixTextFx
import SnapKit
import Storage
import UIKit

private let formatter: RelativeDateTimeFormatter = {
    let fmt = RelativeDateTimeFormatter()
    fmt.unitsStyle = .short
    return fmt
}()

class SidebarSyncLabel: UIView {
    let textLabel: GlyphixTextLabel = .init().with {
        $0.font = .preferredFont(forTextStyle: .caption1)
        $0.textColor = .secondaryLabel
        $0.alpha = 0.5
        $0.isBlurEffectEnabled = true
        $0.textAlignment = .center
        $0.translatesAutoresizingMaskIntoConstraints = false
        $0.clipsToBounds = true
    }

    var cancellables = Set<AnyCancellable>()

    init() {
        super.init(frame: .zero)

        addSubview(textLabel)
        textLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        NotificationCenter.default.publisher(for: SyncEngine.SyncStatusChanged)
            .delay(for: .seconds(0.1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateSyncStatus()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: SyncEngine.SyncStatusChanged)
            .delay(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateSyncStatus()
            }
            .store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateSyncStatus() {
        if SyncEngine.isSynchronizing {
            textLabel.text = String(localized: "Syncing with iCloud")
        } else {
            if let date = SyncEngine.LastSyncDate,
               // 会出现 0 秒后 这种文案。。醉了
               let dateText = formatter.string(for: date.addingTimeInterval(-1))
            {
                let text = String(localized: "Last synced \(dateText)")
                textLabel.text = text
            }
        }

        scheduleTextDismissal()
    }

    func scheduleTextDismissal() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(dismissText), object: nil)
        perform(#selector(dismissText), with: nil, afterDelay: 3.0)
    }

    @objc func dismissText() {
        textLabel.text = ""
    }
}
