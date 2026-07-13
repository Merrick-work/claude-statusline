# claude-statusline

Public, minimal status line for Claude Code: `statusline.sh` (usage/context/model/effort,
one line) + `install.sh` (idempotent installer).

- `statusline.sh` reads the statusLine JSON on stdin and only prints one line to stdout.
  No network calls, no side files. Keep it that way; that's the whole point of the tool.
- `install.sh`'s "existing statusLine" refusal is scoped to *foreign* configs: if
  `.statusLine.command` already equals this installer's target path, it's treated as
  a no-op re-run (backed up and rewritten anyway), not a conflict. Preserve this behavior
  or the acceptance test (rerun in a scratch HOME must be idempotent) breaks.
- CI (`.github/workflows/ci.yml`) shellchecks both scripts and runs a smoke test against
  `tests/sample-input.json` / `tests/expected-output.txt`. Update both fixture files
  together if the jq rendering in `statusline.sh` changes.
