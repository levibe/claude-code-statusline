#!/usr/bin/env bats

load 'helpers'

# ─── Subagent tokens ───

@test "subagent: tokens added to total" {
  local transcript_dir
  transcript_dir=$(mktemp -d)/transcript
  mkdir -p "${transcript_dir}/subagents"
  # Create a minimal subagent JSONL with one assistant message
  printf '{"type":"assistant","message":{"id":"msg_1","usage":{"input_tokens":100,"output_tokens":50}}}\n' \
    > "${transcript_dir}/subagents/agent-1.jsonl"
  local tp="${transcript_dir}.jsonl"
  touch "$tp"
  # 8000 base tokens + 150 subagent = 8150, in 60s = 8150 tpm
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "$tp"
  [[ "$(plain)" == *"8.1k tpm"* ]]
  rm -rf "$(dirname "$transcript_dir")"
}

@test "subagent: cache hit on unchanged files" {
  local transcript_dir
  transcript_dir=$(mktemp -d)/transcript
  mkdir -p "${transcript_dir}/subagents"
  printf '{"type":"assistant","message":{"id":"msg_1","usage":{"input_tokens":100,"output_tokens":50}}}\n' \
    > "${transcript_dir}/subagents/agent-1.jsonl"
  local tp="${transcript_dir}.jsonl"
  touch "$tp"
  # First call: parses and caches
  invoke "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "$tp"
  local cache="/tmp/claude-code-statusline-subagent-${TEST_SID}"
  [ -f "$cache" ]
  local first_fp
  first_fp=$(head -1 "$cache")
  # Second call: same files, should use cache (fingerprint unchanged)
  invoke "Opus 4.6" 25 "$TEST_SID" 120000 6000 4000 "" "$tp"
  [ "$(head -1 "$cache")" = "$first_fp" ]
  [ "$(tail -1 "$cache")" = "150" ]
  rm -rf "$(dirname "$transcript_dir")"
}
