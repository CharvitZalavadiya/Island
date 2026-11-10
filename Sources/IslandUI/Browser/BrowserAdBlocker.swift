import Foundation
import WebKit
import IslandCore

/// Gets the ad-blocking rules into WebKit and puts them (and the YouTube script) on a page.
///
/// The rules are compiled by WebKit once, saved by WebKit on disk under a name that changes whenever the rules do, and
/// looked up from there on later launches, so starting costs a moment only the very first time.
@MainActor
final class BrowserAdBlocker {
    private let extraBlockedFilters: [String]
    private let hostPattern: String
    private let store: WKContentRuleListStore
    private let cleansUpOldLists: Bool
    private(set) var ruleList: WKContentRuleList?
    /// Why the rules could not be compiled, if they could not (the YouTube script still works without them).
    private(set) var problem: String?

    /// `store` and the two other parameters are for tests: a private store (so tests never touch the real one), more rules,
    /// and a local address standing in for YouTube.
    init(extraBlockedFilters: [String] = [], youtubeHostPattern: String? = nil, store: WKContentRuleListStore? = nil) {
        self.extraBlockedFilters = extraBlockedFilters
        self.hostPattern = youtubeHostPattern ?? YouTubeAdScript.defaultHostPattern
        self.store = store ?? WKContentRuleListStore.default()
        self.cleansUpOldLists = store == nil && extraBlockedFilters.isEmpty
    }

    /// Compiles the rules, or finds the copy WebKit saved.
    func prepare() async {
        guard ruleList == nil else { return }
        let json = AdBlockRules.json(extraBlockedFilters: extraBlockedFilters)
        let identifier = AdBlockRules.identifier(for: json)
        if let saved = try? await store.contentRuleList(forIdentifier: identifier) {
            ruleList = saved
        } else {
            do {
                ruleList = try await store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json)
            } catch {
                problem = error.localizedDescription
            }
        }
        // Lists saved for earlier versions of the rules are no use any more.
        if cleansUpOldLists, let identifiers = await store.availableIdentifiers() {
            for old in identifiers where old.hasPrefix("island-ads-") && old != identifier {
                try? await store.removeContentRuleList(forIdentifier: old)
            }
        }
    }

    /// Puts the rules and the YouTube script on a page's content controller. Safe to do twice: it replaces what it put before.
    func install(on controller: WKUserContentController) {
        uninstall(from: controller)
        if let ruleList { controller.add(ruleList) }
        controller.addUserScript(WKUserScript(source: YouTubeAdScript.source(hostPattern: hostPattern), injectionTime: .atDocumentStart, forMainFrameOnly: false))
    }

    func uninstall(from controller: WKUserContentController) {
        controller.removeAllContentRuleLists()
        controller.removeAllUserScripts()
    }
}
