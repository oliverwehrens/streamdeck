import DeckConfig

/// Which page is shown. A pure state machine; see the page-navigation spec.
public struct Navigation: Equatable, Sendable {
    public enum Event: Equatable, Sendable {
        case pageAction(PageTarget)
        case appActivated(bundleID: String)
        case configLoaded(DeckConfig)
        case setAutoSwitch(Bool)
    }

    public private(set) var currentPage: String
    public private(set) var history: [String] = []
    public private(set) var autoSwitch = true
    private var config: DeckConfig
    private var frontmostApp: String?
    private let ownBundleID: String

    public init(config: DeckConfig, frontmostApp: String?, ownBundleID: String) {
        self.config = config
        self.ownBundleID = ownBundleID
        self.frontmostApp = frontmostApp == ownBundleID ? nil : frontmostApp
        currentPage = config.defaultPage
        currentPage = pageForFrontmostApp()
    }

    public mutating func handle(_ event: Event) {
        switch event {
        case let .pageAction(.named(name)):
            guard name != currentPage, config.pages[name] != nil else { return }
            history.append(currentPage)
            currentPage = name

        case .pageAction(.back):
            guard let previous = history.popLast() else { return }
            currentPage = previous

        case let .appActivated(bundleID):
            guard bundleID != ownBundleID else { return }
            frontmostApp = bundleID
            guard autoSwitch else { return }
            currentPage = pageForFrontmostApp()
            history.removeAll()

        case let .configLoaded(newConfig):
            config = newConfig
            history.removeAll { newConfig.pages[$0] == nil }
            if newConfig.pages[currentPage] == nil {
                currentPage = autoSwitch ? pageForFrontmostApp() : newConfig.defaultPage
                history.removeAll()
            }

        case let .setAutoSwitch(enabled):
            autoSwitch = enabled
        }
    }

    private func pageForFrontmostApp() -> String {
        frontmostApp.flatMap { config.appPages[$0] } ?? config.defaultPage
    }
}
