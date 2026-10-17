import DeckConfig
import Testing
@testable import DeckEngine

let own = "de.wehrens.streamdeck"
let xcode = "com.apple.dt.Xcode"
let safari = "com.apple.Safari"
let mail = "com.apple.mail"

func makeConfig(pages: [String] = ["home", "media", "xcode", "browser"], appPages: [String: String] = [xcode: "xcode", safari: "browser"]) -> DeckConfig {
    DeckConfig(defaultPage: "home", pages: Dictionary(uniqueKeysWithValues: pages.map { ($0, Page(keys: [:])) }), appPages: appPages)
}

// MARK: Initial page

@Test func startWithMappedAppInFront() {
    #expect(Navigation(config: makeConfig(), frontmostApp: xcode, ownBundleID: own).currentPage == "xcode")
}

@Test func startWithUnmappedAppInFront() {
    #expect(Navigation(config: makeConfig(), frontmostApp: mail, ownBundleID: own).currentPage == "home")
}

@Test func startWithOwnAppInFront() {
    #expect(Navigation(config: makeConfig(), frontmostApp: own, ownBundleID: own).currentPage == "home")
}

// MARK: Manual navigation history

@Test func forwardAndBack() {
    var nav = Navigation(config: makeConfig(), frontmostApp: mail, ownBundleID: own)
    nav.handle(.pageAction(.named("media")))
    #expect(nav.currentPage == "media")
    nav.handle(.pageAction(.back))
    #expect(nav.currentPage == "home")
}

@Test func backWithEmptyHistory() {
    var nav = Navigation(config: makeConfig(), frontmostApp: mail, ownBundleID: own)
    nav.handle(.pageAction(.back))
    #expect(nav.currentPage == "home")
}

@Test func samePageActionDoesNothing() {
    var nav = Navigation(config: makeConfig(), frontmostApp: mail, ownBundleID: own)
    nav.handle(.pageAction(.named("home")))
    #expect(nav.history.isEmpty)
}

@Test func multiLevelBack() {
    var nav = Navigation(config: makeConfig(), frontmostApp: mail, ownBundleID: own)
    nav.handle(.pageAction(.named("media")))
    nav.handle(.pageAction(.named("browser")))
    nav.handle(.pageAction(.back))
    nav.handle(.pageAction(.back))
    #expect(nav.currentPage == "home")
    #expect(nav.history.isEmpty)
}

// MARK: Automatic switching

@Test func mappedAppActivated() {
    var nav = Navigation(config: makeConfig(), frontmostApp: mail, ownBundleID: own)
    nav.handle(.pageAction(.named("media")))
    nav.handle(.appActivated(bundleID: safari))
    #expect(nav.currentPage == "browser")
    #expect(nav.history.isEmpty)
}

@Test func unmappedAppActivated() {
    var nav = Navigation(config: makeConfig(), frontmostApp: safari, ownBundleID: own)
    nav.handle(.appActivated(bundleID: mail))
    #expect(nav.currentPage == "home")
}

@Test func appSwitchAfterManualNavigation() {
    var nav = Navigation(config: makeConfig(), frontmostApp: xcode, ownBundleID: own)
    nav.handle(.pageAction(.named("media")))
    nav.handle(.appActivated(bundleID: safari))
    #expect(nav.currentPage == "browser")
}

@Test func backDoesNotUndoAppSwitch() {
    var nav = Navigation(config: makeConfig(), frontmostApp: mail, ownBundleID: own)
    nav.handle(.appActivated(bundleID: xcode))
    nav.handle(.pageAction(.back))
    #expect(nav.currentPage == "xcode")
}

// MARK: Manual navigation within an app

@Test func manualPageStaysWhileAppUnchanged() {
    var nav = Navigation(config: makeConfig(), frontmostApp: xcode, ownBundleID: own)
    nav.handle(.pageAction(.named("media")))
    #expect(nav.currentPage == "media")
}

// MARK: Own app ignored

@Test func openingOwnMenuKeepsPage() {
    var nav = Navigation(config: makeConfig(), frontmostApp: xcode, ownBundleID: own)
    nav.handle(.pageAction(.named("media")))
    nav.handle(.appActivated(bundleID: own))
    #expect(nav.currentPage == "media")
    #expect(nav.history == ["xcode"])
}

// MARK: Disable automatic switching

@Test func switchingPaused() {
    var nav = Navigation(config: makeConfig(), frontmostApp: mail, ownBundleID: own)
    nav.handle(.setAutoSwitch(false))
    nav.handle(.appActivated(bundleID: safari))
    #expect(nav.currentPage == "home")
    nav.handle(.setAutoSwitch(true))
    #expect(nav.currentPage == "home")
    nav.handle(.appActivated(bundleID: xcode))
    #expect(nav.currentPage == "xcode")
}

// MARK: Config reload

@Test func reloadKeepsExistingPage() {
    var nav = Navigation(config: makeConfig(), frontmostApp: mail, ownBundleID: own)
    nav.handle(.pageAction(.named("media")))
    nav.handle(.configLoaded(makeConfig()))
    #expect(nav.currentPage == "media")
    #expect(nav.history == ["home"])
}

@Test func reloadRemovingCurrentPage() {
    var nav = Navigation(config: makeConfig(), frontmostApp: mail, ownBundleID: own)
    nav.handle(.pageAction(.named("media")))
    nav.handle(.configLoaded(makeConfig(pages: ["home", "xcode", "browser"])))
    #expect(nav.currentPage == "home")
    #expect(nav.history.isEmpty)
}

@Test func reloadRemovingCurrentPageUsesFrontmostAppMapping() {
    var nav = Navigation(config: makeConfig(), frontmostApp: xcode, ownBundleID: own)
    nav.handle(.pageAction(.named("media")))
    nav.handle(.configLoaded(makeConfig(pages: ["home", "xcode", "browser"])))
    #expect(nav.currentPage == "xcode")
}

@Test func reloadDropsRemovedPagesFromHistory() {
    var nav = Navigation(config: makeConfig(), frontmostApp: mail, ownBundleID: own)
    nav.handle(.pageAction(.named("media")))
    nav.handle(.pageAction(.named("browser")))
    nav.handle(.configLoaded(makeConfig(pages: ["home", "browser", "xcode"])))
    #expect(nav.history == ["home"])
}

@Test func pageActionToUnknownPageIgnored() {
    var nav = Navigation(config: makeConfig(), frontmostApp: mail, ownBundleID: own)
    nav.handle(.pageAction(.named("gone")))
    #expect(nav.currentPage == "home")
}
