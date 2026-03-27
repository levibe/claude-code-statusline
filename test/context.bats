#!/usr/bin/env bats

load 'helpers'

# ─── Context bar ───

@test "bar: 0% shows empty" {
  run run_sl "Opus 4.6" 0
  [[ "$(plain)" == *"░░░░░ 0%"* ]]
}

@test "bar: 19% shows empty (below 20% threshold)" {
  run run_sl "Opus 4.6" 19
  [[ "$(plain)" == *"░░░░░ 19%"* ]]
}

@test "bar: 20% shows one filled" {
  run run_sl "Opus 4.6" 20
  [[ "$(plain)" == *"▓░░░░ 20%"* ]]
}

@test "bar: 40% shows two filled" {
  run run_sl "Opus 4.6" 40
  [[ "$(plain)" == *"▓▓░░░ 40%"* ]]
}

@test "bar: 60% shows three filled" {
  run run_sl "Opus 4.6" 60
  [[ "$(plain)" == *"▓▓▓░░ 60%"* ]]
}

@test "bar: 80% shows four filled" {
  run run_sl "Opus 4.6" 80
  [[ "$(plain)" == *"▓▓▓▓░ 80%"* ]]
}

@test "bar: 95% shows full (special case)" {
  run run_sl "Opus 4.6" 95
  [[ "$(plain)" == *"▓▓▓▓▓ 95%"* ]]
}

@test "bar: 100% shows full" {
  run run_sl "Opus 4.6" 100
  [[ "$(plain)" == *"▓▓▓▓▓ 100%"* ]]
}

# ─── Context color tiers ───

@test "color: dim below 35%" {
  run run_sl "Opus 4.6" 34
  # \033[38;5;247m = dim gray
  [[ "$output" == *$'\033[38;5;247m'"▓"* ]]
}

@test "color: yellow-green at 35%" {
  run run_sl "Opus 4.6" 35
  # \033[38;5;148m = yellow-green
  [[ "$output" == *$'\033[38;5;148m'"▓"* ]]
}

@test "color: yellow at 50%" {
  run run_sl "Opus 4.6" 50
  # \033[93m = yellow
  [[ "$output" == *$'\033[93m'"▓"* ]]
}

@test "color: orange at 75%" {
  run run_sl "Opus 4.6" 75
  # \033[38;5;208m = orange
  [[ "$output" == *$'\033[38;5;208m'"▓"* ]]
}
