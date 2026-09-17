#!/usr/bin/env bash
# Single size guard for markdown files, covering two PreToolUse matchers:
#   - Edit|Write on ~/.claude/CLAUDE.md: warn if user-editable content
#     (excluding anything between MANAGED_BLOCK_START/END, if you have a
#     tool-managed section like that - unset both if you don't) exceeds
#     WARN_TOKENS_CLAUDE_MD estimated tokens. This content is injected into
#     EVERY turn of the session, so its threshold is much tighter than a
#     one-off Read.
#   - Read on any other *.md file: warn if its estimated token size crosses
#     WARN_TOKENS/HARD_TOKENS (a one-time read cost, not recurring).
#
# All estimates use chars/3.5 (jq's unicode-aware `length`, not raw bytes) -
# the same ratio find-large-turns.sh uses. Raw byte counts were tried first
# and dropped: UTF-8 encodes non-Latin scripts and heavily-accented text in
# more bytes per character than plain ASCII, which skews a byte-based
# threshold relative to actual token cost purely based on what language a
# doc happens to be written in. Character count doesn't have that skew.
set -euo pipefail

WARN_TOKENS=12500          # generic .md Read: prefer grep-first past this
HARD_TOKENS=25000          # generic .md Read: never read in full past this
WARN_TOKENS_CLAUDE_MD=1000 # CLAUDE.md Edit|Write: injected every turn, tighter cap
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
# Markers for a tool-managed section to exclude from the CLAUDE.md count
# (e.g. content some installer script owns and regenerates). Leave both
# empty ("") if your CLAUDE.md has no such section.
MANAGED_BLOCK_START="<!-- managed:begin -->"
MANAGED_BLOCK_END="<!-- managed:end -->"

# chars -> estimated tokens, matches find-large-turns.sh's `int(chars*2/7)`
est_tokens() { echo $(( $1 * 2 / 7 )); }

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')

[ -n "$FILE_PATH" ] || exit 0
case "$FILE_PATH" in
  *.md) ;;
  *) exit 0 ;;
esac

IS_CLAUDE_MD=false
if [ "$(realpath -m "$FILE_PATH" 2>/dev/null)" = "$(realpath -m "$CLAUDE_MD" 2>/dev/null)" ]; then
  IS_CLAUDE_MD=true
fi

if [ "$IS_CLAUDE_MD" = true ] && [ "$TOOL" != "Read" ]; then
  [ -f "$CLAUDE_MD" ] || exit 0
  if [ -n "$MANAGED_BLOCK_START" ] && [ -n "$MANAGED_BLOCK_END" ]; then
    CONTENT=$(sed "/$MANAGED_BLOCK_START/,/$MANAGED_BLOCK_END/d" "$CLAUDE_MD")
  else
    CONTENT=$(cat "$CLAUDE_MD")
  fi
  CHARS=$(printf '%s' "$CONTENT" | jq -Rs 'length' 2>/dev/null || echo 0)
  TOKENS=$(est_tokens "$CHARS")
  [ "$TOKENS" -gt "$WARN_TOKENS_CLAUDE_MD" ] || exit 0
  CTX="THRESHOLD: CLAUDE.md user-editable content is ~${TOKENS} estimated tokens (chars/3.5, > ${WARN_TOKENS_CLAUDE_MD} - this content is injected every turn). Prefer pruning or merging into an existing bullet over appending a new one."
  jq -n --arg ctx "$CTX" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $ctx}}'
  exit 0
fi

[ -f "$FILE_PATH" ] || exit 0
CHARS=$(jq -Rs 'length' "$FILE_PATH" 2>/dev/null || echo 0)
TOKENS=$(est_tokens "$CHARS")
[ "$TOKENS" -ge "$WARN_TOKENS" ] || exit 0

if [ "$TOKENS" -ge "$HARD_TOKENS" ]; then
  CTX="'$FILE_PATH' is ~${TOKENS} estimated tokens (chars/3.5, >= ${HARD_TOKENS}). Do not read it in full - grep -n first to find the relevant region, then Read with offset/limit for just that part."
else
  CTX="'$FILE_PATH' is ~${TOKENS} estimated tokens (chars/3.5, >= ${WARN_TOKENS}). Prefer grep -n (or rg) first to locate the relevant lines before reading the whole file."
fi

jq -n --arg ctx "$CTX" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $ctx}}'
