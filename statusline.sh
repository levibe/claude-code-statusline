#!/bin/sh
# Line 1: ⌥ branch  +N -N  ✦ model  ██▒░░ N%  ϟ N tpm
# Line 2: 5h N% XhYm  7d N% XdYh   (shown when on pace / ≥75%)

TPM_STATE_PREFIX="claude-code-statusline-tpm"
TPM_WINDOW_MS=300000  # 5 minutes
MODEL_STATE_PREFIX="claude-code-statusline-model"
SUBAGENT_STATE_PREFIX="claude-code-statusline-subagent"
USAGE_STATE_PREFIX="claude-code-statusline-usage"
USAGE_FIRST_WINDOW_S=5   # seconds to show rate limits on first invocation

# Helpers for rate limit display
fmt_countdown() {
  if [ "$1" -ge 86400 ] 2>/dev/null; then
    printf '%dd %dh' "$(($1 / 86400))" "$(($1 % 86400 / 3600))"
  elif [ "$1" -ge 3600 ] 2>/dev/null; then
    printf '%dh %dm' "$(($1 / 3600))" "$(($1 % 3600 / 60))"
  elif [ "$1" -ge 60 ] 2>/dev/null; then
    printf '%dm' "$(($1 / 60))"
  else
    printf '%ds' "$1"
  fi
}

usage_color() {
  if [ "$1" -ge 90 ] 2>/dev/null; then printf '%s' '\033[91m'
  elif [ "$1" -ge 75 ] 2>/dev/null; then printf '%s' '\033[38;5;208m'
  elif [ "$1" -ge 50 ] 2>/dev/null; then printf '%s' '\033[93m'
  else printf '%s' '\033[38;5;247m'
  fi
}

usage_value_color() {
  if [ "$1" -ge 50 ] 2>/dev/null; then usage_color "$1"
  else printf '%s' '\033[97m'
  fi
}

# should_show_window pct_raw reset_at window_seconds first_usage
# Prints two lines (pct_int, remaining) if the window should be shown,
# or nothing (empty output) otherwise.  Uses _now from caller scope.
should_show_window() {
  _pct=$1; _reset=$2; _window=$3; _first=$4
  _pct_int=${_pct%%.*}
  _pct_int=${_pct_int:-0}
  _remaining=$((_reset - _now))
  [ "$_remaining" -lt 0 ] 2>/dev/null && _remaining=0

  case "$_pct" in
    *.*)
      _i=${_pct%%.*}; _f=${_pct#*.}; _d=${_f%"${_f#?}"}
      _pct_x10=$(( (${_i:-0} * 10) + ${_d:-0} ))
      ;;
    *)
      _pct_x10=$(( ${_pct:-0} * 10 ))
      ;;
  esac

  _show=0
  if [ "$_first" -eq 1 ] || [ "$_pct_int" -ge 75 ]; then
    _show=1
  else
    _elapsed=$((_window - _remaining))
    if [ "$_elapsed" -le 0 ]; then
      _show=1
    elif [ "$((_pct_x10 * _window))" -ge "$((1000 * _elapsed))" ]; then
      _show=1
    fi
  fi

  if [ "$_show" -eq 1 ]; then
    printf '%s\n%s\n' "$_pct_int" "$_remaining"
  fi
}

input=$(cat)

# Single jq call to extract all fields (floor handles potential floats)
eval "$(echo "$input" | jq -r '
  "cwd=\(.cwd // "" | @sh)",
  "session_id=\(.session_id // "" | @sh)",
  "transcript_path=\(.transcript_path // "" | @sh)",
  "used=\(.context_window.used_percentage // 0 | floor | @sh)",
  "model=\(.model.display_name // "unknown" | sub(" *\\(.*\\)"; "") | @sh)",
  "ctx_size=\(.context_window.context_window_size // 0 | floor | @sh)",
  "total_in=\(.context_window.total_input_tokens // 0 | floor | @sh)",
  "total_out=\(.context_window.total_output_tokens // 0 | floor | @sh)",
  "duration_ms=\(.cost.total_duration_ms // 0 | floor | @sh)",
  "rl_5h_pct=\(.rate_limits.five_hour.used_percentage // "" | @sh)",
  "rl_5h_reset=\(.rate_limits.five_hour.resets_at // "" | @sh)",
  "rl_7d_pct=\(.rate_limits.seven_day.used_percentage // "" | @sh)",
  "rl_7d_reset=\(.rate_limits.seven_day.resets_at // "" | @sh)"
