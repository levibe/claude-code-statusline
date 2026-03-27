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
}

cleanup_state() {
  local sid="$1"
  rm -f "/tmp/claude-code-statusline-model-${sid}"
  rm -f "/tmp/claude-code-statusline-tpm-${sid}"
  rm -f "/tmp/claude-code-statusline-subagent-${sid}"
}

# Build JSON input using jq for proper escaping
# Args: model used session_id duration_ms total_in total_out cwd transcript_path
make_json() {
  local model="${1:-Opus 4.6}"
  local used="${2:-25}"
  local session_id="${3:-$TEST_SID}"
  local duration_ms="${4:-60000}"
  local total_in="${5:-5000}"
  local total_out="${6:-3000}"
  local cwd="${7:-}"
  local transcript_path="${8:-}"
  jq -n \
    --arg cwd "$cwd" \
    --arg sid "$session_id" \
    --arg tp "$transcript_path" \
    --argjson used "$used" \
    --arg model "$model" \
    --argjson tin "$total_in" \
    --argjson tout "$total_out" \
    --argjson dur "$duration_ms" \
    '{
      cwd: $cwd,
      session_id: $sid,
      transcript_path: $tp,
      context_window: { used_percentage: $used, total_input_tokens: $tin, total_output_tokens: $tout },
      model: { display_name: $model },
      cost: { total_duration_ms: $dur }
    }'
}

# Run the script, capturing output for assertions via `run`
run_sl() {
  make_json "$@" | sh "$SCRIPT"
}

# Set up cache state without capturing output
invoke() {
  make_json "$@" | sh "$SCRIPT" > /dev/null
}

# Strip ANSI escape codes from $output
plain() {
  printf '%s' "$output" | sed $'s/\033\[[0-9;]*m//g'
}

# Read model cache file for a session
cached_model() {
  head -1 "/tmp/claude-code-statusline-model-${1:-$TEST_SID}"
}

cached_duration() {
  tail -1 "/tmp/claude-code-statusline-model-${1:-$TEST_SID}"
}
