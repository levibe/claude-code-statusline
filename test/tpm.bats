#!/usr/bin/env bats

load 'helpers'

# ─── TPM calculation ───

@test "tpm: not shown when duration is zero" {
  run run_sl "Opus 4.6" 25 "$TEST_SID" 0 0 0
  [[ "$(plain)" != *"tpm"* ]]
}

@test "tpm: not shown when tokens are zero" {
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 0 0
  [[ "$(plain)" != *"tpm"* ]]
}

@test "tpm: shows raw number below 1k" {
  # 500 in + 0 out in 60s = 500 tpm
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 500 0
  [[ "$(plain)" == *"ϟ 500 tpm"* ]]
}

@test "tpm: shows N.Nk for 1000-9999" {
  # 3000 tokens in 60s = 3000 tpm
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 2000 1000
  [[ "$(plain)" == *"3.0k tpm"* ]]
}

@test "tpm: shows N.Nk for 10k-99.9k and integer for 100k+" {
  # 20000 tokens in 60s = 20000 tpm
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 12000 8000
  [[ "$(plain)" == *"20.0k tpm"* ]]
  # 100000 tokens in 60s = 100000 tpm
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 60000 40000
  [[ "$(plain)" == *"100k tpm"* ]]
}

@test "tpm: shows N.NM for 1M-99.9M" {
  # 1500000 tokens in 60s = 1500000 tpm
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 1000000 500000
  [[ "$(plain)" == *"1.5M tpm"* ]]
}

@test "tpm: shows integer M for 100M+" {
  # 100000000 tokens in 60s = 100000000 tpm
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 60000000 40000000
  [[ "$(plain)" == *"100M tpm"* ]]
}

# ─── TPM bolt colors ───

@test "bolt: no color below 1000 tpm" {
  # 500 tpm -> plain bolt
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 500 0
  # Should NOT have any color code immediately before the bolt
  [[ "$output" != *$'\033[93m'"ϟ"* ]]
  [[ "$output" != *$'\033[38;5;209m'"ϟ"* ]]
  [[ "$output" != *$'\033[91m'"ϟ"* ]]
  [[ "$output" != *$'\033[38;5;57m'"ϟ"* ]]
}

@test "bolt: yellow at 1000 tpm" {
  # 1000 tokens in 60s = 1000 tpm
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 600 400
  [[ "$output" == *$'\033[93m'"ϟ"* ]]
}

@test "bolt: orange at 5000 tpm" {
  # 5000 tokens in 60s = 5000 tpm
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 3000 2000
  [[ "$output" == *$'\033[38;5;209m'"ϟ"* ]]
}

@test "bolt: red at 10000 tpm" {
  # 10000 tokens in 60s = 10000 tpm
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 6000 4000
  [[ "$output" == *$'\033[91m'"ϟ"* ]]
}

@test "bolt: violet at 20000 tpm" {
  # 20000 tokens in 60s = 20000 tpm
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 12000 8000
  [[ "$output" == *$'\033[38;5;57m'"ϟ"* ]]
}

@test "bolt: hot pink at 1M tpm" {
  # 1500000 tokens in 60s = 1500000 tpm
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 1000000 500000
  [[ "$output" == *$'\033[38;5;198m'"ϟ"* ]]
}

# ─── TPM sliding window ───

@test "tpm: first invocation uses full-session average" {
  # 8000 tokens in 60s = 8000 tpm
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000
  [[ "$(plain)" == *"8.0k tpm"* ]]
}

@test "tpm: sliding window overrides average on second call" {
  # Call 1: 8000 tokens at t=60s
  invoke "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000
  # Call 2: 9000 tokens at t=120s -> window: 1000 tok / 60s = 1000 tpm
  run run_sl "Opus 4.6" 25 "$TEST_SID" 120000 5500 3500
  [[ "$(plain)" == *"1.0k tpm"* ]]
}

@test "tpm: session restart hides segment when token delta is negative" {
  # Prior session ended with 80000 tokens at t=120s
  invoke "Opus 4.6" 25 "$TEST_SID" 120000 50000 30000
  # Resumed session reports fewer total tokens (e.g. context trim).
  # Without the mitigation this would display the spurious full-session
  # average (1000 tok / 5s = 12000 tpm). Sentinel keeps the segment hidden.
  run run_sl "Opus 4.6" 25 "$TEST_SID" 5000 600 400
  [[ "$(plain)" != *"tpm"* ]]
}

@test "tpm: session restart recovers post-resume rate via synthetic baseline" {
  # Prior session ended with 50000 tokens at t=600s
  invoke "Opus 4.6" 25 "$TEST_SID" 600000 30000 20000
  # Resumed session: 5000 new tokens in 10s of post-resume time.
  # Baseline (0, 50000) + current (10000, 55000) -> window_tpm = 5000*60/10 = 30000
  run run_sl "Opus 4.6" 25 "$TEST_SID" 10000 35000 20000
  [[ "$(plain)" == *"30.0k tpm"* ]]
}

@test "tpm: sentinel clears once a positive window_tpm is produced" {
  # Pre-resume: 80000 tokens. Resume with 1000 tokens (trim case) -> truncate, sentinel set.
  invoke "Opus 4.6" 25 "$TEST_SID" 120000 50000 30000
  invoke "Opus 4.6" 25 "$TEST_SID" 5000 600 400          # state: 5000 1000, sentinel set
  # Continued post-resume activity produces a positive delta -> sentinel clears.
  # delta = 2000-1000 = 1000 tokens over 60000ms = 1000 tpm
  run run_sl "Opus 4.6" 25 "$TEST_SID" 65000 1200 800
  [[ "$(plain)" == *"1.0k tpm"* ]]
}

@test "tpm: session restart with zero prior tokens hides segment" {
  # Prior session recorded a zero-token sample. prev_tok=0 -> truncate path, sentinel set.
  invoke "Opus 4.6" 25 "$TEST_SID" 60000 0 0
  run run_sl "Opus 4.6" 25 "$TEST_SID" 5000 600 400
  [[ "$(plain)" != *"tpm"* ]]
}

@test "tpm: orphaned sentinel is cleared when state file is missing" {
  # Simulate /tmp eviction: sentinel exists but state file does not.
  : > "/tmp/claude-code-statusline-tpm-${TEST_SID}.restart"
  rm -f "/tmp/claude-code-statusline-tpm-${TEST_SID}"
  # First invocation should clear the orphaned sentinel and display normally.
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000
  [[ "$(plain)" == *"8.0k tpm"* ]]
}
