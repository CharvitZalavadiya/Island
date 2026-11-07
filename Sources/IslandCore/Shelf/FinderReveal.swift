import Foundation

/// Where "Show in Finder" should take the user.
public enum FinderReveal {
    public enum Target: Equatable {
        /// Open a Finder window with this file or folder selected.
        case reveal(URL)
        /// Open this folder.
        case openFolder(URL)
    }

    /// The file itself if it is still there; otherwise the folder it was in; otherwise the home folder.
    /// `resolved` is where the shelf's bookmark found the file now, `lastKnownPath` where it was last seen.
    public static func target(
        resolved: URL?, lastKnownPath: String?, fileExists: (String) -> Bool, home: URL
    ) -> Target {
        if let resolved, fileExists(resolved.path) { return .reveal(resolved) }
        let gone = resolved?.path ?? lastKnownPath
        if let gone {
            let folder = (gone as NSString).deletingLastPathComponent
            if !folder.isEmpty, fileExists(folder) { return .openFolder(URL(fileURLWithPath: folder)) }
        }
        return .openFolder(home)
    }
}
