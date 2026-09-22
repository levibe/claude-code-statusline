#!/usr/bin/env bash

SCRIPT="$BATS_TEST_DIRNAME/../statusline.sh"

setup() {
  TEST_SID="bats-$$-${BATS_TEST_NUMBER}"
  cleanup_state "$TEST_SID"
  cleanup_state "${TEST_SID}-a"
  cleanup_state "${TEST_SID}-b"
}

teardown() {
  cleanup_state "$TEST_SID"
  cleanup_state "${TEST_SID}-a"
  cleanup_state "${TEST_SID}-b"
  [ -n "${TEST_GIT_REPO:-}" ] && rm -rf "$TEST_GIT_REPO" || true
  # Worktrees made outside the repo (siblings) aren't removed with it
  [ -n "${TEST_WORKTREE:-}" ] && rm -rf "$TEST_WORKTREE" || true
}

cleanup_state() {
  local sid
  sid=$(printf '%s' "$1" | tr -dc 'a-zA-Z0-9_-')
  rm -f "/tmp/claude-code-statusline-model-${sid}"
  rm -f "/tmp/claude-code-statusline-usage-${sid}"
}

# Create a git repo with one commit at $TEST_GIT_REPO ($1 = branch, default main)
make_git_repo() {
  TEST_GIT_REPO=$(mktemp -d)
  git -C "$TEST_GIT_REPO" init -b "${1:-main}" >/dev/null 2>&1
  git -C "$TEST_GIT_REPO" -c user.name=test -c user.email=test@test commit --allow-empty -m "init" >/dev/null 2>&1
}

# Add a linked worktree, publishing its path as $TEST_WORKTREE
# ($TEST_GIT_REPO/.worktrees/$1); remaining args pass through to
# `git worktree add` (e.g. -b branch, --detach)
make_worktree() {
  local folder="$1"; shift
  make_worktree_at "$TEST_GIT_REPO/.worktrees/$folder" "$@"
}

# Same, at an arbitrary absolute path ($1), for layouts other than .worktrees/
# (Claude Code's .claude/worktrees/, repo-prefixed siblings)
make_worktree_at() {
  TEST_WORKTREE="$1"; shift
  git -C "$TEST_GIT_REPO" worktree add "$@" "$TEST_WORKTREE" >/dev/null 2>&1
}

# Build JSON input using jq for proper escaping
# Args: model used session_id duration_ms total_in total_out cwd transcript_path
#       [rl_5h_pct rl_5h_reset rl_7d_pct rl_7d_reset]
make_json() {
  local model="${1:-Opus 4.6}"
  local used="${2:-25}"
  local session_id="${3:-$TEST_SID}"
  local duration_ms="${4:-60000}"
  local total_in="${5:-5000}"
  local total_out="${6:-3000}"
  local cwd="${7:-}"
  local transcript_path="${8:-}"
  local rl_5h_pct="${9:-}"
  local rl_5h_reset="${10:-}"
  local rl_7d_pct="${11:-}"
  local rl_7d_reset="${12:-}"
  local ctx_size="${13:-}"
  local base
  local ctx_size_args=()
  local ctx_size_filter="."
  if [ -n "$ctx_size" ]; then
    ctx_size_args=(--argjson ctxsz "$ctx_size")
    ctx_size_filter=". | .context_window.context_window_size = \$ctxsz"
  fi
  base=$(jq -n \
    --arg cwd "$cwd" \
    --arg sid "$session_id" \
    --arg tp "$transcript_path" \
    --argjson used "$used" \
    --arg model "$model" \
    --argjson tin "$total_in" \
    --argjson tout "$total_out" \
    --argjson dur "$duration_ms" \
    "${ctx_size_args[@]}" \
    '{
      cwd: $cwd,
      session_id: $sid,
      transcript_path: $tp,
      context_window: { used_percentage: $used, total_input_tokens: $tin, total_output_tokens: $tout },
      model: { display_name: $model },
      cost: { total_duration_ms: $dur }
    } | '"$ctx_size_filter")
  if [ -n "$rl_5h_pct" ] || [ -n "$rl_5h_reset" ] || [ -n "$rl_7d_pct" ] || [ -n "$rl_7d_reset" ]; then
    local rl_args=()
    local rl_filter="."
    if [ -n "$rl_5h_pct" ] || [ -n "$rl_5h_reset" ]; then
      rl_filter="$rl_filter | .rate_limits.five_hour = {}"
      [ -n "$rl_5h_pct" ] && rl_args+=(--argjson rl5p "$rl_5h_pct") && rl_filter="$rl_filter | .rate_limits.five_hour.used_percentage = \$rl5p"
      [ -n "$rl_5h_reset" ] && rl_args+=(--argjson rl5r "$rl_5h_reset") && rl_filter="$rl_filter | .rate_limits.five_hour.resets_at = \$rl5r"
    fi
    if [ -n "$rl_7d_pct" ] || [ -n "$rl_7d_reset" ]; then
      rl_filter="$rl_filter | .rate_limits.seven_day = {}"
      [ -n "$rl_7d_pct" ] && rl_args+=(--argjson rl7p "$rl_7d_pct") && rl_filter="$rl_filter | .rate_limits.seven_day.used_percentage = \$rl7p"
      [ -n "$rl_7d_reset" ] && rl_args+=(--argjson rl7r "$rl_7d_reset") && rl_filter="$rl_filter | .rate_limits.seven_day.resets_at = \$rl7r"
    fi
    echo "$base" | jq "${rl_args[@]}" "$rl_filter"
  else
    echo "$base"
  fi
}

