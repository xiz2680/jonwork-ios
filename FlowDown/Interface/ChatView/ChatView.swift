//
//  ChatView.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/20/25.
//

import Combine
import ConfigurableKit
import GlyphixTextFx
import SnapKit
import Storage
import UIKit

class ChatView: UIView {
    var conversationIdentifier: Conversation.ID?
    var cancellables: Set<AnyCancellable> = .init()

    let handlerColor: UIColor = .init {
        switch $0.userInterfaceStyle {
        case .light:
            .white
        default:
            .gray.withAlphaComponent(0.1)
        }
    }

    #if !targetEnvironment(macCatalyst)
        let escapeButton = EasyHitImageCircleButton(name: "sidebar.left", distinctStyle: .none)
    #endif

    let editor = RichEditorView()
    let editorBackgroundView = UIView().with {
        $0.backgroundColor = .background
        let sep = SeparatorView()
        $0.addSubview(sep)
        sep.snp.makeConstraints { make in
            make.left.top.right.equalToSuperview()
            make.height.equalTo(1)
        }
    }

    let sessionManager = ConversationSessionManager.shared
    private var messageListViews: [Conversation.ID: MessageListView] = [:]
    var currentMessageListView: MessageListView? {
        guard let id = conversationIdentifier else {
            return nil
        }
        if let listView = messageListViews[id] {
            return listView
        }

        // If the message list view is not found, create a new one.
        let listView = MessageListView()
        listView.session = sessionManager.session(for: id)
        messageListViews[id] = listView
        return listView
    }

    @TypedStorage(key: "Chat.Editor.Model.Name.Style", defaultValue: EditorModelNameStyle.trimmed)
    var editorModelNameStyle: EditorModelNameStyle {
        didSet { editor.updateModelName() }
    }

    @TypedStorage(key: "Chat.Editor.Model.Apply.Default", defaultValue: true)
    var editorApplyModelToDefault: Bool

    let title = TitleBar()
    let piStatusView = PiSessionStatusView()

    var onCreateNewChat: (() -> Void)?
    var onSuggestNewChat: ((Conversation.ID) -> Void)?

    init() {
        super.init(frame: .zero)

        addSubview(editorBackgroundView)
        addSubview(editor)

        #if !targetEnvironment(macCatalyst)
            let escapeButtonGlass = escapeButton.wrappedInGlassEffect(cornerStyle: .capsule)
            addSubview(escapeButtonGlass)
        #endif

        addSubview(title)
        addSubview(piStatusView)

        #if !targetEnvironment(macCatalyst)
            bringSubviewToFront(escapeButtonGlass)
        #endif

        piStatusView.snp.makeConstraints { make in
            make.top.equalTo(title.snp.bottom).offset(8)
            make.centerX.equalToSuperview()
            make.width.lessThanOrEqualToSuperview().inset(64)
            make.height.greaterThanOrEqualTo(44)
        }

        editor.handlerColor = handlerColor
        editor.delegate = self
        editor.snp.makeConstraints { make in
            #if targetEnvironment(macCatalyst)
                make.bottom.equalToSuperview()
            #else
                make.bottom.equalTo(safeAreaLayoutGuide)
            #endif
            make.centerX.equalToSuperview()
            make.width.lessThanOrEqualTo(750)
            make.width.lessThanOrEqualToSuperview()
            make.width.equalToSuperview().priority(.low)
        }

        editorBackgroundView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            #if targetEnvironment(macCatalyst)
                make.bottom.equalToSuperview()
            #else
                make.bottom.equalToSuperview().offset(128)
            #endif
            make.top.equalTo(editor.snp.top).offset(-4) // for visual
        }

        sessionManager.executingSessionsPublisher
            .sink { [weak self] executingSessions in
                guard let self, let conversationID = conversationIdentifier else { return }
                let isExecuting = executingSessions.contains(conversationID)
                editor.setProcessingMode(isExecuting)
            }
            .store(in: &cancellables)

        #if !targetEnvironment(macCatalyst)
            escapeButton.backgroundColor = .clear
            escapeButtonGlass.snp.makeConstraints { make in
                make.top.equalTo(safeAreaLayoutGuide).inset(10)
                make.leading.equalTo(safeAreaLayoutGuide).inset(10)
                make.width.height.equalTo(40)
            }
            title.snp.makeConstraints { make in
                make.left.top.right.equalToSuperview()
                make.bottom.equalTo(escapeButtonGlass).offset(10)
            }
        #else
            setupTitleLayout()
        #endif

        title.onCreateNewChat = { [weak self] in
            self?.onCreateNewChat?()
        }
        title.onSuggestSelection = { [weak self] id in
            self?.onSuggestNewChat?(id)
        }

