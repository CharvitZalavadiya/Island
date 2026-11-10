import Foundation

/// What keeps ads off YouTube. Its video ads come from the same servers as the video, so they cannot be told apart by the
/// network; the way that works (the way uBlock Origin does it) is three layers inside the page, all running only on YouTube:
///
/// 1. **Remove the ads from the data.** The player is told about ads by keys in the data YouTube sends it (`adPlacements`,
///    `playerAds`, `adSlots`). They are deleted from the page's first copy of that data, from anything the page parses, and
///    from the answers to YouTube's own requests, before the player sees them. No ad is then scheduled.
/// 2. **Hide ad containers** (banners, promoted videos, the "ad blockers are not allowed" box).
/// 3. **If an ad plays anyway** (YouTube changes its data often), click its Skip button, or mute it and jump to its end, then
///    put the sound and speed back.
///
/// YouTube keeps changing, so this needs upkeep. It does nothing on any other site.
public enum YouTubeAdScript {
    public static let defaultHostPattern = #"(^|\.)youtube(-nocookie)?\.com$"#

    /// Elements to hide on YouTube.
    public static let hiddenSelectors: [String] = [
        "#masthead-ad", "#player-ads", ".video-ads", ".ytp-ad-module", ".ytp-ad-overlay-container", ".ytp-ad-image-overlay",
        ".ytp-ad-text-overlay", "ytd-ad-slot-renderer", "ytd-in-feed-ad-layout-renderer", "ytd-display-ad-renderer",
        "ytd-promoted-sparkles-web-renderer", "ytd-promoted-video-renderer", "ytd-compact-promoted-video-renderer",
        "ytd-banner-promo-renderer", "ytd-statement-banner-renderer", "ytd-action-companion-ad-renderer",
        "ytd-player-legacy-desktop-watch-ads-renderer", "ytd-brand-video-singleton-renderer", "ytd-brand-video-shelf-renderer",
        "ytd-rich-item-renderer:has(ytd-ad-slot-renderer)", "ytd-engagement-panel-section-list-renderer[target-id=\"engagement-panel-ads\"]",
        "ytd-enforcement-message-view-model", "body:has(ytd-enforcement-message-view-model) tp-yt-iron-overlay-backdrop",
    ]

    /// The script, for pages whose host name matches `hostPattern` (a regular expression; tests use a local address).
    public static func source(hostPattern: String = defaultHostPattern) -> String {
        template
            .replacingOccurrences(of: "__HOST__", with: jsString(hostPattern))
            .replacingOccurrences(of: "__CSS__", with: jsString(hiddenSelectors.joined(separator: ",\n") + " { display: none !important; }"))
    }

    /// A string as a JavaScript literal (quotes and backslashes escaped), so nothing in it can break out of the script.
    private static func jsString(_ text: String) -> String {
        let encoded = (try? JSONEncoder().encode([text])).map { String(decoding: $0, as: UTF8.self) } ?? "[\"\"]"
        return String(encoded.dropFirst().dropLast())
    }

