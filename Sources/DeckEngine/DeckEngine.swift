import DeckConfig
import DeckHID
import DeckRender
import Foundation

/// Ties config, navigation, rendering, actions and the device together.
@MainActor
public final class DeckEngine {
    public struct Status: Equatable, Sendable {
        public var connected = false
        public var device: DeviceInfo?
        public var page: String?
        public var autoSwitch = true
        public var problems: [Problem] = []

        public init() {}

        init(connected: Bool, device: DeviceInfo?, page: String?, autoSwitch: Bool, problems: [Problem]) {
            self.connected = connected
            self.device = device
            self.page = page
            self.autoSwitch = autoSwitch
            self.problems = problems
        }
    }

    public static let dynamicTimeout: TimeInterval = 10

    public private(set) var status = Status()
    public var onStatusChange: ((Status) -> Void)?

    /// While set, the device shows this page instead of the one navigation selects.
    /// Navigation keeps tracking apps, so clearing it returns to the right page.
    public var editorPage: String? {
        didSet { if editorPage != oldValue { pageMayHaveChanged() } }
    }

    /// While set, a key-down calls this instead of running the key's action.
    public var onEditorKeyPress: ((Int) -> Void)?

    private let transport: DeckTransport
    private let performer: ActionPerformer
    private let commands: CommandRunner
    /// Relative icon paths in dynamic output resolve against this.
    private let configDirectory: URL
    private let ownBundleID: String

    private var config: DeckConfig?
    private var navigation: Navigation?
    private var frontmostApp: String?
    private var autoSwitch = true
    private var brightnessOverride: Int?
    private var connected = false
    private var device: DeviceInfo?
    private var eventTask: Task<Void, Never>?

    /// Last JPEG sent per key; only changed keys are written.
    private var lastSent: [Int: Data] = [:]
    private var pressed: Set<Int> = []
    private var dynamicOutputs: [Int: DynamicOutput] = [:]
    private var dynamicFailed: Set<Int> = []
    private var dynamicTasks: [Int: Task<Void, Never>] = [:]
    private var problems: [Problem.Source: String] = [:]

    public init(transport: DeckTransport, performer: ActionPerformer, commands: CommandRunner, configDirectory: URL,
                ownBundleID: String, frontmostApp: String?) {
        self.transport = transport
        self.performer = performer
        self.commands = commands
        self.configDirectory = configDirectory
        self.ownBundleID = ownBundleID
        self.frontmostApp = frontmostApp
    }

    /// Starts consuming device events.
    public func start() {
        eventTask = Task { [weak self, transport] in
            for await event in transport.events {
                self?.handle(event)
            }
        }
        transport.start()
    }

    /// Blanks all keys and releases the device.
    public func shutdown() {
        cancelDynamicTasks()
        eventTask?.cancel()
        if connected {
            let blank = KeyRenderer.render(.blank).jpeg
            for key in 0 ..< DeckConfig.keyCount { transport.setImage(key: key, jpeg: blank) }
        }
        transport.stop()
    }

    // MARK: - Inputs

    public func configLoaded(_ newConfig: DeckConfig) {
        let unchanged = newConfig == config
        config = newConfig
        brightnessOverride = nil
        problems[.config] = nil
        problems = problems.filter { if case .action = $0.key { false } else { true } }
        // An identical config (e.g. an editor preview) must not restart dynamic keys.
        if unchanged {
            applyBrightness()
            notify()
            return
        }
        if navigation == nil {
            navigation = Navigation(config: newConfig, frontmostApp: frontmostApp, ownBundleID: ownBundleID)
            navigation?.handle(.setAutoSwitch(autoSwitch))
        } else {
            navigation?.handle(.configLoaded(newConfig))
        }
        applyBrightness()
        pageMayHaveChanged(force: true)
    }

    public func configFailed(_ errors: [ConfigError]) {
        problems[.config] = "Config not applied:\n" + errors.map { "• \($0)" }.joined(separator: "\n")
        notify()
    }

    public func appActivated(bundleID: String) {
        if bundleID != ownBundleID { frontmostApp = bundleID }
        navigation?.handle(.appActivated(bundleID: bundleID))
        pageMayHaveChanged()
    }

    public func setAutoSwitch(_ enabled: Bool) {
        autoSwitch = enabled
        navigation?.handle(.setAutoSwitch(enabled))
        notify()
    }

    /// Sets brightness for this session; the config value applies again on the next reload.
    public func setSessionBrightness(_ percent: Int) {
        brightnessOverride = min(100, max(0, percent))
        applyBrightness()
    }

    public var effectiveBrightness: Int {
        brightnessOverride ?? config?.brightness ?? DeckConfig.defaultBrightness
    }

    /// Resends brightness and every key, e.g. after the Mac wakes.
    public func redrawAll() {
        lastSent.removeAll()
        applyBrightness()
        renderAll()
    }

    public func setPermissionProblem(_ message: String?) {
        problems[.permission] = message
        notify()
    }

    // MARK: - Device events

    func handle(_ event: DeviceEvent) {
        switch event {
        case let .connected(info):
            connected = true
            device = info
            problems[.device] = nil
            pressed.removeAll()
            lastSent.removeAll()
            applyBrightness()
            renderAll()
        case .disconnected:
            connected = false
            device = nil
            pressed.removeAll()
            lastSent.removeAll()
            notify()
        case let .openFailed(code):
            problems[.device] = OpenFailure.message(code: code, elgatoRunning: OpenFailure.elgatoAppIsRunning())
            notify()
        case let .key(keyEvent):
            handleKey(keyEvent)
        }
    }