')"

# Defaults if jq fails or fields are missing
cwd=${cwd:-}; session_id=${session_id:-}; transcript_path=${transcript_path:-}
used=${used:-0}; model=${model:-unknown}; ctx_size=${ctx_size:-0}
total_in=${total_in:-0}; total_out=${total_out:-0}; duration_ms=${duration_ms:-0}
rl_5h_pct=${rl_5h_pct:-}; rl_5h_reset=${rl_5h_reset:-}
rl_7d_pct=${rl_7d_pct:-}; rl_7d_reset=${rl_7d_reset:-}

# Validate numeric fields
case "$rl_5h_reset" in ""|*[!0-9]*) rl_5h_reset="" ;; esac
case "$rl_7d_reset" in ""|*[!0-9]*) rl_7d_reset="" ;; esac
case "$rl_5h_pct" in ""|*[!0-9.]*|*.*.*) rl_5h_pct="" ;; esac
case "$rl_7d_pct" in ""|*[!0-9.]*|*.*.*) rl_7d_pct="" ;; esac

# Validate model name: must match "Name N.N" pattern (e.g. "Opus 4.6", "Sonnet 4.6", "Haiku 4.5")
# Garbled names from Claude Code (e.g. "Op.6") are treated as unknown so they don't pollute the cache
case "$model" in
  unknown) ;;
  *) echo "$model" | grep -qE '^[A-Z][a-z]+ [0-9]+\.[0-9]+$' || model="unknown" ;;
esac

# Session-scoped state key (used by model cache and sliding window TPM)
safe_id=$(printf '%s' "$session_id" | tr -dc 'a-zA-Z0-9_-')

# Temp file cleanup (set once, covers all temp files created below)
tmpfile=""
untracked_list=""
trap 'rm -f "$tmpfile" "$untracked_list"' EXIT

# Tokens per minute (full-session average as default)
total_tokens=$((total_in + total_out))

# Subagent tokens (mtime-cached to avoid re-parsing unchanged files)
subagent_tokens=0
if [ -n "$transcript_path" ] && [ -n "$safe_id" ]; then
  subagent_dir="${transcript_path%.jsonl}/subagents"
  if [ -d "$subagent_dir" ]; then
    subagent_cache="/tmp/${SUBAGENT_STATE_PREFIX}-${safe_id}"
    # Fingerprint: size:mtime:path per file, joined into one line
    if stat -c '%s' /dev/null >/dev/null 2>&1; then
      fingerprint=$(stat -c '%s:%Y:%n' "$subagent_dir"/agent-*.jsonl 2>/dev/null | tr '\n' '|')
    else
      fingerprint=$(stat -f '%z:%m:%N' "$subagent_dir"/agent-*.jsonl 2>/dev/null | tr '\n' '|')
    fi
    if [ -n "$fingerprint" ]; then
      cached_fp=""
      [ -f "$subagent_cache" ] && cached_fp=$(head -1 "$subagent_cache")
      if [ "$fingerprint" = "$cached_fp" ]; then
        subagent_tokens=$(tail -1 "$subagent_cache")
      else
        subagent_tokens=$(cat "$subagent_dir"/agent-*.jsonl 2>/dev/null \
          | jq -r 'select(.type == "assistant") | "\(.message.id) \(.message.usage.input_tokens // 0) \(.message.usage.output_tokens // 0)"' 2>/dev/null \
          | awk '{usage[$1]=$2" "$3} END {for(id in usage){split(usage[id],a);s+=a[1]+a[2]} print s+0}')
        subagent_tokens=${subagent_tokens:-0}
        printf '%s\n%s\n' "$fingerprint" "$subagent_tokens" > "$subagent_cache"
      fi
    fi
  fi