    private static let template = #"""
    (function () {
      'use strict';
      var HOST = new RegExp(__HOST__);
      if (!HOST.test(location.hostname)) { return; }
      if (window.__islandAdBlock) { return; }
      try { Object.defineProperty(window, '__islandAdBlock', { value: true }); } catch (e) { window.__islandAdBlock = true; }

      // 1. Take the ads out of the data the player is given.
      var AD_KEYS = ['adPlacements', 'playerAds', 'adSlots', 'adBreakHeartbeatParams'];
      var nativeParse = JSON.parse;

      function prune(value) {
        if (!value || typeof value !== 'object') { return value; }
        try {
          var holders = [value, value.playerResponse];
          for (var h = 0; h < holders.length; h++) {
            var holder = holders[h];
            if (!holder || typeof holder !== 'object') { continue; }
            for (var k = 0; k < AD_KEYS.length; k++) {
              if (AD_KEYS[k] in holder) { delete holder[AD_KEYS[k]]; }
            }
          }
        } catch (e) {}
        return value;
      }

      // The copy of the player data that is written into the page itself.
      var initialPlayerResponse;
      try {
        Object.defineProperty(window, 'ytInitialPlayerResponse', {
          configurable: true, enumerable: true,
          get: function () { return initialPlayerResponse; },
          set: function (value) { initialPlayerResponse = prune(value); }
        });
      } catch (e) {}

      // Anything the page parses.
      JSON.parse = new Proxy(nativeParse, {
        apply: function (target, thisArg, args) { return prune(Reflect.apply(target, thisArg, args)); }
      });

      // The answers to YouTube's own requests for the player and the next video.
      var nativeFetch = window.fetch;
      if (typeof nativeFetch === 'function') {
        window.fetch = new Proxy(nativeFetch, {
          apply: function (target, thisArg, args) {
            var result = Reflect.apply(target, thisArg, args);
            var url = '';
            try { var first = args[0]; url = typeof first === 'string' ? first : ((first && first.url) || ''); } catch (e) {}
            if (url.indexOf('/youtubei/v1/') === -1) { return result; }
            return result.then(function (response) {
              if (!response || !response.ok) { return response; }
              return response.clone().text().then(function (text) {
                if (text.indexOf('"adPlacements"') === -1 && text.indexOf('"playerAds"') === -1 && text.indexOf('"adSlots"') === -1) { return response; }
                try {
                  var data = prune(nativeParse.call(JSON, text));
                  return new Response(JSON.stringify(data), { status: response.status, statusText: response.statusText, headers: response.headers });
                } catch (e) { return response; }
              });
            });
          }
        });
      }

      // 2. Hide the places ads go.
      function addStyle() {
        var style = document.createElement('style');
        style.textContent = __CSS__;
        (document.head || document.documentElement).appendChild(style);
      }
      if (document.documentElement) { addStyle(); } else {
        var waiting = setInterval(function () { if (document.documentElement) { clearInterval(waiting); addStyle(); } }, 10);
      }

      // 3. If an ad still plays, skip it and put the sound and speed back afterwards.
      var saved = null;
      function tick() {
        var player = document.getElementById('movie_player');
        var video = document.querySelector('video.html5-main-video') || document.querySelector('video');
        var showing = !!(player && (player.classList.contains('ad-showing') || player.classList.contains('ad-interrupting')));

        var skip = document.querySelector('.ytp-skip-ad-button, .ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-ad-skip-button-container button');
        if (skip) { try { skip.click(); } catch (e) {} }
        var close = document.querySelector('.ytp-ad-overlay-close-button');
        if (close) { try { close.click(); } catch (e) {} }

        if (showing && video) {
          if (!saved) { saved = { muted: video.muted, rate: video.playbackRate }; }
          video.muted = true;
          try { video.playbackRate = 16; } catch (e) {}
          var length = video.duration;
          if (isFinite(length) && length > 0 && video.currentTime < length - 0.1) { video.currentTime = length; }
        } else if (saved && video) {
          video.muted = saved.muted;
          try { video.playbackRate = saved.rate; } catch (e) {}
          saved = null;
        }

        // The "ad blockers are not allowed" box stops the video behind it: take it away and carry on.
        var notice = document.querySelector('ytd-enforcement-message-view-model');
        if (notice) {
          var dialog = notice.closest('tp-yt-paper-dialog');
          if (dialog) { dialog.remove(); }
          var backdrop = document.querySelector('tp-yt-iron-overlay-backdrop');
          if (backdrop) { backdrop.remove(); }
          if (video && video.paused && !showing) { try { var started = video.play(); if (started && started.catch) { started.catch(function () {}); } } catch (e) {} }
        }
      }
      setInterval(tick, 250);
    })();
    """#
}
