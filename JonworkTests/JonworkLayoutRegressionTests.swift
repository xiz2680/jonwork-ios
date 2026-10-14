@testable import Jonwork
import Foundation
import GlyphixTextFx
import Testing
import UIKit

@Suite(.serialized)
struct JonworkLayoutRegressionTests {
    @Test(arguments: [CGFloat(314), 320, 430]) @MainActor
    func titleMenuAndNewConversationHaveSeparateVisibleAndHitFrames(width: CGFloat) throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = .init(x: 0, y: 0, width: width, height: 800)
        let presenter = UIViewController()
        window.rootViewController = presenter
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let header = ChatView.TitleBar(allowsLegacyConversations: true)
        presenter.view.addSubview(header)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: presenter.view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: presenter.view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: presenter.view.trailingAnchor),
        ])
        header.use(identifier: nil)
        header.piControls.isHidden = false
        header.textLabel.text = "iOS connection acceptance conversation with a long title"
        for category in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
            header.traitOverrides.preferredContentSizeCategory = category
            header.textLabel.font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: header.traitCollection).bold
            presenter.view.setNeedsLayout()
            presenter.view.layoutIfNeeded()
            let menu = header.menuButton
            let newConversation = header.piControls.actionButton
            let menuFrame = menu.convert(menu.bounds, to: header)
            let newFrame = newConversation.convert(newConversation.bounds, to: header)
            let titleFrame = header.textLabel.convert(header.textLabel.bounds, to: header)
            #expect(menuFrame.width >= 44 && menuFrame.height >= 44)
            #expect(newFrame.width >= 44 && newFrame.height >= 44)
            #expect(titleFrame.maxX + 8 <= menuFrame.minX + 0.5)
            #expect(menuFrame.maxX + 8 <= newFrame.minX + 0.5)
            #expect(!menuFrame.intersects(newFrame))
            #expect(header.bounds.contains(menuFrame))
            #expect(header.bounds.contains(newFrame))
            #expect(header.hitTest(.init(x: menuFrame.midX, y: menuFrame.midY), with: nil) === menu)
            #expect(header.hitTest(.init(x: newFrame.midX, y: newFrame.midY), with: nil) === newConversation)
            for frame in [menuFrame, newFrame] {
                let expected: UIView = frame == menuFrame ? menu : newConversation
                for point in [CGPoint(x: frame.midX, y: frame.minY + 1), CGPoint(x: frame.midX, y: frame.maxY - 1), CGPoint(x: frame.minX + 1, y: frame.midY), CGPoint(x: frame.maxX - 1, y: frame.midY)] {
                    #expect(header.hitTest(point, with: nil) === expected)
                }
            }
            #expect(!menu.point(inside: menu.convert(.init(x: newFrame.midX, y: newFrame.midY), from: header), with: nil))
        }
    }

    @Test @MainActor
    func nativeComposerKeepsAttachmentReachableWhileEditingWithoutOverlappingSend() {
        let editor = RichEditorView()
        editor.setJonworkConversation(true, allowsImageAttachments: true, allowsPhotoLibrary: true)
        let input = editor.inputEditor
        input.frame = .init(x: 0, y: 0, width: 320, height: 56)
        input.textView.text = "A draft"
        input.layoutStatus = .editingText
        input.setNeedsLayout()
        input.layoutIfNeeded()
        #expect(!input.bossButton.isHidden)
        #expect(input.bossButton.alpha == 1)
        #expect(input.sendButton.alpha == 1)
        #expect(input.voiceButton.alpha == 1)
        #expect(input.textView.frame.minX >= input.bossButton.frame.maxX)
        #expect(input.textView.frame.maxX <= input.sendButton.frame.minX)
        #expect(input.bossButton.imageView.image != nil)
        input.textView.text = ""
        input.layoutStatus = .standard
        input.setNeedsLayout()
        input.layoutIfNeeded()
        #expect(input.voiceButton.alpha == 1)
        #expect(input.sendButton.alpha == 0)
    }

    @Test @MainActor
    func attachmentOnlyDraftShowsSendAndClearingRestoresVoice() {
        let editor = RichEditorView()
        editor.setJonworkConversation(true, allowsFileAttachments: true, allowsFilePicker: true, attachmentMaximumCount: 4)
        let input = editor.inputEditor
        input.frame = .init(x: 0, y: 0, width: 320, height: 56)
        input.textView.text = ""
        editor.attachmentsBar.insert(item: .init(type: .text, name: "fixture.txt", previewImage: Data(), imageRepresentation: Data(), textRepresentation: "Fixture text", storageSuffix: "fixture.txt"))
        input.layoutIfNeeded()
        #expect(input.hasAttachments)
        #expect(input.sendButton.alpha == 1)
        #expect(input.voiceButton.alpha == 1)
        #expect(!editor.collectObject().hasEmptyContent)
        editor.attachmentsBar.deleteAllItems()
        input.layoutIfNeeded()
        #expect(!input.hasAttachments)
        #expect(input.sendButton.alpha == 0)
        #expect(input.voiceButton.alpha == 1)
    }

    @Test @MainActor
    func rapidNewConversationTapsConstructOnlyOneNativeEntry() throws {
        let presenter = UIViewController()
        let window = UIWindow(frame: .init(x: 0, y: 0, width: 390, height: 800))
        window.rootViewController = presenter
        window.isHidden = false
        defer { presenter.dismiss(animated: false); window.isHidden = true }
        let button = NewChatButton()
        presenter.view.addSubview(button)
        var entries = 0
        let destination = UIViewController()
        button.makeJonworkController = { entries += 1; return destination }
        button.sendActions(for: .touchUpInside)
        button.sendActions(for: .touchUpInside)
        #expect(entries == 1)
        #expect(presenter.presentedViewController === destination)
        let detached = NewChatButton()
        detached.makeJonworkController = { entries += 1; return UIViewController() }
        detached.sendActions(for: .touchUpInside)
        #expect(entries == 1)
    }

    @Test @MainActor
    func initialWorkspaceSnapshotAndSearchReloadRepositoriesAndSessionsCoherently() {
        let workspace = SettingController.SettingContent.PiServerController(autoConnect: false)
        workspace.loadViewIfNeeded()
        workspace.tableView.frame = .init(x: 0, y: 0, width: 390, height: 700)
        workspace.tableView.layoutIfNeeded()
        workspace.apply(.init(
            repositories: [.init(id: "first", displayName: "First"), .init(id: "second", displayName: "Second")],
            sessions: [.init(id: "a", name: "Alpha", messageCount: 1, isRunning: false), .init(id: "b", name: "Beta", messageCount: 2, isRunning: false)],
            selectedRepositoryID: "first", isConnected: false
        ))
        workspace.tableView.layoutIfNeeded()
        #expect(workspace.tableView.numberOfRows(inSection: 1) == 3)
        #expect(workspace.tableView.numberOfRows(inSection: 2) == 2)
        let search = UISearchController()
        search.searchBar.text = "Alpha"
        workspace.updateSearchResults(for: search)
        workspace.tableView.layoutIfNeeded()
        #expect(workspace.tableView.numberOfRows(inSection: 1) == 3)
        #expect(workspace.tableView.numberOfRows(inSection: 2) == 1)
        workspace.apply(.init(repositories: [], sessions: [], isConnected: false))
        workspace.tableView.layoutIfNeeded()
        #expect(workspace.tableView.numberOfRows(inSection: 1) == 1)
        #expect(workspace.tableView.numberOfRows(inSection: 2) == 1)
    }
}