fi
subagent_tokens=${subagent_tokens:-0}
[ "$subagent_tokens" -gt 0 ] 2>/dev/null && total_tokens=$((total_tokens + subagent_tokens))

if [ "$duration_ms" -gt 0 ]; then
  tpm=$(( (total_tokens * 60000) / duration_ms ))
else
  tpm=0
fi

# Per-session model cache — prevents global model changes in other sessions
# from affecting this session's display before it has new activity.
#
# State file format (3 lines):
#   line 1: last known model string for this session
#   line 2: context_window_size at the time that model was recorded
#   line 3: duration_ms at the time that model was recorded
#
# Update rule: only replace the cached model when duration_ms has increased,
# meaning this session processed a real assistant turn.
# A model change with no new turn will take effect on the next turn.
if [ -n "$safe_id" ]; then
  model_file="/tmp/${MODEL_STATE_PREFIX}-${safe_id}"
  if [ -f "$model_file" ]; then
    cached_model=$(sed -n '1p' "$model_file")
    cached_ctx_size=$(sed -n '2p' "$model_file")
    cached_duration=$(sed -n '3p' "$model_file")
    # Migrate legacy 2-line cache: line 2 was duration_ms, line 3 missing
    if [ -n "$cached_ctx_size" ] && [ -z "$cached_duration" ]; then
      cached_duration="$cached_ctx_size"
      cached_ctx_size=0
    fi
    # Reject non-numeric cached values (e.g. from a corrupted/truncated file)
    case "$cached_ctx_size" in ""|*[!0-9]*) cached_ctx_size=0 ;; esac
    case "$cached_duration" in ""|*[!0-9]*) cached_duration=0 ;; esac
    if [ "$duration_ms" -lt "$cached_duration" ] 2>/dev/null; then
      # duration_ms went backwards → session restarted; reset cache
      [ "$model" != "unknown" ] && printf '%s\n%s\n%s\n' "$model" "$ctx_size" "$duration_ms" > "$model_file"
    elif [ "$duration_ms" -gt "$cached_duration" ] 2>/dev/null && [ "$model" != "unknown" ]; then
      # New activity with a known model → update cache
      printf '%s\n%s\n%s\n' "$model" "$ctx_size" "$duration_ms" > "$model_file"
    else
      # No new activity, or model is unknown → keep cached model + context size
      if [ -n "$cached_model" ]; then
        model="$cached_model"
        ctx_size="$cached_ctx_size"
      fi
    fi
  elif [ "$model" != "unknown" ]; then
    # First invocation for this session → initialize cache
    # Skip initialization if model is unknown (jq failure) to avoid caching a bad value
    printf '%s\n%s\n%s\n' "$model" "$ctx_size" "$duration_ms" > "$model_file"
  fi
fi

# Rescale context percentage so 100% displayed matches the actual autocompact
# point. Claude Code reserves ~33k tokens as an autocompact buffer, so without
# rescaling, users see "70% used" and get surprised by compaction at what looks
# like 83%. Runs after the cache block because cached ctx_size may replace the
# live value.
effective_ctx_size=$ctx_size
[ "$effective_ctx_size" -le 0 ] 2>/dev/null && effective_ctx_size=200000
effective_size=$((effective_ctx_size - 33000))
case "${CLAUDE_AUTOCOMPACT_PCT_OVERRIDE:-}" in
  ""|*[!0-9]*) ;;
  *)
    if [ "$CLAUDE_AUTOCOMPACT_PCT_OVERRIDE" -ge 1 ] 2>/dev/null \
      && [ "$CLAUDE_AUTOCOMPACT_PCT_OVERRIDE" -le 100 ] 2>/dev/null; then
      effective_size=$((effective_ctx_size * CLAUDE_AUTOCOMPACT_PCT_OVERRIDE / 100))
    fi
    ;;
esac
if [ "$effective_size" -gt 0 ] 2>/dev/null; then
  rescaled=$((used * effective_ctx_size / effective_size))
  if [ "$rescaled" -gt 100 ]; then
    used=100
  else
    used=$rescaled
  fi
