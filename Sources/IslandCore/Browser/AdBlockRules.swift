import CryptoKit
import Foundation

/// The ad blocker's rules, in Safari's content-blocker format. WebKit compiles them itself into a compact form that runs
/// inside the network layer, so blocking costs almost no memory or time per page (unlike a script that inspects every request).
///
/// Two kinds of rule: block a request to a known ad network (or to a YouTube address that only serves ads), and hide the
/// boxes where ads sit. YouTube's video ads come from the same servers as the video, so they are handled by
/// `YouTubeAdScript`, not here.
public enum AdBlockRules {
    /// Ad networks and ad exchanges: nothing a person wants is ever loaded from these. Trackers that are not ad networks
    /// are left out on purpose, to keep sites from breaking.
    public static let adDomains: [String] = [
        "doubleclick.net", "googlesyndication.com", "googleadservices.com", "adservice.google.com", "2mdn.net",
        "adnxs.com", "adsrvr.org", "advertising.com", "amazon-adsystem.com", "criteo.com", "criteo.net", "outbrain.com",
        "taboola.com", "openx.net", "pubmatic.com", "rubiconproject.com", "casalemedia.com", "smartadserver.com",
        "adform.net", "yieldmo.com", "teads.tv", "moatads.com", "33across.com", "sharethrough.com", "triplelift.com",
        "media.net", "bidswitch.net", "lijit.com", "sovrn.com", "gumgum.com", "mathtag.com", "adroll.com", "revcontent.com",
        "mgid.com", "zedo.com", "popads.net", "propellerads.com", "exoclick.com", "adcolony.com", "applovin.com",
        "unityads.unity3d.com", "ads.yahoo.com", "adtechus.com", "adsafeprotected.com", "serving-sys.com", "flashtalking.com",
        "contextweb.com", "spotxchange.com", "springserve.com", "tremorhub.com", "videoamp.com", "adition.com", "adscale.de",
        "inmobi.com", "smaato.net", "mopub.com", "ads.twitter.com", "ads.linkedin.com", "ads-twitter.com", "adhigh.net",
        "yandexadexchange.net", "an.yandex.ru", "ad.mail.ru", "adriver.ru", "buysellads.com", "carbonads.net", "adbrite.com",
        "pagead2.googlesyndication.com", "tpc.googlesyndication.com", "ads.pubmatic.com", "securepubads.g.doubleclick.net",
    ]

    /// Addresses on YouTube that only serve or count ads.
    public static let youtubePaths: [String] = ["/pagead/", "/api/stats/ads", "/ptracking", "/get_midroll_info"]

    /// Boxes where ads sit, on any site. Kept to what is clearly an ad, because a loose selector hides real content.
    public static let hiddenSelectors: [String] = [
        "ins.adsbygoogle", ".adsbygoogle", "[id^=\"google_ads_iframe\"]", "[id^=\"google_ads_frame\"]", "[id^=\"div-gpt-ad\"]",
        "[data-google-query-id]", "[data-ad-slot]", "[data-ad-client]", "iframe[src*=\"doubleclick.net\"]",
        "iframe[src*=\"googlesyndication.com\"]", "iframe[src*=\"googleads.g.doubleclick.net\"]", "a[href*=\"://ad.doubleclick.net/\"]",
        "a[href*=\"://adclick.g.doubleclick.net/\"]", "a[href*=\"://www.googleadservices.com/\"]", ".taboola-widget", "[id^=\"taboola-\"]",
        "[id^=\"outbrain\"]", ".OUTBRAIN", ".ob-widget", "#ad-banner", "#top-ad", ".top-ad-banner", ".sponsored-ad",
    ]

    // MARK: The list

    /// A filter for requests to a site and everything under it: `^[^:]+://+([^:/]+\.)?site\.com[:/]` (WebKit's rule syntax has
    /// no alternation, so each site is a rule of its own).
    static func domainFilter(_ domain: String) -> String {
        "^[^:]+://+([^:/]+\\.)?" + domain.replacingOccurrences(of: ".", with: "\\.") + "[:/]"
    }

    static func youtubePathFilter(_ path: String) -> String {
        "^[^:]+://+([^:/]+\\.)?youtube\\.com" + path
    }

    /// The rules. `extraBlockedFilters` are more request filters to block (used by tests, to block something on a local site).
    public static func rules(extraBlockedFilters: [String] = []) -> [[String: Any]] {
        var rules: [[String: Any]] = []
        for domain in adDomains {
            rules.append(["trigger": ["url-filter": domainFilter(domain)], "action": ["type": "block"]])
        }
        for path in youtubePaths {
            rules.append(["trigger": ["url-filter": youtubePathFilter(path)], "action": ["type": "block"]])
        }
        for filter in extraBlockedFilters {
            rules.append(["trigger": ["url-filter": filter], "action": ["type": "block"]])
        }
        rules.append([
            "trigger": ["url-filter": ".*"],
            "action": ["type": "css-display-none", "selector": hiddenSelectors.joined(separator: ", ")],
        ])
        return rules
    }

    /// The rules as the JSON text WebKit compiles. Keys are sorted so the same rules always give the same text (and the same identifier).
    public static func json(extraBlockedFilters: [String] = []) -> String {
        let data = try! JSONSerialization.data(withJSONObject: rules(extraBlockedFilters: extraBlockedFilters), options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    /// A name for a compiled list that changes whenever the rules do, so WebKit's saved copy is used until they change.
    public static func identifier(for json: String) -> String {
        let digest = SHA256.hash(data: Data(json.utf8))
        return "island-ads-" + digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