        editor.heightPublisher
            .ensureMainThread()
            .sink { [weak self] _ in
                self?.setNeedsLayout()
            }
            .store(in: &cancellables)

        Self.editorModelNameStyle.onChange
            .compactMap { try? $0.decodingValue() }
            .compactMap { EditorModelNameStyle(rawValue: $0) }
            .sink { [weak self] output in self?.editorModelNameStyle = output }
            .store(in: &cancellables)

        Self.editorApplyModelToDefault.onChange
            .compactMap { try? $0.decodingValue() }
            .sink { [weak self] output in self?.editorApplyModelToDefault = output }
            .store(in: &cancellables)

        ConversationManager.removeAllEditorObjectsPublisher
            .ensureMainThread()
            .sink { [weak self] _ in
                let id = self?.conversationIdentifier
                self?.prepareForReuse()
                guard let id else { return }
                self?.use(conversation: id)
            }
            .store(in: &cancellables)

        ModelManager.shared.modelChangedPublisher
            .ensureMainThread()
            .sink { [weak self] _ in
                self?.editor.updateModelName()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSNotification.Name("RefreshRichEditor"))
            .ensureMainThread()
            .sink { [weak self] notification in
                guard let self,
                      let conversationID = notification.object as? Conversation.ID,
                      conversationID == conversationIdentifier
                else { return }
                editor.restoreEditorStatusIfPossible()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSNotification.Name("TriggerSendMessage"))
            .ensureMainThread()
            .sink { [weak self] notification in
                guard let self,
                      let conversationID = notification.object as? Conversation.ID,
                      conversationID == conversationIdentifier
                else { return }
                editor.submitValues()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .piSessionDidChange)
            .ensureMainThread()
            .sink { [weak self] notification in
                guard let self,
                      let conversationID = notification.object as? Conversation.ID,
                      conversationID == conversationIdentifier
                else { return }
                updatePiPresentation()
            }
            .store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    func focusEditor() {
        editor.focus()
    }

    func prepareForReuse() {
        // Removes the current message list view from the superview.
        currentMessageListView?.removeFromSuperview()
        conversationIdentifier = nil
        editor.prepareForReuse()
    }

    func setupTitleLayout(_ height: CGFloat? = nil) {
        title.snp.remakeConstraints { make in
            make.left.top.right.equalToSuperview()
            if let height {
                make.height.equalTo(height).priority(.high)
            }
        }
    }

