#!/bin/bash
# Installs statusline.sh to ~/.local/bin and points ~/.claude/settings.json at it.
# Usage: ./install.sh [--force]
#   --force  overwrite an existing statusLine config that points somewhere else
set -euo pipefail

INSTALL_DIR="$HOME/.local/bin"
INSTALL_PATH="$INSTALL_DIR/claude-statusline.sh"
SETTINGS_DIR="$HOME/.claude"
SETTINGS_FILE="$SETTINGS_DIR/settings.json"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/statusline.sh"

FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    *)
      echo "error: unknown argument '$arg'" >&2
      exit 1
      ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required but not installed. Install it (e.g. 'brew install jq' or 'apt install jq') and re-run." >&2
  exit 1
fi

if [ ! -f "$SRC" ]; then
  echo "error: statusline.sh not found next to install.sh (expected $SRC)" >&2
  exit 1
fi

case "$INSTALL_PATH" in
  *[!A-Za-z0-9._/-]*)
    echo "warning: install path '$INSTALL_PATH' contains characters (e.g. spaces) that may not" >&2
    echo "survive being run as a shell command by Claude Code. Consider a \$HOME without them." >&2
    ;;
esac

mkdir -p "$SETTINGS_DIR"

# Validate settings.json and resolve the clobber-refusal check up front, before
# touching ~/.local/bin, so a bad settings.json aborts cleanly instead of
# leaving a half-installed script behind. A symlinked settings file (dangling
# or not) is refused rather than followed, since writing through it could
# clobber an arbitrary target.
settings_existed=0
if [ -L "$SETTINGS_FILE" ]; then
  echo "error: $SETTINGS_FILE is a symlink; refusing to follow it for safety." >&2
  echo "Remove or replace it with a real file first." >&2
  exit 1
elif [ -f "$SETTINGS_FILE" ]; then
  settings_existed=1

  if ! jq empty "$SETTINGS_FILE" >/dev/null 2>&1; then
    echo "error: $SETTINGS_FILE is not valid JSON, aborting" >&2
    exit 1
  fi

  existing_command=$(jq -r '.statusLine.command // empty' "$SETTINGS_FILE")
  if [ -n "$existing_command" ] && [ "$existing_command" != "$INSTALL_PATH" ] && [ "$FORCE" -ne 1 ]; then
    existing_command_display=$(printf '%s' "$existing_command" | tr -d '\000-\037\177')
    echo "error: $SETTINGS_FILE already has a statusLine pointing at '$existing_command_display'." >&2
    echo "Rerun with --force to overwrite it." >&2
    exit 1
  fi
else
  echo '{}' > "$SETTINGS_FILE"
fi

mkdir -p "$INSTALL_DIR"
rm -f "$INSTALL_PATH"
cp "$SRC" "$INSTALL_PATH"
chmod +x "$INSTALL_PATH"
echo "Installed statusline script to $INSTALL_PATH"

backup=""
if [ "$settings_existed" -eq 1 ]; then
  backup="$SETTINGS_FILE.bak.$(date +%Y%m%d%H%M%S).$$"
  cp "$SETTINGS_FILE" "$backup"
  echo "Backed up existing settings to $backup"
fi

# Write to a temp file in the same directory so the final replace is an
# atomic same-filesystem rename, and clean it up if jq fails partway. mktemp
# creates it safely (no predictable name to race or pre-plant a symlink at).
tmp=$(mktemp "$SETTINGS_DIR/.settings.json.XXXXXX")
trap 'rm -f "$tmp"' EXIT
jq --arg cmd "$INSTALL_PATH" \
  '.statusLine = {type: "command", command: $cmd, refreshInterval: 30}' \
  "$SETTINGS_FILE" > "$tmp"
mv "$tmp" "$SETTINGS_FILE"

echo "Updated $SETTINGS_FILE: statusLine.command = $INSTALL_PATH"
echo
echo "To undo:"
if [ -n "$backup" ]; then
  echo "  cp \"$backup\" \"$SETTINGS_FILE\"   # restore settings.json as it was before"
fi
echo "  tmp=\$(mktemp \"$SETTINGS_DIR/.settings.json.XXXXXX\") && jq 'del(.statusLine)' \"$SETTINGS_FILE\" > \"\$tmp\" && mv \"\$tmp\" \"$SETTINGS_FILE\"   # just remove the statusLine key"
echo "  rm \"$INSTALL_PATH\"   # remove the installed script"
