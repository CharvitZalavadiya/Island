import Foundation

/// One program the system lists as using audio, as read from the system (not yet grouped into apps).
public struct AudioClient: Equatable, Sendable {
    public var processObject: UInt32
    public var pid: Int32
    /// The program's executable path, "" when it could not be read.
    public var path: String
    /// True while it is producing sound right now.
    public var isPlaying: Bool

    public init(processObject: UInt32, pid: Int32, path: String, isPlaying: Bool) {
        self.processObject = processObject
        self.pid = pid
        self.path = path
        self.isPlaying = isPlaying
    }
}

/// An app that can be turned up or down: every audio process inside one `.app`, helpers included.
public struct MixerApp: Equatable, Identifiable, Sendable {
    /// The path of the app (stable while it runs), which also names its volume.
    public var id: String
    public var name: String
    public var processObjects: [UInt32]
    public var isPlaying: Bool

    public init(id: String, name: String, processObjects: [UInt32], isPlaying: Bool) {
        self.id = id
        self.name = name
        self.processObjects = processObjects
        self.isPlaying = isPlaying
    }
}

public enum AudioMixerGrouping {
    /// Groups the audio clients into apps. Only programs inside an `.app` count, so command-line tools and background
    /// services are left out, as are the macOS system pieces under /System/Library (Control Center, Siri and the like)
    /// and Island itself. Sorted by name.
    public static func apps(from clients: [AudioClient], ownPID: Int32) -> [MixerApp] {
        var groups: [String: MixerApp] = [:]
        for client in clients where client.pid != ownPID {
            guard let bundle = appBundlePath(of: client.path) else { continue }
            let name = (bundle as NSString).lastPathComponent.dropLast(4)
            var app = groups[bundle] ?? MixerApp(id: bundle, name: String(name), processObjects: [], isPlaying: false)
            app.processObjects.append(client.processObject)
            app.isPlaying = app.isPlaying || client.isPlaying
            groups[bundle] = app
        }
        return groups.values.sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    }

    /// The outermost `.app` an executable lives in ("/Applications/Brave Browser.app" for one of its helpers), nil when it
    /// is not in an app or is part of macOS itself.
    public static func appBundlePath(of path: String) -> String? {
        guard !path.hasPrefix("/System/Library/") else { return nil }
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard let index = components.firstIndex(where: { $0.hasSuffix(".app") && $0.count > 4 }) else { return nil }
        return "/" + components[...index].joined(separator: "/")
    }

    /// The apps worth showing: the ones making sound now, plus any whose volume was turned down (even while quiet, so a
    /// paused app can be turned back up).
    public static func visible(_ apps: [MixerApp], volumes: [String: Float]) -> [MixerApp] {
        apps.filter { $0.isPlaying || (volumes[$0.id] ?? 1) < Self.fullVolume }
    }

    /// A volume at or above this counts as full: no tap is needed.
    public static let fullVolume: Float = 0.995
}
