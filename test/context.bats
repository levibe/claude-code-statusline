#!/usr/bin/env bats

load 'helpers'

# ─── Context bar ───

@test "bar: 0% shows all empty" {
  run run_sl "Opus 4.6" 0
  [[ "$(plain)" == *"░░░░░ 0%"* ]]
}

@test "bar: 6% stays empty (below +7 threshold)" {
  run run_sl "Opus 4.6" 6
  [[ "$(plain)" == *"░░░░░ 6%"* ]]
}

@test "bar: 7% shows light shade" {
  run run_sl "Opus 4.6" 7
  [[ "$(plain)" == *"▒░░░░ 7%"* ]]
}

@test "bar: 13% shows dark shade" {
  run run_sl "Opus 4.6" 13
  [[ "$(plain)" == *"▓░░░░ 13%"* ]]
}

@test "bar: 20% shows one full block" {
  run run_sl "Opus 4.6" 20
  [[ "$(plain)" == *"█░░░░ 20%"* ]]
}

@test "bar: 40% shows two full blocks" {
  run run_sl "Opus 4.6" 40
  [[ "$(plain)" == *"██░░░ 40%"* ]]
}

@test "bar: 47% shows two full + light shade" {
  run run_sl "Opus 4.6" 47
  [[ "$(plain)" == *"██▒░░ 47%"* ]]
}

@test "bar: 57% shows two full + dark shade" {
  run run_sl "Opus 4.6" 57
  [[ "$(plain)" == *"██▓░░ 57%"* ]]
}

@test "bar: 60% shows three full blocks" {
  run run_sl "Opus 4.6" 60
  [[ "$(plain)" == *"███░░ 60%"* ]]
}

@test "bar: 80% shows four full blocks" {
  run run_sl "Opus 4.6" 80
  [[ "$(plain)" == *"████░ 80%"* ]]
}

@test "bar: 93% shows four full + dark shade" {
  run run_sl "Opus 4.6" 93
  [[ "$(plain)" == *"████▓ 93%"* ]]
}

@test "bar: 100% shows all full" {
  run run_sl "Opus 4.6" 100
  [[ "$(plain)" == *"█████ 100%"* ]]
}

# ─── Context color tiers ───

@test "color: dim below 35%" {
  run run_sl "Opus 4.6" 34
  # \033[38;5;247m = dim gray
  [[ "$output" == *$'\033[38;5;247m'"█"* ]]
}

@test "color: yellow-green at 35%" {
  run run_sl "Opus 4.6" 35
  # \033[38;5;148m = yellow-green
  [[ "$output" == *$'\033[38;5;148m'"█"* ]]
}

@test "color: yellow at 50%" {
  run run_sl "Opus 4.6" 50
  # \033[93m = yellow
  [[ "$output" == *$'\033[93m'"██"* ]]
}

@test "color: orange at 75%" {
  run run_sl "Opus 4.6" 75
  # \033[38;5;208m = orange
  [[ "$output" == *$'\033[38;5;208m'"███"* ]]
}
