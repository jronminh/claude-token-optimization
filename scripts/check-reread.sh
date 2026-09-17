#!/usr/bin/env bash
# PreToolUse hook (Read): warn (don't block) if this file has already been
# Read earlier in the same session. Evidence (session-stats.md, 2026-09-16,
# real transcript analysis) shows this happens in practice, up to 16x in a
# single session, despite the "avoid re-reading" rule already in CLAUDE.md -
# this catches it live instead of only in after-the-fact analysis.
set -euo pipefail

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')

[ -n "$SESSION_ID" ] && [ -n "$FILE_PATH" ] || exit 0

LOG_DIR="$HOME/.claude/session-env/$SESSION_ID"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/read-files-log"

PRIOR=$(grep -Fxc "$FILE_PATH" "$LOG_FILE" 2>/dev/null || true)
PRIOR="${PRIOR:-0}"

# Record this attempt for next time - after counting PRIOR, so the message
# below reports how many times it was read BEFORE this call.
echo "$FILE_PATH" >> "$LOG_FILE"

[ "$PRIOR" -ge 1 ] || exit 0

N=$(( PRIOR + 1 ))
CTX="'$FILE_PATH' has already been Read $PRIOR time(s) earlier in this session (this will be read #$N). Prefer grep -n -A<N> -B<N> <anchor> to jump straight to the relevant section instead of re-reading the whole file, unless you're genuinely unsure of the file's current state (many turns since you last saw it, or it may have changed elsewhere)."

jq -n --arg ctx "$CTX" --arg msg "File re-read #$N this session - prefer grep over reading it again." \
  '{systemMessage: $msg, hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $ctx}}'