fi

# Sliding window TPM (overrides full-session average when enough data)
if [ -n "$safe_id" ]; then
  state_file="/tmp/${TPM_STATE_PREFIX}-${safe_id}"
  [ -f "$state_file" ] || : > "$state_file"

  # Detect session restart (duration_ms went backwards)
  last_ms=$(tail -n 1 "$state_file" 2>/dev/null | awk '$1 ~ /^[0-9]+$/ { print $1 }')
  if [ -n "$last_ms" ] && [ "$duration_ms" -lt "$last_ms" ] 2>/dev/null; then
    : > "$state_file"
  fi

  cutoff=$((duration_ms - TPM_WINDOW_MS))
  [ "$cutoff" -lt 0 ] && cutoff=0

  tmpfile=$(mktemp "/tmp/${TPM_STATE_PREFIX}-XXXXXX")

  window_tpm=$(awk -v cutoff="$cutoff" -v cur_ms="$duration_ms" -v cur_tok="$total_tokens" -v tmpfile="$tmpfile" '
    BEGIN { oldest_ms = ""; oldest_tok = ""; last_ms = "" }
    $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && $1 + 0 >= cutoff {
      print > tmpfile
      if (oldest_ms == "") { oldest_ms = $1 + 0; oldest_tok = $2 + 0 }
      last_ms = $1 + 0
    }
    END {
      if (last_ms != cur_ms + 0)
        printf "%s %s\n", cur_ms, cur_tok > tmpfile
      close(tmpfile)
      delta_ms = cur_ms - oldest_ms
      delta_tok = cur_tok - oldest_tok
      if (oldest_ms != "" && delta_ms > 0)
        printf "%d", (delta_tok * 60000) / delta_ms
    }
  ' "$state_file" 2>/dev/null)

  [ -f "$tmpfile" ] && mv "$tmpfile" "$state_file"

  # Negative deltas (e.g. context window reset) produce negative TPM — intentionally ignored
  if [ -n "$window_tpm" ] && [ "$window_tpm" -gt 0 ] 2>/dev/null; then
    tpm=$window_tpm
  fi
fi

# 5-char progress bar with 4 shades (░▒▓█), 20 visual steps
bar=""
for i in 0 1 2 3 4; do
  slot_start=$((i * 20))
  remainder=$((used - slot_start))
  if [ "$remainder" -ge 20 ]; then
    bar="${bar}█"
  elif [ "$remainder" -ge 13 ]; then
    bar="${bar}▓"
  elif [ "$remainder" -ge 7 ]; then
    bar="${bar}▒"
  else
    bar="${bar}░"
  fi
done

# Context color gradient, relative to the rescaled `used` value (100% = autocompact point).
if [ "$used" -ge 90 ]; then
  ctx_color="\033[91m"          # red: compaction imminent or past
elif [ "$used" -ge 75 ]; then
  ctx_color="\033[38;5;208m"    # orange
elif [ "$used" -ge 50 ]; then
  ctx_color="\033[93m"          # yellow
elif [ "$used" -ge 35 ]; then
  ctx_color="\033[38;5;148m"    # yellow-green
else
  ctx_color="\033[38;5;247m"    # dim
fi

dim="\033[38;5;247m"
reset="\033[0m"
sep="  "

# Git branch + uncommitted diff stats (tracked + untracked)
branch=""
diff_stat=""
if [ -n "$cwd" ]; then
  branch=$(git --no-optional-locks -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)
  # Detached HEAD: show short SHA instead of literal "HEAD"
  [ "$branch" = "HEAD" ] && branch=$(git --no-optional-locks -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  # Empty repo (no commits): fall back to symbolic ref for branch name
  [ -z "$branch" ] && branch=$(git --no-optional-locks -C "$cwd" symbolic-ref --short HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    added=0
    removed=0
    # Tracked changes require at least one commit
    if git --no-optional-locks -C "$cwd" rev-parse HEAD 2>/dev/null >/dev/null; then
      # Tracked changes (text)
      stat=$(git --no-optional-locks -C "$cwd" diff --shortstat HEAD 2>/dev/null)
      added=$(echo "$stat" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+')
      removed=$(echo "$stat" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+')
      added=${added:-0}
      removed=${removed:-0}
      # Tracked binary changes: +1 per added/modified, -1 per deleted
      bin_added=$(git --no-optional-locks -C "$cwd" diff --diff-filter=AM --numstat HEAD 2>/dev/null | grep -c '^-' || true)
      bin_deleted=$(git --no-optional-locks -C "$cwd" diff --diff-filter=D --numstat HEAD 2>/dev/null | grep -c '^-' || true)
      added=$((added + bin_added))
      removed=$((removed + bin_deleted))
    fi
    # Untracked files: text lines + binary files counted as +1 each (cap at 10k)
    untracked_lines=0
    untracked_capped=0
    untracked_list=$(mktemp)
    git --no-optional-locks -C "$cwd" ls-files --others --exclude-standard -z 2>/dev/null > "$untracked_list"
    total_untracked=$(tr -cd '\0' < "$untracked_list" | wc -c | tr -d ' ')
    total_untracked=${total_untracked:-0}
    if [ "$total_untracked" -gt 0 ] 2>/dev/null; then
      # Text file lines
      raw_count=$(xargs -0 grep -Ih '' < "$untracked_list" 2>/dev/null | head -n 10001 | wc -l | tr -d ' ')
      raw_count=${raw_count:-0}
      if [ "$raw_count" -gt 10000 ] 2>/dev/null; then
        untracked_capped=1
        untracked_lines=10000
      else
        untracked_lines=$raw_count
      fi
      # Binary files: count each as +1 (total minus text files)
      text_files=$(xargs -0 grep -Il '' < "$untracked_list" 2>/dev/null | wc -l | tr -d ' ')
      text_files=${text_files:-0}
      binary_count=$((total_untracked - text_files))
      [ "$binary_count" -gt 0 ] 2>/dev/null && untracked_lines=$((untracked_lines + binary_count))
    fi
    rm -f "$untracked_list"
    [ "$untracked_lines" -gt 0 ] 2>/dev/null && added=$((added + untracked_lines))
    if [ "$added" -gt 0 ] || [ "$removed" -gt 0 ]; then
      diff_stat="${sep}"
      if [ "$untracked_capped" -eq 1 ]; then
        diff_stat="${diff_stat}\033[93m⚠ +${added}${reset}"
      elif [ "$added" -gt 0 ]; then
        diff_stat="${diff_stat}\033[92m+${added}${reset}"
      fi
      if [ "$removed" -gt 0 ]; then
        [ "$added" -gt 0 ] && diff_stat="${diff_stat} "
        diff_stat="${diff_stat}\033[91m-${removed}${reset}"
      fi
    fi
  fi
fi

# Rate limit visibility (each window shown independently)
show_5h=0
show_7d=0
rl_5h_pct_int=0
rl_7d_pct_int=0
remaining_5h=0
remaining_7d=0

if [ -n "$rl_5h_pct" ] || [ -n "$rl_7d_pct" ]; then
  _now=$(date +%s)

  # First invocation of this session (show for USAGE_FIRST_WINDOW_S seconds)?
  # State file creation is deferred until a window actually renders, so partial
  # data (e.g. pct without reset) does not burn the first-usage grace period.
  first_usage=0
  usage_state_exists=0
  if [ -n "$safe_id" ]; then
    usage_state="/tmp/${USAGE_STATE_PREFIX}-${safe_id}"
    if [ ! -f "$usage_state" ]; then
      first_usage=1
    else
      usage_state_exists=1
      usage_created=$(head -1 "$usage_state" 2>/dev/null)
      case "$usage_created" in *[!0-9]*|"") usage_created="" ;; esac
      if [ -n "$usage_created" ] && [ "$((_now - usage_created))" -lt "$USAGE_FIRST_WINDOW_S" ] 2>/dev/null; then
        first_usage=1
      fi
    fi
  else
    first_usage=1
  fi

  # 5h window (18000s total)
  if [ -n "$rl_5h_pct" ] && [ -n "$rl_5h_reset" ]; then
    result_5h=$(should_show_window "$rl_5h_pct" "$rl_5h_reset" 18000 "$first_usage")
    if [ -n "$result_5h" ]; then
      show_5h=1
      rl_5h_pct_int=$(echo "$result_5h" | sed -n '1p')
      remaining_5h=$(echo "$result_5h" | sed -n '2p')
    fi
  fi

  # 7d window (604800s total)
  if [ -n "$rl_7d_pct" ] && [ -n "$rl_7d_reset" ]; then
    result_7d=$(should_show_window "$rl_7d_pct" "$rl_7d_reset" 604800 "$first_usage")
    if [ -n "$result_7d" ]; then
      show_7d=1
      rl_7d_pct_int=$(echo "$result_7d" | sed -n '1p')
      remaining_7d=$(echo "$result_7d" | sed -n '2p')
    fi
  fi

  # Create state file only once a window has actually rendered
  if [ "$usage_state_exists" -eq 0 ] && [ -n "$safe_id" ] \
     && { [ "$show_5h" -eq 1 ] || [ "$show_7d" -eq 1 ]; }; then
    printf '%s\n' "$_now" > "$usage_state"
  fi
fi

# ─── Line 1: branch, diff, model, context, tpm ───

if [ -n "$branch" ]; then
  printf "\033[36m⌥ %s${reset}" "$branch"
  printf "%b" "$diff_stat"
  printf "%s" "$sep"
fi
printf "\033[38;5;252m✦ %s${reset}" "$model"
if [ "$ctx_size" -ge 1000000 ] 2>/dev/null; then
  printf " \033[38;5;252m1M${reset}"
fi
printf "${sep}${ctx_color}%s %s%%${reset}" "$bar" "$used"
if [ "$tpm" -gt 0 ]; then
  if [ "$tpm" -ge 100000 ]; then
    tpm_display="$((tpm / 1000))k"
  elif [ "$tpm" -ge 1000 ]; then
    tpm_display="$((tpm / 1000)).$((tpm % 1000 / 100))k"
  else
    tpm_display="$tpm"
  fi
  if [ "$tpm" -ge 20000 ]; then
    bolt="\033[38;5;57mϟ${dim}"   # deep violet
  elif [ "$tpm" -ge 10000 ]; then
    bolt="\033[91mϟ${dim}"        # red
  elif [ "$tpm" -ge 5000 ]; then
    bolt="\033[38;5;209mϟ${dim}"  # orange
  elif [ "$tpm" -ge 1000 ]; then
    bolt="\033[93mϟ${dim}"        # yellow
  else
    bolt="ϟ"
  fi
  printf "${sep}${dim}${bolt} %s tpm${reset}" "$tpm_display"
fi

# ─── Line 2: rate limit usage ───

if [ "$show_5h" -eq 1 ] || [ "$show_7d" -eq 1 ]; then
  printf '\n'

  if [ "$show_5h" -eq 1 ]; then
    rl_5h_color=$(usage_color "$rl_5h_pct_int")
    rl_5h_vcolor=$(usage_value_color "$rl_5h_pct_int")
    countdown_5h=$(fmt_countdown "$remaining_5h")
    printf "${rl_5h_color}5h ${rl_5h_vcolor}%s%%${reset} \033[2;38;5;249m%s${reset}" "$rl_5h_pct_int" "$countdown_5h"
  fi

  if [ "$show_7d" -eq 1 ]; then
    [ "$show_5h" -eq 1 ] && printf "$sep"
    rl_7d_color=$(usage_color "$rl_7d_pct_int")
    rl_7d_vcolor=$(usage_value_color "$rl_7d_pct_int")
    countdown_7d=$(fmt_countdown "$remaining_7d")
    printf "${rl_7d_color}7d ${rl_7d_vcolor}%s%%${reset} \033[2;38;5;249m%s${reset}" "$rl_7d_pct_int" "$countdown_7d"
  fi
fi

