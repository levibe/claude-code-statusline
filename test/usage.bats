#!/usr/bin/env bats

load 'helpers'

# ─── Display ───

@test "usage: no second line when rate_limits absent" {
  run run_sl "Opus 4.6" 25
  [[ "$(plain)" != *$'\n'* ]]
}

@test "usage: shows 5h only when only five_hour present" {
  now=$(date +%s)
  reset=$((now + 3600))
  # 80% used -> always show (>= 75%)
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "" 80 "$reset" "" ""
  plain_out=$(plain)
  [[ "$plain_out" == *"5h 80%"* ]]
  [[ "$plain_out" != *"7d "* ]]
}

@test "usage: shows 7d only when only seven_day present" {
  now=$(date +%s)
  reset=$((now + 86400))
  # 80% used -> always show (>= 75%)
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "" "" "" 80 "$reset"
  plain_out=$(plain)
  [[ "$plain_out" != *"5h "* ]]
  [[ "$plain_out" == *"7d 80%"* ]]
}

@test "usage: shows both when both present" {
  now=$(date +%s)
  reset_5h=$((now + 3600))
  reset_7d=$((now + 86400))
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "" 80 "$reset_5h" 80 "$reset_7d"
  plain_out=$(plain)
  [[ "$plain_out" == *"5h 80%"* ]]
  [[ "$plain_out" == *"7d 80%"* ]]
}

@test "usage: second line separated by newline" {
  now=$(date +%s)
  reset=$((now + 3600))
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "" 80 "$reset" "" ""
  line2=$(plain | sed -n '2p')
  [[ "$line2" == *"5h 80%"* ]]
}

@test "usage: percentage is floored to integer" {
  now=$(date +%s)
  reset=$((now + 3600))
  # 83.7% -> should display as 83%
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "" 83.7 "$reset" "" ""
  [[ "$(plain)" == *"5h 83%"* ]]
}

# ─── Countdown formatting ───

@test "usage: countdown shows days and hours" {
  now=$(date +%s)
  # 2 days 5 hours + buffer = 190830s
  reset=$((now + 190830))
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "" "" "" 80 "$reset"
  [[ "$(plain)" == *"2d 5h"* ]]
}

@test "usage: countdown shows hours and minutes" {
  now=$(date +%s)
  # 3 hours 30 minutes = 12600s (+2s buffer for timing)
  reset=$((now + 12602))
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "" 80 "$reset" "" ""
  [[ "$(plain)" == *"3h 30m"* ]]
}

@test "usage: countdown shows minutes when under an hour" {
  now=$(date +%s)
  reset=$((now + 330))
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "" 80 "$reset" "" ""
  [[ "$(plain)" == *"5m"* ]]
}

@test "usage: countdown shows seconds when under a minute" {
  now=$(date +%s)
  reset=$((now + 50))
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "" 80 "$reset" "" ""
  [[ "$(plain)" == *"49s"* ]] || [[ "$(plain)" == *"50s"* ]]
}

@test "usage: 0% usage is displayed correctly" {
  now=$(date +%s)
  reset=$((now + 9000))
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "" 0 "$reset" "" ""
  [[ "$(plain)" == *"5h 0%"* ]]
}

@test "usage: resets_at in the past clamps to 0s" {
  now=$(date +%s)
  reset=$((now - 100))
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "" 80 "$reset" "" ""
  [[ "$(plain)" == *"5h 80% 0s"* ]]
}

@test "usage: non-numeric resets_at is ignored" {
  # Construct JSON directly to bypass make_json's --argjson validation
  json='{"cwd":"","session_id":"'"$TEST_SID"'","transcript_path":"","context_window":{"used_percentage":25,"total_input_tokens":5000,"total_output_tokens":3000},"model":{"display_name":"Opus 4.6"},"cost":{"total_duration_ms":60000},"rate_limits":{"five_hour":{"used_percentage":80,"resets_at":"not-a-number"}}}'
  run sh -c 'echo "$1" | sh "$2"' _ "$json" "$SCRIPT"
  plain_out=$(printf '%s' "$output" | sed $'s/\033\[[0-9;]*m//g')
  [[ "$plain_out" != *"5h "* ]]
}

@test "usage: empty session_id still shows rate limits" {
  now=$(date +%s)
  reset=$((now + 3600))
  # Empty session_id means no pace state file, treated as first invocation
  # Use 60% (under-pace) to verify the empty-session fallback shows it anyway
  run run_sl "Opus 4.6" 25 "" 60000 5000 3000 "" "" 60 "$reset" "" ""
  [[ "$(plain)" == *"5h 60%"* ]]
}

# ─── Color tiers ───

@test "usage color: dim below 50%" {
  now=$(date +%s)
  reset=$((now + 3600))
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "" 49 "$reset" "" ""
  [[ "$output" == *$'\033[38;5;247m'"5h "$'\033[97m'"49%"* ]]
}

@test "usage color: yellow at 50%" {
  now=$(date +%s)
  reset=$((now + 3600))
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "" 50 "$reset" "" ""
  [[ "$output" == *$'\033[93m'"5h "$'\033[93m'"50%"* ]]
}

@test "usage color: orange at 75%" {
  now=$(date +%s)
  reset=$((now + 3600))
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "" 75 "$reset" "" ""
  [[ "$output" == *$'\033[38;5;208m'"5h "$'\033[38;5;208m'"75%"* ]]
}

@test "usage color: red at 90%" {
  now=$(date +%s)
  reset=$((now + 3600))
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "" 90 "$reset" "" ""
  [[ "$output" == *$'\033[91m'"5h "$'\033[91m'"90%"* ]]
}

