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
  [[ "$(plain)" == *"⚡500 tpm"* ]]
}

@test "tpm: shows N.Nk for 1000-9999" {
  # 3000 tokens in 60s = 3000 tpm
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 2000 1000
  [[ "$(plain)" == *"3.0k tpm"* ]]
}

@test "tpm: shows Nk for 10000+" {
  # 20000 tokens in 60s = 20000 tpm
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 12000 8000
  [[ "$(plain)" == *"20k tpm"* ]]
}

# ─── TPM bolt colors ───

@test "bolt: no color below 1000 tpm" {
  # 500 tpm -> plain bolt
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 500 0
  # Should NOT have any color code immediately before the bolt
  [[ "$output" != *$'\033[93m'"⚡"* ]]
  [[ "$output" != *$'\033[38;5;209m'"⚡"* ]]
  [[ "$output" != *$'\033[91m'"⚡"* ]]
  [[ "$output" != *$'\033[38;5;57m'"⚡"* ]]
}

@test "bolt: yellow at 1000 tpm" {
  # 1000 tokens in 60s = 1000 tpm
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 600 400
  [[ "$output" == *$'\033[93m'"⚡"* ]]
}

@test "bolt: orange at 5000 tpm" {
  # 5000 tokens in 60s = 5000 tpm
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 3000 2000
  [[ "$output" == *$'\033[38;5;209m'"⚡"* ]]
}

@test "bolt: red at 10000 tpm" {
  # 10000 tokens in 60s = 10000 tpm
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 6000 4000
  [[ "$output" == *$'\033[91m'"⚡"* ]]
}

@test "bolt: violet at 20000 tpm" {
  # 20000 tokens in 60s = 20000 tpm
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 12000 8000
  [[ "$output" == *$'\033[38;5;57m'"⚡"* ]]
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

@test "tpm: session restart clears window" {
  invoke "Opus 4.6" 25 "$TEST_SID" 120000 50000 30000
  # Duration goes backward -> restart -> window resets
  # 1000 tokens in 5s = 12000 tpm
  run run_sl "Opus 4.6" 25 "$TEST_SID" 5000 600 400
  [[ "$(plain)" == *"12k tpm"* ]]
}
