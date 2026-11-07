/// Island keeps its data in single files, and launching starts a clean-up of an earlier crashed keep-awake session.
/// A second copy running at the same time would end the first copy's live session and overwrite its files, so a copy
/// that finds another one already running should quit before touching anything.
public enum SingleInstance {
    /// The process ID of another running copy, if there is one. `processIDs` may include this process.
    public static func otherProcessID(among processIDs: [Int32], current: Int32) -> Int32? {
        processIDs.first { $0 != current }
    }
}