# Run the script, capturing output for assertions via `run`.
# Forces CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=100 so rescaling is an identity — tests
# that pass a raw `used_percentage` see it displayed unchanged. Tests that need
# real rescale behavior should use run_sl_rescaled instead.
run_sl() {
  make_json "$@" | env CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=100 sh "$SCRIPT"
}

# Set up cache state without capturing output
invoke() {
  make_json "$@" | env CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=100 sh "$SCRIPT" > /dev/null
}

# Run the script without the identity-override, for tests that exercise the
# real rescale math. Inherits CLAUDE_AUTOCOMPACT_PCT_OVERRIDE from the caller
# when set (so individual tests can inject their own override value).
run_sl_rescaled() {
  make_json "$@" | sh "$SCRIPT"
}

# This test's transcript. add_message creates it on first use; the script's
# TPM window reads it (and any agent-*.jsonl under <transcript>/subagents/).
transcript_path() {
  printf '%s/%s.jsonl' "$BATS_TEST_TMPDIR" "$TEST_SID"
}

# Append an assistant message to a transcript file (the main one by default).
# Args: age_seconds input cache_creation cache_read output [message_id] [file]
add_message() {
  local age="$1" in="$2" cc="$3" cr="$4" out="$5"
  local id="${6:-msg_${RANDOM}${RANDOM}}"
  local file="${7:-$(transcript_path)}"
  local ts
  ts=$(date -u -v-"${age}S" +%Y-%m-%dT%H:%M:%S.000Z 2>/dev/null \
    || date -u -d "-${age} seconds" +%Y-%m-%dT%H:%M:%S.000Z)
  mkdir -p "$(dirname "$file")"
  printf '{"type":"assistant","timestamp":"%s","message":{"id":"%s","usage":{"input_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s,"output_tokens":%s}}}\n' \
    "$ts" "$id" "$in" "$cc" "$cr" "$out" >> "$file"
}

# Run the script against this test's transcript with a given session age.
# With a 60s session the window equals the session, so tpm == tokens of work in window.
# Args: duration_ms [model] [used]
run_tpm() {
  run_sl "${2:-Opus 4.6}" "${3:-25}" "$TEST_SID" "${1:-60000}" 0 0 "" "$(transcript_path)"
}

# Strip ANSI escape codes from $output
plain() {
  printf '%s' "$output" | sed $'s/\033\[[0-9;]*m//g'
}

# Read model cache file for a session
cached_model() {
  sed -n '1p' "/tmp/claude-code-statusline-model-${1:-$TEST_SID}"
}

cached_ctx_size() {
  sed -n '2p' "/tmp/claude-code-statusline-model-${1:-$TEST_SID}"
}

cached_duration() {
  sed -n '3p' "/tmp/claude-code-statusline-model-${1:-$TEST_SID}"
}

# Expire the first-usage display window for a session
expire_first_usage() {
  printf '%s\n' "0" > "/tmp/claude-code-statusline-usage-${1:-$TEST_SID}"
}