    func use(conversation: Conversation.ID, completion: (() -> Void)? = nil) {
        if conversationIdentifier == conversation {
            completion?()
            return
        }
        conversationIdentifier = conversation

        // dont do it here, stream may still alive
        // ConversationSessionManager.shared.resolvePendingRefresh(for: conversation)

        if let listView = currentMessageListView {
            insertSubview(listView, belowSubview: editorBackgroundView)
            listView.snp.makeConstraints { make in
                make.edges.equalToSuperview()
            }
            listView.isHidden = false
        }

        for key in messageListViews.keys {
            if key != conversation {
                messageListViews[key]?.isHidden = true
            }
        }

        editor.use(identifier: conversation)
        title.use(identifier: conversation)
        PiSessionCoordinator.shared.activate(conversationID: conversation)
        updatePiPresentation()

        let isExecuting = sessionManager.isSessionExecuting(conversation)
        editor.setProcessingMode(isExecuting)
        updateCurrentMessageListInsets()

        offloadModelsToSession(modelIdentifier: modelIdentifier())
        removeUnusedListViews()
        Task { @MainActor in
            completion?()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateCurrentMessageListInsets()
    }

    private func updateCurrentMessageListInsets() {
        guard let currentMessageListView else { return }
        let visibleEditorTop = min(editor.frame.minY, editorBackgroundView.frame.minY)

        let headerBottom = piStatusView.isHidden ? title.frame.maxY : piStatusView.frame.maxY
        currentMessageListView.contentSafeAreaInsets = .init(
            top: headerBottom + 16,
            left: 0,
            bottom: bounds.height - visibleEditorTop + 16,
            right: 0,
        )
        currentMessageListView.scrollIndicatorInsets = .init(
            top: title.frame.maxY,
            left: 0,
            bottom: bounds.height - visibleEditorTop,
            right: 0,
        )
    }

    private func updatePiPresentation() {
        guard let conversationIdentifier,
              PiSessionCoordinator.shared.binding(for: conversationIdentifier) != nil
        else {
            piStatusView.isHidden = true
            editor.isUserInteractionEnabled = true
            setNeedsLayout()
            return
        }

        if let viewState = PiSessionCoordinator.shared.viewState(for: conversationIdentifier) {
            piStatusView.update(viewState)
            let state = viewState.conversation
            editor.isUserInteractionEnabled = viewState.connection == .connected
                && state.role == .controller
                && !state.isReleased
            piStatusView.actionButton.menu = buildPiSessionMenu(viewState: viewState)
        } else {
            piStatusView.showConnecting()
            editor.isUserInteractionEnabled = false
            piStatusView.actionButton.menu = nil
        }
        setNeedsLayout()
    }

    private func buildPiSessionMenu(viewState: PiSessionCoordinator.ViewState) -> UIMenu {
        guard let conversationIdentifier else { return UIMenu() }
        if viewState.connection != .connected {
            return UIMenu(title: String(localized: "Pi Session"), children: [
                UIAction(
                    title: String(localized: "Retry"),
                    image: UIImage(systemName: "arrow.clockwise")
                ) { _ in
                    Task { @MainActor in
                        PiSessionCoordinator.shared.reconnect(conversationID: conversationIdentifier)
                    }
                },
            ])
        }
        let state = viewState.conversation
        var actions: [UIMenuElement] = []
        if state.role == .controller, state.isStreaming {
            actions.append(UIAction(
                title: String(localized: "Stop Response"),
                image: UIImage(systemName: "stop.circle")
            ) { [weak self] _ in
                Task { await self?.performPiAction { try await PiSessionCoordinator.shared.abort(conversationID: conversationIdentifier) } }
            })
        }
        if state.role == .viewer, !state.isStreaming {
            actions.append(UIAction(
                title: String(localized: "Take Control"),
                image: UIImage(systemName: "hand.raised")
            ) { [weak self] _ in
                Task { await self?.performPiAction { try await PiSessionCoordinator.shared.takeOver(conversationID: conversationIdentifier) } }
            })
        } else if state.role == .viewer, state.isStreaming {
            actions.append(UIAction(
                title: String(localized: "Take Control is unavailable while Pi is working."),
                image: UIImage(systemName: "hand.raised"),
                attributes: .disabled
            ) { _ in })
        }
        if state.role == .controller, !state.isReleased {
            actions.append(UIAction(
                title: String(localized: "Release to Pi CLI"),
                image: UIImage(systemName: "terminal"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.confirmPiRelease(conversationID: conversationIdentifier)
            })
        }
        if actions.isEmpty {
            actions.append(UIAction(
                title: String(localized: "No actions available"),
                attributes: .disabled
            ) { _ in })
        }
        return UIMenu(title: String(localized: "Pi Session"), children: actions)
    }

    private func confirmPiRelease(conversationID: Conversation.ID) {
        let alert = UIAlertController(
            title: String(localized: "Release to Pi CLI?"),
            message: String(localized: "The mobile runtime will close. Your durable session stays available in the Pi CLI."),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "Release"), style: .destructive) { [weak self] _ in
            Task { await self?.performPiAction { try await PiSessionCoordinator.shared.release(conversationID: conversationID) } }
        })
        parentViewController?.present(alert, animated: true)
    }

    private func performPiAction(_ action: @escaping @MainActor () async throws -> Void) async {
        do {
            try await action()
        } catch {
            let errorKey: String.LocalizationValue = "\(error.localizedDescription)"
            Indicator.present(title: errorKey, preset: .error, referencingView: self)
        }
    }

    private func removeUnusedListViews() {
        let conversationIDs: Set<Conversation.ID> = .init(ConversationManager.shared.conversations.value.keys)
        let unusedKeys = messageListViews.keys.filter { !conversationIDs.contains($0) }

        for key in unusedKeys {
            messageListViews.removeValue(forKey: key)?.removeFromSuperview()
        }
    }
}

extension ChatView {
    class TitleBar: UIView {
        let textLabel: GlyphixTextLabel = .init().with {
            $0.font = .preferredFont(forTextStyle: .body).bold
            $0.isBlurEffectEnabled = false
            $0.textColor = .label
            $0.textAlignment = .center
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.clipsToBounds = false
        }

