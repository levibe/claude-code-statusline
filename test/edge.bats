#!/usr/bin/env bats

load 'helpers'

# ─── Bad input ───

@test "bad input: empty JSON object still produces output" {
  run sh -c 'echo "{}" | sh "$1"' _ "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$(plain)" == *"✦ unknown"* ]]
  [[ "$(plain)" == *"░░░░░ 0%"* ]]
}

@test "bad input: non-JSON input produces safe defaults" {
  run sh -c 'echo "not json" | sh "$1"' _ "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$(plain)" == *"✦ unknown"* ]]
  [[ "$(plain)" == *"░░░░░ 0%"* ]]
}

@test "bad input: missing model field shows unknown" {
  local json
  json=$(jq -n '{
    cwd: "",
    session_id: "test",
    transcript_path: "",
    context_window: { used_percentage: 25, total_input_tokens: 0, total_output_tokens: 0 },
    cost: { total_duration_ms: 0 }
  }')
  run sh -c 'printf "%s" "$1" | sh "$2"' _ "$json" "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$(plain)" == *"✦ unknown"* ]]
}