    private func handleKey(_ event: KeyEvent) {
        if let onEditorKeyPress {
            if event.edge == .down { onEditorKeyPress(event.key) }
            return
        }
        guard let page = displayedPage, let action = currentPageKeys[event.key]?.action else { return }
        switch event.edge {
        case .down:
            pressed.insert(event.key)
            render(key: event.key)
            perform(action, page: page, key: event.key)
        case .up:
            guard pressed.remove(event.key) != nil else { return }
            render(key: event.key)
        }
    }

    private func perform(_ action: Action, page: String, key: Int) {
        if case let .page(target) = action {
            navigation?.handle(.pageAction(target))
            pageMayHaveChanged()
            return
        }
        Task { [performer] in
            let result = await performer.perform(action)
            self.actionFinished(result, action: action, page: page, key: key)
        }
    }

    private func actionFinished(_ result: ActionResult, action: Action, page: String, key: Int) {
        let source = Problem.Source.action(page: page, key: key)
        switch result {
        case .succeeded:
            problems[source] = nil
            if case .keys = action { problems[.permission] = nil }
            if case .media = action { problems[.permission] = nil }
        case let .failed(message):
            problems[source] = "Page '\(page)', key \(key): \(message)"
        case .needsAccessibility:
            problems[.permission] = Self.accessibilityMessage
        }
        notify()
    }

    public static let accessibilityMessage = "Keystroke and media keys need Accessibility permission."

    // MARK: - Pages and rendering

    /// The editor's page while it is set and exists, otherwise navigation's page.
    private var displayedPage: String? {
        if let editorPage, config?.pages[editorPage] != nil { return editorPage }
        return navigation?.currentPage
    }

    private var currentPageKeys: [Int: KeyDefinition] {
        guard let page = displayedPage else { return [:] }
        return config?.pages[page]?.keys ?? [:]
    }

    private var shownPage: String?

    private func pageMayHaveChanged(force: Bool = false) {
        let page = displayedPage
        if page != shownPage || force {
            shownPage = page
            restartDynamicTasks()
            pressed.removeAll()
            renderAll()
        } else {
            notify()
        }
    }

    private func renderAll() {
        for key in 0 ..< DeckConfig.keyCount { render(key: key, notifyAfter: false) }
        notify()
    }

    private func render(key: Int, notifyAfter: Bool = true) {
        let definition = currentPageKeys[key]
        let output = dynamicOutputs[key]
        var appearance = KeyAppearance(
            background: output?.background ?? definition?.background ?? .black,
            icon: output?.icon ?? definition?.icon,
            label: output?.label ?? definition?.label,
            pressed: pressed.contains(key) && definition?.action != nil,
            error: dynamicFailed.contains(key)
        )
        if definition == nil { appearance = .blank }
        let rendered = KeyRenderer.render(appearance)
        problems[.icon(key: key)] = rendered.problems.isEmpty ? nil : "Key \(key): " + rendered.problems.joined(separator: "; ")
        if connected, lastSent[key] != rendered.jpeg {
            transport.setImage(key: key, jpeg: rendered.jpeg)
            lastSent[key] = rendered.jpeg
        }
        if notifyAfter { notify() }
    }

    private func applyBrightness() {
        guard connected else { return }
        transport.setBrightness(effectiveBrightness)
    }

    // MARK: - Dynamic keys

    private func cancelDynamicTasks() {
        dynamicTasks.values.forEach { $0.cancel() }
        dynamicTasks.removeAll()
    }

    private func restartDynamicTasks() {
        cancelDynamicTasks()
        dynamicOutputs.removeAll()
        dynamicFailed.removeAll()
        problems = problems.filter { if case .dynamic = $0.key { false } else { true } }
        for (key, definition) in currentPageKeys {
            guard let dynamic = definition.dynamic else { continue }
            dynamicTasks[key] = Task { [weak self, commands] in
                while !Task.isCancelled {
                    let result = await commands.run(dynamic.run, timeout: Self.dynamicTimeout)
                    // Stop when cancelled or when the engine is gone.
                    guard !Task.isCancelled, let self else { return }
                    self.dynamicFinished(key: key, command: dynamic.run, result: result)
                    try? await Task.sleep(for: .seconds(dynamic.every))
                }
            }
        }
    }

    private func dynamicFinished(key: Int, command: String, result: CommandResult) {
        // A failed run keeps the last good output, so the key keeps its whole appearance.
        if !result.succeeded {
            dynamicFailed.insert(key)
            let reason = result.timedOut ? "timed out after \(Int(Self.dynamicTimeout)) s" : "exited with status \(result.exitCode)"
            problems[.dynamic(key: key)] = "Key \(key) dynamic command \(reason): \(command)"
        } else {
            switch DynamicOutput.parse(result.stdout, configDirectory: configDirectory) {
            case let .success(output):
                dynamicOutputs[key] = output
                dynamicFailed.remove(key)
                problems[.dynamic(key: key)] = nil
            case let .failure(rejected):
                dynamicFailed.insert(key)
                problems[.dynamic(key: key)] = "Key \(key) dynamic output: \(rejected.reason): \(command)"
            }
        }
        render(key: key)
    }

    // MARK: - Status

    private func notify() {
        let newStatus = Status(
            connected: connected,
            device: device,
            page: displayedPage,
            autoSwitch: autoSwitch,
            problems: problems.sorted { $0.key < $1.key }.map { Problem(source: $0.key, message: $0.value) }
        )
        guard newStatus != status else { return }
        status = newStatus
        onStatusChange?(newStatus)
    }
}
