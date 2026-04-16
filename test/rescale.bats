#!/usr/bin/env bats

load 'helpers'

# These tests exercise the real rescale math (no CLAUDE_AUTOCOMPACT_PCT_OVERRIDE
# identity shim). The rescale formula:
#   effective_size = ctx_size - 33000  (or ctx_size * override/100 when override set)
#   displayed      = used_percentage * ctx_size / effective_size
# Capped at 100%, with a red color tier past the autocompact threshold.

# ─── 200k window (default) ───

@test "rescale 200k: 0% raw stays 0%" {
  run run_sl_rescaled "Opus 4.6" 0 "" "" "" "" "" "" "" "" "" "" 200000
  [[ "$(plain)" == *" 0%"* ]]
}

@test "rescale 200k: 50% raw shows ~59%" {
  # 50 * 200000 / 167000 = 59.88 → 59
  run run_sl_rescaled "Opus 4.6" 50 "" "" "" "" "" "" "" "" "" "" 200000
  [[ "$(plain)" == *" 59%"* ]]
}

@test "rescale 200k: 70% raw shows ~83%" {
  # 70 * 200000 / 167000 = 83.83 → 83
  run run_sl_rescaled "Opus 4.6" 70 "" "" "" "" "" "" "" "" "" "" 200000
  [[ "$(plain)" == *" 83%"* ]]
}

@test "rescale 200k: 84% raw caps at 100%" {
  # 84 * 200000 / 167000 = 100.59 → 100 (over threshold)
  run run_sl_rescaled "Opus 4.6" 84 "" "" "" "" "" "" "" "" "" "" 200000
  [[ "$(plain)" == *" 100%"* ]]
}

@test "rescale 200k: 95% raw displays 100%" {
  run run_sl_rescaled "Opus 4.6" 95 "" "" "" "" "" "" "" "" "" "" 200000
  [[ "$(plain)" == *" 100%"* ]]
}

# ─── 1M window ───

@test "rescale 1M: 50% raw shows ~51%" {
  # 50 * 1000000 / 967000 = 51.7 → 51
  run run_sl_rescaled "Opus 4.6" 50 "" "" "" "" "" "" "" "" "" "" 1000000
  [[ "$(plain)" == *" 51%"* ]]
}

@test "rescale 1M: 96% raw shows 99%" {
  # 96 * 1000000 / 967000 = 99.27 → 99
  run run_sl_rescaled "Opus 4.6" 96 "" "" "" "" "" "" "" "" "" "" 1000000
  [[ "$(plain)" == *" 99%"* ]]
}

@test "rescale 1M: 97% raw caps at 100%" {
  # 97 * 1000000 / 967000 = 100.31 → 100 (over threshold)
  run run_sl_rescaled "Opus 4.6" 97 "" "" "" "" "" "" "" "" "" "" 1000000
  [[ "$(plain)" == *" 100%"* ]]
}

# ─── Missing ctx_size falls back to 200k ───

@test "rescale: missing ctx_size treated as 200k" {
  # No ctx_size passed → JSON omits it → script defaults 0 → treated as 200000
  # 50 raw should render as 59
  run run_sl_rescaled "Opus 4.6" 50
  [[ "$(plain)" == *" 59%"* ]]
}

# ─── CLAUDE_AUTOCOMPACT_PCT_OVERRIDE ───

@test "rescale override: 90 with 200k, 45 raw shows 50%" {
  # effective = 200000 * 90/100 = 180000
  # displayed = 45 * 200000 / 180000 = 50
  CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=90 run run_sl_rescaled "Opus 4.6" 45 "" "" "" "" "" "" "" "" "" "" 200000
  [[ "$(plain)" == *" 50%"* ]]
}

@test "rescale override: 100 with 200k is identity" {
  # effective = ctx_size, displayed = raw
  CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=100 run run_sl_rescaled "Opus 4.6" 70 "" "" "" "" "" "" "" "" "" "" 200000
  [[ "$(plain)" == *" 70%"* ]]
}

@test "rescale override: garbage value ignored, falls back to 33k buffer" {
  # Invalid override → default 33k buffer path
  # 50 * 200000 / 167000 = 59
  CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=garbage run run_sl_rescaled "Opus 4.6" 50 "" "" "" "" "" "" "" "" "" "" 200000
  [[ "$(plain)" == *" 59%"* ]]
}

@test "rescale override: out of range value ignored" {
  # 0 and 101 should be rejected
  CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=101 run run_sl_rescaled "Opus 4.6" 50 "" "" "" "" "" "" "" "" "" "" 200000
  [[ "$(plain)" == *" 59%"* ]]
}

# ─── Red color kicks in near compaction ───

@test "rescale color: 90%+ displayed uses red" {
  # 76 raw on 200k → rescaled 91 → red tier (≥90)
  run run_sl_rescaled "Opus 4.6" 76 "" "" "" "" "" "" "" "" "" "" 200000
  [[ "$output" == *$'\033[91m'* ]]
}

@test "rescale color: at threshold (capped 100%) uses red" {
  # 90 raw on 200k → rescaled 107 → capped 100 → red (≥90)
  run run_sl_rescaled "Opus 4.6" 90 "" "" "" "" "" "" "" "" "" "" 200000
  [[ "$output" == *$'\033[91m'"█████"* ]]
}

@test "rescale color: 75-89% displayed uses orange" {
  # 70 raw on 200k → rescaled 83 → orange tier (75-89)
  run run_sl_rescaled "Opus 4.6" 70 "" "" "" "" "" "" "" "" "" "" 200000
  [[ "$output" == *$'\033[38;5;208m'* ]]
  [[ "$output" != *$'\033[91m'"█"* ]]
}