# ─── Pace visibility ───

@test "usage: first invocation always shows regardless of pace" {
  now=$(date +%s)
  # 30% used with 50% elapsed (9000s remaining of 18000s) -> projected 60%, under pace
  # But first invocation, so should show
  reset=$((now + 9000))
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "" 30 "$reset" "" ""
  [[ "$(plain)" == *"5h 30%"* ]]
}

@test "usage: hidden when under pace on second invocation" {
  now=$(date +%s)
  # 30% used with 50% elapsed (9000s remaining of 18000s) -> projected 60%, under pace
  reset=$((now + 9000))
  # First invocation (creates state file)
  invoke "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "" 30 "$reset" "" ""
  expire_first_usage
  # Second invocation should apply pace logic -> hidden
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "" 30 "$reset" "" ""
  [[ "$(plain)" != *"5h "* ]]
}

@test "usage: shown when over pace on second invocation" {
  now=$(date +%s)
  # 70% used with 60% elapsed (7200s remaining of 18000s) -> projected 116%, over pace
  reset=$((now + 7200))
  invoke "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "" 70 "$reset" "" ""
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "" 70 "$reset" "" ""
  [[ "$(plain)" == *"5h 70%"* ]]
}

@test "usage: always shown when >= 75% regardless of pace" {
  now=$(date +%s)
  # 75% used with only 10% elapsed (16200s remaining of 18000s)
  reset=$((now + 16200))
  invoke "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "" 75 "$reset" "" ""
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "" 75 "$reset" "" ""
  [[ "$(plain)" == *"5h 75%"* ]]
}

@test "usage: 5h and 7d visibility independent" {
  now=$(date +%s)
  # 5h: 30% used, 50% elapsed -> under pace, hidden (not first invocation)
  # 7d: 80% used -> always shown (>= 75%)
  reset_5h=$((now + 9000))
  reset_7d=$((now + 302400))
  invoke "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "" 30 "$reset_5h" 80 "$reset_7d"
  expire_first_usage
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "" 30 "$reset_5h" 80 "$reset_7d"
  plain_out=$(plain)
  [[ "$plain_out" != *"5h "* ]]
  [[ "$plain_out" == *"7d 80%"* ]]
}

@test "usage: shown when window just started (elapsed <= 0)" {
  now=$(date +%s)
  # resets_at is nearly a full window away -> elapsed ~0
  reset=$((now + 18000))
  invoke "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "" 5 "$reset" "" ""
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "" 5 "$reset" "" ""
  [[ "$(plain)" == *"5h 5%"* ]]
}

# ─── First-usage window ───

@test "usage: shown within first-usage window on second invocation" {
  now=$(date +%s)
  # 30% used with 50% elapsed -> under pace, normally hidden
  reset=$((now + 9000))
  invoke "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "" 30 "$reset" "" ""
  # Second invocation is immediate (within 5s window) -> should still show
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "" 30 "$reset" "" ""
  [[ "$(plain)" == *"5h 30%"* ]]
}

@test "usage: hidden after first-usage window expires" {
  now=$(date +%s)
  reset=$((now + 9000))
  invoke "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "" 30 "$reset" "" ""
  expire_first_usage
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "" 30 "$reset" "" ""
  [[ "$(plain)" != *"5h "* ]]
}

@test "usage: 100% usage displayed correctly" {
  now=$(date +%s)
  reset=$((now + 60))
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "" 100 "$reset" "" ""
  [[ "$(plain)" == *"5h 100%"* ]]
}

@test "usage: pace check uses decimal precision (49.9% over pace, 49% would not be)" {
  now=$(date +%s)
  # 5h window = 18000s. At 49.9% with 8950s remaining (elapsed = 9050s):
  # Pace threshold = elapsed/window = 9050/18000 = 50.3%
  # 49.9% < 50.3% -> under pace (should be hidden)
  # But at 49% -> 49% < 50.3% -> also under pace
  # Use elapsed = 8990s (remaining = 9010s) -> threshold = 8990/18000 = 49.94%
  # 49.9% >= 49.94%? No (barely under). Use elapsed = 9000s -> threshold = 50%
  # 49.9% < 50% -> under pace. 49% < 50% -> also under.
  # Use elapsed = 9010s (remaining = 8990s) -> threshold = 9010/18000 = 50.06%
  # Need: 49.9% over pace but 49% not. threshold must be between 49% and 49.9%.
  # threshold = elapsed/18000 -> elapsed = 18000 * 0.495 = 8910 -> remaining = 9090
  # 49.9% >= 49.5% -> over pace (shown). 49% >= 49.5%? No -> under pace (hidden).
  reset=$((now + 9090))
  invoke "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "" 49.9 "$reset" "" ""
  expire_first_usage
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "" 49.9 "$reset" "" ""
  [[ "$(plain)" == *"5h 49%"* ]]
}

@test "usage: pace check at 49% (integer) hidden at same elapsed where 49.9% shows" {
  now=$(date +%s)
  # Same elapsed as above: remaining = 9090, threshold = 49.5%
  # 49% < 49.5% -> under pace -> hidden
  reset=$((now + 9090))
  invoke "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "" 49 "$reset" "" ""
  expire_first_usage
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "" 49 "$reset" "" ""
  [[ "$(plain)" != *"5h "* ]]
}

@test "usage: empty state file from old version treated as window expired" {
  now=$(date +%s)
  reset=$((now + 9000))
  # Simulate old-version state file (empty)
  : > "/tmp/claude-code-statusline-usage-${TEST_SID}"
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "" 30 "$reset" "" ""
  # Under pace and window expired -> hidden
  [[ "$(plain)" != *"5h "* ]]
}
