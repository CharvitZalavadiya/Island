// Real files of public pull requests of cli/cli (fetched from GitHub's API on 2026-11-15), as the API sent them.
// Generated from the answers themselves, not retyped; the numbers beside each are what GitHub said it counted.

import Foundation

struct RealChangedFile {
    let filename: String
    let status: String
    let additions: Int
    let deletions: Int
    let patch: String
}

let real_modifiedThreeHunks = RealChangedFile(
    filename: ".github/workflows/issue-triage.md", status: "modified", additions: 5, deletions: 5,
    patch: #"""
@@ -2,8 +2,8 @@
 description: |
   Agentic issue-triage for GitHub CLI. On newly opened issues it follows the
   team's shared triage skills (hosted in desktop/gh-cli-and-desktop-shared-workflows)
-  and applies the minimal correct end-state labels (with issue-intents rationale and
-  confidence), plus one short, plain-language comment.
+  and applies the minimal correct end-state labels (with rationale and confidence
+  in reports), plus one short, plain-language comment.
   Separate issue artifacts hold duplicate analysis, label reasoning, reproduction
   logs, and investigation notes. Bug reports include a minimal observed reproduction.
   Confirmed duplicates stop before further investigation. The objective is to drive the
@@ -42,8 +42,8 @@ permissions:
   issues: read
   copilot-requests: write
 
-# GH_AW_RUNTIME_FEATURES enables native issue-intent rationale/confidence at runtime.
-# It is INERT unless a repo admin sets the repository variable to `issue_intents`.
+# Preserve the runtime feature setting. Add-labels disables native issue intents
+# below; its rationale and confidence stay in the triage reports.
 #
 # The schema paths are populated by setup. The export path is the approved
 # final artifact destination, so the agent never needs to resolve runner paths.
@@ -119,7 +119,7 @@ safe-outputs:
     client-id: ${{ secrets.CLI_TRIAGE_APP_CLIENT_ID }}
     private-key: ${{ secrets.CLI_TRIAGE_APP_PRIVATE_KEY }}
   add-labels:
-    issue-intent: true
+    issue-intent: false
     max: 3
     target: ${{ github.event.issue.number || inputs.issue_number }}
     allowed:
"""#)

let real_modifiedFourHunks = RealChangedFile(
    filename: "pkg/cmd/auth/login/login_test.go", status: "modified", additions: 8, deletions: 8,
    patch: #"""
@@ -45,6 +45,7 @@ func Test_NewCmdLogin(t *testing.T) {
 		defaultHost string
 		wants       LoginOptions
 		wantsErr    bool
+		errMsg      string
 	}{
 		{
 			name:  "nontty, with-token",
@@ -70,10 +71,8 @@ func Test_NewCmdLogin(t *testing.T) {
 			stdinTTY: true,
 			stdin:    "def456",
 			cli:      "--with-token",
-			wants: LoginOptions{
-				Hostname: "github.com",
-				Token:    "def456",
-			},
+			wantsErr: true,
+			errMsg:   "`--with-token` must be used noninteractively, for example `gh auth login --with-token < mytoken.txt`\nTo paste a token interactively, run `gh auth login` instead.",
 		},
 		{
 			name:     "nontty, hostname",
@@ -107,10 +106,8 @@ func Test_NewCmdLogin(t *testing.T) {
 			stdinTTY: true,
 			stdin:    "ghi789",
 			cli:      "--with-token --hostname brad.vickers",
-			wants: LoginOptions{
-				Hostname: "brad.vickers",
-				Token:    "ghi789",
-			},
+			wantsErr: true,
+			errMsg:   "`--with-token` must be used noninteractively, for example `gh auth login --with-token < mytoken.txt`\nTo paste a token interactively, run `gh auth login` instead.",
 		},
 		{
 			name:     "tty, hostname",
@@ -317,6 +314,9 @@ func Test_NewCmdLogin(t *testing.T) {
 			_, err = cmd.ExecuteC()
 			if tt.wantsErr {
 				assert.Error(t, err)
+				if tt.errMsg != "" {
+					assert.EqualError(t, err, tt.errMsg)
+				}
 				return
 			}
 			assert.NoError(t, err)
"""#)

let real_addedFile = RealChangedFile(
    filename: "pr_body.md", status: "added", additions: 25, deletions: 0,
    patch: #"""
@@ -0,0 +1,25 @@
+Closes #11247
+
+This adds `--json` and `--jq` flags to `gh pr create`, matching the pattern used by other `gh pr` subcommands like `pr view`, `pr list`, and `pr status`.
+
+## Summary of changes
+
+- Added `Exporter cmdutil.Exporter` field to `CreateOptions`
+- Registered `--json` and `--jq` flags via `cmdutil.AddJSONFlags` using `api.PullRequestFields`
+- Added flag validation: `--json`/`--jq` are mutually exclusive with `--web` and `--dry-run`
+- Modified `submitPR` to return `(*api.PullRequest, error)` instead of just `error`
+- Added `finishSubmit` helper that re-fetches the created PR with the requested fields when an Exporter is configured, then writes JSON output
+- Updated all three call sites of `submitPR` to use `finishSubmit`
+- When `--json`/`--jq` is used, the plain URL output is suppressed so only JSON goes to stdout
+
+## Example usage
+
+```bash
+gh pr create --title "Bug fix" --body "Fixes the bug" --json url,number,title
+gh pr create --json url,number --jq '.number'
+```
+
+This allows scripting workflows like:
+```bash
+PR_NUMBER=$(gh pr create --title "..." --body "..." --json number --jq '.number')
+```
"""#)
