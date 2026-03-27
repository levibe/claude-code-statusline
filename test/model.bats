#!/usr/bin/env bats

load 'helpers'

# ─── Model validation ───

@test "model: accepts 'Opus 4.6'" {
  run run_sl "Opus 4.6"
  [ "$status" -eq 0 ]
  [[ "$(plain)" == *"✦ Opus 4.6"* ]]
}

@test "model: accepts 'Sonnet 4.6'" {
  run run_sl "Sonnet 4.6"
  [ "$status" -eq 0 ]
  [[ "$(plain)" == *"✦ Sonnet 4.6"* ]]
}

@test "model: accepts 'Haiku 4.5'" {
  run run_sl "Haiku 4.5"
  [ "$status" -eq 0 ]
  [[ "$(plain)" == *"✦ Haiku 4.5"* ]]
}

@test "model: strips parenthetical suffix 'Opus 4.6 (1M context)'" {
  run run_sl "Opus 4.6 (1M context)"
  [ "$status" -eq 0 ]
  [[ "$(plain)" == *"✦ Opus 4.6"* ]]
}

@test "model: rejects garbled 'Op.6'" {
  run run_sl "Op.6"
  [ "$status" -eq 0 ]
  [[ "$(plain)" == *"✦ unknown"* ]]
}

@test "model: rejects truncated 'Son'" {
  run run_sl "Son"
  [ "$status" -eq 0 ]
  [[ "$(plain)" == *"✦ unknown"* ]]
}

@test "model: rejects lowercase 'opus 4.6'" {
  run run_sl "opus 4.6"
  [ "$status" -eq 0 ]
  [[ "$(plain)" == *"✦ unknown"* ]]
}

@test "model: rejects trailing text 'Opus 4.6 extra'" {
  run run_sl "Opus 4.6 extra"
  [ "$status" -eq 0 ]
  [[ "$(plain)" == *"✦ unknown"* ]]
}

@test "model: rejects multi-word name 'Sonnet Max 4.6'" {
  run run_sl "Sonnet Max 4.6"
  [ "$status" -eq 0 ]
  [[ "$(plain)" == *"✦ unknown"* ]]
}

@test "model: passes through 'unknown' as-is" {
  run run_sl "unknown"
  [ "$status" -eq 0 ]
  [[ "$(plain)" == *"✦ unknown"* ]]
}

# ─── Model cache ───

@test "cache: first invocation initializes cache file" {
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000
  [ -f "/tmp/claude-code-statusline-model-${TEST_SID}" ]
  [ "$(cached_model)" = "Opus 4.6" ]
  [ "$(cached_duration)" = "60000" ]
}

@test "cache: unknown model does not create cache file" {
  run run_sl "unknown" 25 "$TEST_SID" 60000
  [ ! -f "/tmp/claude-code-statusline-model-${TEST_SID}" ]
}

@test "cache: preserved when duration unchanged (no new activity)" {
  invoke "Opus 4.6" 25 "$TEST_SID" 60000
  # Same duration, CC now reports Sonnet -- cache should win
  run run_sl "Sonnet 4.6" 25 "$TEST_SID" 60000
  [[ "$(plain)" == *"✦ Opus 4.6"* ]]
  [ "$(cached_model)" = "Opus 4.6" ]
}

@test "cache: updated when duration increases with known model" {
  invoke "Opus 4.6" 25 "$TEST_SID" 60000
  run run_sl "Sonnet 4.6" 25 "$TEST_SID" 120000
  [[ "$(plain)" == *"✦ Sonnet 4.6"* ]]
  [ "$(cached_model)" = "Sonnet 4.6" ]
  [ "$(cached_duration)" = "120000" ]
}

@test "cache: NOT updated when duration increases with garbled model" {
  invoke "Opus 4.6" 25 "$TEST_SID" 60000
  # Garbled name fails validation -> treated as unknown -> cache preserved
  run run_sl "Op.6" 25 "$TEST_SID" 120000
  [[ "$(plain)" == *"✦ Opus 4.6"* ]]
  [ "$(cached_model)" = "Opus 4.6" ]
}

@test "cache: session restart (duration decreases) resets cache" {
  invoke "Opus 4.6" 25 "$TEST_SID" 120000
  run run_sl "Sonnet 4.6" 25 "$TEST_SID" 5000
  [[ "$(plain)" == *"✦ Sonnet 4.6"* ]]
  [ "$(cached_model)" = "Sonnet 4.6" ]
  [ "$(cached_duration)" = "5000" ]
}

@test "cache: session restart with unknown model shows unknown" {
  invoke "Opus 4.6" 25 "$TEST_SID" 120000
  run run_sl "unknown" 25 "$TEST_SID" 5000
  # Restart detected but model is unknown -- display shows unknown
  # (old cache is from previous session lifecycle, not reused)
  [[ "$(plain)" == *"✦ unknown"* ]]
}

@test "cache: sessions are fully isolated" {
  invoke "Opus 4.6" 25 "${TEST_SID}-a" 60000
  invoke "Sonnet 4.6" 25 "${TEST_SID}-b" 60000
  [ "$(cached_model "${TEST_SID}-a")" = "Opus 4.6" ]
  [ "$(cached_model "${TEST_SID}-b")" = "Sonnet 4.6" ]
}

@test "cache: empty session_id bypasses caching" {
  run run_sl "Opus 4.6" 25 "" 60000
  [ "$status" -eq 0 ]
  [[ "$(plain)" == *"✦ Opus 4.6"* ]]
  # No cache file for empty session (safe_id is empty, caching is skipped)
  [ ! -f "/tmp/claude-code-statusline-model-" ]
}
