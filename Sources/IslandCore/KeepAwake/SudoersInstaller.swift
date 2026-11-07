import Foundation

public enum SudoersError: Error, Equatable {
    /// The account name could not safely be used in the rule.
    case invalidUser
    /// The person pressed Cancel in the password dialog.
    case cancelled
    case failed(String)
}

/// Sets up (and removes) the one permission keep awake needs: letting the current user run exactly two commands,
/// `pmset -a disablesleep 0` and `pmset -a disablesleep 1`, as root without a password.
///
/// It does this from inside the app, so it works on any Mac with no script, repository or username baked in. The rule
/// is written by a shell command that runs with administrator rights, which macOS grants through its own password
/// dialog (`osascript … with administrator privileges`). The command first writes to a name sudo ignores, has `visudo`
/// check the result, and only then moves it into place, so a bad rule can never break `sudo` itself.
public enum SudoersInstaller {
    public static let directory = "/etc/sudoers.d"

    /// Account names go into a command that runs as root, so only plain letters, digits and `_ . -` are accepted
    /// (and not a leading `-` or `.`), up to 32 bytes.
    public static func isValidUserName(_ name: String) -> Bool {
        guard !name.isEmpty, name.utf8.count <= 32, let first = name.unicodeScalars.first else { return false }
        func isAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
            (48...57).contains(scalar.value) || (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
        }
        guard isAlphanumeric(first) || first == "_" else { return false }
        return name.unicodeScalars.allSatisfy { isAlphanumeric($0) || $0 == "_" || $0 == "." || $0 == "-" }
    }

    public static func rule(for user: String) -> String {
        "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"
    }

    /// One file per user. sudo ignores files whose names contain a dot, so dots in the account name become underscores.
    public static func fileName(for user: String) -> String {
        "island-" + user.replacingOccurrences(of: ".", with: "_")
    }

    /// Shell text that installs the rule, meant to run as root. `nil` if the account name is not safe to use.
    public static func installCommand(user: String, directory: String = directory) -> String? {
        guard isValidUserName(user) else { return nil }
        let file = shellQuote(directory + "/" + fileName(for: user))
        let line = shellQuote(rule(for: user))
        return [
            "set -e",
            "FILE=\(file)",
            #"TMP="$FILE.tmp""#,
            #"trap 'rm -f "$TMP"' EXIT"#,
            "printf '%s\\n' \(line) > \"$TMP\"",
            #"chmod 440 "$TMP""#,
            #"[ "$(id -u)" -ne 0 ] || chown root:wheel "$TMP""#,
            #"/usr/sbin/visudo -cf "$TMP" > /dev/null"#,
            #"mv "$TMP" "$FILE""#,
        ].joined(separator: "; ")
    }

    /// Shell text that removes this user's rule (and nothing else).
    public static func removeCommand(user: String, directory: String = directory) -> String? {
        guard isValidUserName(user) else { return nil }
        return "rm -f " + shellQuote(directory + "/" + fileName(for: user))
    }

    /// AppleScript that runs `command` as administrator, which makes macOS show its password dialog.
    public static func appleScript(running command: String, prompt: String) -> String {
        func escaped(_ text: String) -> String {
            text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        }
        return "do shell script \"\(escaped(command))\" with administrator privileges with prompt \"\(escaped(prompt))\""
    }

    public static func install(user: String, runner: CommandRunner) throws {
        guard let command = installCommand(user: user) else { throw SudoersError.invalidUser }
        try run(
            command,
            prompt: "Island needs your password once, so it can switch your Mac's sleep setting on and off. It will be allowed to do that and nothing else.",
            runner: runner)
    }

    public static func remove(user: String, runner: CommandRunner) throws {
        guard let command = removeCommand(user: user) else { throw SudoersError.invalidUser }
        try run(
            command,
            prompt: "Island will remove the permission it was given to change your Mac's sleep setting.",
            runner: runner)
    }

    private static func run(_ command: String, prompt: String, runner: CommandRunner) throws {
        let result: CommandResult
        do {
            result = try runner.run("/usr/bin/osascript", ["-e", appleScript(running: command, prompt: prompt)])
        } catch {
            throw SudoersError.failed(error.localizedDescription)
        }
        guard result.status == 0 else {
            let text = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.contains("User canceled") || text.contains("(-128)") { throw SudoersError.cancelled }
            throw SudoersError.failed(text.isEmpty ? "The permission could not be changed." : text)
        }
    }

    private static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
