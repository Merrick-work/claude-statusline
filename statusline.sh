#!/bin/bash
# Claude Code status line: usage + context + model + effort.
# Configured in ~/.claude/settings.json under statusLine. Test with:
#   echo '{"model":{"display_name":"Sonnet"},"effort":{"level":"high"},"context_window":{"used_percentage":76},"rate_limits":{"five_hour":{"used_percentage":24},"seven_day":{"used_percentage":28}}}' | ./statusline.sh
set -uo pipefail

# Bound how much untrusted stdin we'll ever read; the real payload is a few
# hundred bytes, so 64KB is generous headroom without letting a runaway or
# hostile caller hang/balloon this process.
in=$(head -c 65536)

# the visible line: ◑ 5h% · wk % · context % · model · effort
# The stdin JSON is untrusted: fields may be missing, wrong-typed, out of
# range, or contain spoofing characters, so every field is type-checked,
# range-checked, and sanitized rather than assumed to match the expected shape.
# shellcheck disable=SC2016  # single quotes are intentional: this is a jq program, not shell interpolation
filter='
  def clamppct: if . < 0 then 0 elif . > 100 then 100 else . end;
  def safepct: if type == "number" then (clamppct|floor|tostring) + "%" else "—" end;
  def safectx: if type == "number" then " · context " + (clamppct|floor|tostring) + "%" else "" end;
  def isspoof: . as $c
    | ($c >= 32 and $c != 127 and ($c < 128 or $c > 159))
    and (($c < 8203 or $c > 8207) and ($c < 8234 or $c > 8238) and ($c < 8294 or $c > 8297) and $c != 65279);
  def clean: if type == "string" then
    ([explode[] | select(isspoof)] | implode)
  else null end;

  ((.rate_limits.five_hour.used_percentage)? // null) as $fh
  | ((.rate_limits.seven_day.used_percentage)? // null) as $wk
  | ((.context_window.used_percentage)? // null) as $ctx
  | (((.model.display_name)? // null) | clean) as $model
  | ((((.effort.level)? // (.effort)? // null)) | clean) as $effort
  | "◑ " + ($fh | safepct)
    + " · wk " + ($wk | safepct)
    + ($ctx | safectx)
    + (if ($model // "") != "" then "  │  " + ($model | ascii_downcase) else "" end)
    + (if ($effort // "") != "" then " · " + $effort else "" end)
'

# `head -n 1` guarantees a single line even if stdin held multiple
# concatenated JSON texts (each would otherwise print its own line).
if out=$(printf '%s' "$in" | jq -r "$filter" 2>/dev/null | head -n 1) && [ -n "$out" ]; then
  printf '%s\n' "$out"
else
  printf '%s\n' "◑ —"
fi