        let icon = UIImageView().with {
            $0.contentMode = .scaleAspectFit
            $0.tintColor = .accent
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        let menuButton = EasyMenuButton().with {
            var config = UIButton.Configuration.plain()
            config.image = UIImage(systemName: "chevron.down")
            $0.imageView?.contentMode = .scaleAspectFit
            $0.configuration = config
            $0.tintColor = .gray.withAlphaComponent(0.5)
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.showsMenuAsPrimaryAction = true
        }

        #if targetEnvironment(macCatalyst)
            let bg = UIView().with { $0.backgroundColor = .background }
            let sep = SeparatorView()
        #else
            let edgeEffectView = ChatHeaderEdgeEffectView()
            let backgroundContainer = ChatHeaderGlassBackgroundContainerView()
        #endif

        let rightClick = RightClickFinder()
        var cancellables: Set<AnyCancellable> = .init()

        var onCreateNewChat: (() -> Void)?
        var onSuggestSelection: ((Conversation.ID) -> Void)?

        init() {
            super.init(frame: .zero)
            translatesAutoresizingMaskIntoConstraints = false

            snp.makeConstraints { make in
                make.height.equalTo(40).priority(.low)
            }

            #if targetEnvironment(macCatalyst)
                addSubview(bg)
                bg.snp.makeConstraints { make in
                    make.left.bottom.right.equalToSuperview()
                    make.top.equalToSuperview().offset(-128)
                }
                addSubview(sep)
                sep.snp.makeConstraints { make in
                    make.left.right.equalToSuperview()
                    make.bottom.equalToSuperview()
                    make.height.equalTo(1)
                }

                addSubview(icon)
                addSubview(textLabel)
                addSubview(menuButton)

                icon.snp.makeConstraints { make in
                    make.centerY.equalToSuperview()
                    make.left.equalToSuperview().inset(20)
                    make.width.height.equalTo(24)
                }
                textLabel.snp.makeConstraints { make in
                    make.center.equalToSuperview()
                    make.top.greaterThanOrEqualToSuperview()
                    make.bottom.lessThanOrEqualToSuperview()
                    make.left.greaterThanOrEqualTo(icon.snp.right).offset(8)
                    make.right.lessThanOrEqualTo(menuButton.snp.left).offset(-8)
                }
                menuButton.snp.makeConstraints { make in
                    make.centerY.equalToSuperview()
                    make.right.equalToSuperview().inset(20)
                    make.width.height.equalTo(18)
                }
            #else
                clipsToBounds = false

                addSubview(edgeEffectView)
                addSubview(backgroundContainer)

                backgroundContainer.contentView.addSubview(icon)
                backgroundContainer.contentView.addSubview(textLabel)

                let menuButtonGlass = menuButton.wrappedInGlassEffect(cornerStyle: .capsule)
                backgroundContainer.contentView.addSubview(menuButtonGlass)

                menuButtonGlass.snp.makeConstraints { make in
                    make.centerY.equalToSuperview()
                    make.right.equalToSuperview().inset(12)
                    make.width.height.equalTo(34)
                }

                icon.snp.makeConstraints { make in
                    make.centerY.equalToSuperview()
                    make.left.equalToSuperview().inset(20)
                    make.width.height.equalTo(24)
                }
                textLabel.snp.makeConstraints { make in
                    make.centerX.equalToSuperview()
                    make.centerY.equalToSuperview()
                    make.top.greaterThanOrEqualToSuperview()
                    make.bottom.lessThanOrEqualToSuperview()
                    make.left.greaterThanOrEqualTo(icon.snp.right).offset(8)
                    make.right.lessThanOrEqualTo(menuButtonGlass.snp.left).offset(-8)
                }

                icon.alpha = 0
            #endif

            menuButton.menu = UIMenu(children: [
                UIDeferredMenuElement.uncached { [weak self] completion in
                    completion(self?.buildMenu()?.children ?? [])
                },
            ])

            ConversationManager.shared.conversations
                .ensureMainThread()
                .sink { [weak self] _ in
                    self?.use(identifier: self?.conv)
                }
                .store(in: &cancellables)

            #if !targetEnvironment(macCatalyst)
                _ = registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: TitleBar, _: UITraitCollection) in
                    view.updateBackgroundInterfaceStyle()
                }
                updateBackgroundInterfaceStyle()
            #endif
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }

        #if !targetEnvironment(macCatalyst)
            override func layoutSubviews() {
                super.layoutSubviews()

                let safeTop = safeAreaInsets.top

                let usesUnifiedBackdrop = if #available(iOS 26.0, *) {
                    false
                } else {
                    true
                }

                if usesUnifiedBackdrop {
                    backgroundContainer.frame = CGRect(
                        x: 0,
                        y: 0,
                        width: bounds.width,
                        height: bounds.height,
                    )
                    backgroundContainer.setContentTopOffset(safeTop)
                } else {
                    backgroundContainer.frame = CGRect(
                        x: 0,
                        y: safeTop,
                        width: bounds.width,
                        height: max(0, bounds.height - safeTop),
                    )
                    backgroundContainer.setContentTopOffset(0)
                }

