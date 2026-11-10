import Foundation

/// The little script that finishes an update after Island has quit: it cannot be done by Island itself, which cannot
/// replace the app it is running from. It waits for Island to exit, moves the old app aside, puts the new one in its place
/// (and puts the old one back if that fails), and opens the result.
public enum UpdateScript {
    /// - Parameters:
    ///   - waitSeconds: how long to wait for Island to quit before giving up and leaving everything as it was.
    ///   - openCommand: what opens the app afterwards (`open`, except in tests).
    public static func text(waitSeconds: Int = 30, openCommand: String = "open") -> String {
        let attempts = max(10, waitSeconds * 10)    // tenths of a second; never less than one second
        return """
        #!/bin/bash
        # Finishes an Island update. Arguments: <pid of Island> <installed app> <new app> <backup> [arguments to open Island with]
        PID="$1"; APP="$2"; NEW="$3"; BACKUP="$4"
        shift 4
        log() { echo "$(date '+%H:%M:%S') $*"; }

        log "waiting for Island ($PID) to quit"
        for _ in $(seq 1 \(attempts)); do
            kill -0 "$PID" 2>/dev/null || break
            sleep 0.1
        done
        if kill -0 "$PID" 2>/dev/null; then
            log "Island did not quit: leaving everything as it was"
            rm -rf "$NEW"
            exit 1
        fi

        rm -rf "$BACKUP"
        if ! mv "$APP" "$BACKUP"; then
            log "could not move the old version aside: leaving it in place"
            rm -rf "$NEW"
            exit 1
        fi
        if mv "$NEW" "$APP"; then
            log "the new version is in place"
            rm -rf "$BACKUP"
        else
            log "could not move the new version in: putting the old one back"
            mv "$BACKUP" "$APP"
        fi

        xattr -dr com.apple.quarantine "$APP" 2>/dev/null
        log "opening Island"
        if [ "$#" -gt 0 ]; then
            \(openCommand) -n "$APP" --args "$@"
        else
            \(openCommand) "$APP"
        fi
        """
    }
}