                let edgeHeight = bounds.height + 14
                edgeEffectView.update(
                    content: .background,
                    blur: usesUnifiedBackdrop,
                    alpha: 0.85,
                    rect: CGRect(x: 0, y: 0, width: bounds.width, height: edgeHeight),
                    edge: .top,
                    edgeSize: min(54, edgeHeight),
                )
            }
        #endif

        deinit {
            cancellables.forEach { $0.cancel() }
            cancellables.removeAll()
        }

        #if !targetEnvironment(macCatalyst)
            override func didMoveToWindow() {
                super.didMoveToWindow()
                updateBackgroundInterfaceStyle()
            }
        #endif

        private var conv: Conversation.ID?

        #if !targetEnvironment(macCatalyst)
            private func updateBackgroundInterfaceStyle() {
                backgroundContainer.update(isDark: traitCollection.userInterfaceStyle == .dark)
            }

            func setDecorativeBackgroundHidden(_ isHidden: Bool) {
                backgroundContainer.setVisualEffectEnabled(!isHidden)
                edgeEffectView.isHidden = isHidden
            }
        #else
            func setDecorativeBackgroundHidden(_ isHidden: Bool) {
                bg.isHidden = isHidden
                sep.isHidden = isHidden
            }
        #endif

        func use(identifier: Conversation.ID?) {
            conv = identifier
            let conversation = ConversationManager.shared.conversation(identifier: identifier)
            icon.image = conversation?.interfaceImage
            doWithAnimation {
                self.textLabel.text = conversation?.title ?? String(localized: "Untitled")
            }
        }

        func contextMenuInteraction(
            _: UIContextMenuInteraction,
            configurationForMenuAtLocation _: CGPoint,
        ) -> UIContextMenuConfiguration? {
            UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
                self?.buildMenu()
            }
        }

        private func buildMenu() -> UIMenu? {
            guard let conv else { return nil }
            guard let convMenu = ConversationManager.shared.menu(
                forConversation: conv,
                view: self,
            ) else { return nil }

            #if targetEnvironment(macCatalyst)
                // On Catalyst, only show conversation menu (new chat button is handled by sidebar)
                if let mainController = parentViewController as? MainController,
                   mainController.isSidebarCollapsed
                {
                    return UIMenu(children: [
                        convMenu,
                        UIAction(title: String(localized: "Show Sidebar"), image: UIImage(systemName: "sidebar.left")) { _ in
                            mainController.openSidebar()
                        },
                    ])
                } else {
                    return convMenu
                }
            #else
                // On iOS, show both new chat options and conversation menu
                let mainMenu = UIDeferredMenuElement.uncached { [weak self] completion in
                    guard let self else {
                        completion([])
                        return
                    }

                    let templates = ChatTemplateManager.shared.templates
                    var newChatOptions: [UIMenuElement] = []

                    if templates.isEmpty {
                        // No templates, just show "Start New Chat"
                        newChatOptions.append(UIAction(
                            title: String(localized: "Start New Chat"),
                            image: UIImage(systemName: "plus"),
                        ) { [weak self] _ in
                            self?.onCreateNewChat?()
                        })
                    } else {
                        // Show template options
                        newChatOptions.append(UIAction(
                            title: String(localized: "Start New Chat"),
                            image: UIImage(systemName: "plus"),
                        ) { [weak self] _ in
                            self?.onCreateNewChat?()
                        })

                        var templatesMenuActions: [UIAction] = []
                        for template in templates.values {
                            templatesMenuActions.append(UIAction(
                                title: template.name,
                                image: UIImage(data: template.avatar),
                            ) { [weak self] _ in
                                let convId = ChatTemplateManager.shared.createConversationFromTemplate(template)
                                self?.onSuggestSelection?(convId)
                            })
                        }
                        newChatOptions.append(UIMenu(
                            title: String(localized: "Choose Template"),
                            image: UIImage(systemName: "folder"),
                            children: templatesMenuActions,
                        ))
                    }

                    completion([
                        UIMenu(
                            title: String(localized: "New Conversation"),
                            options: [.displayInline],
                            children: newChatOptions,
                        ),
                        convMenu,
                    ])
                }
                return .init(children: [mainMenu])
            #endif
        }
    }
}

extension ChatView.TitleBar {
    class EasyMenuButton: UIButton {
        open var easyHitInsets: UIEdgeInsets = .init(top: -16, left: -16, bottom: -16, right: -16)

        override open func point(inside point: CGPoint, with _: UIEvent?) -> Bool {
            bounds.inset(by: easyHitInsets).contains(point)
        }
    }
}
