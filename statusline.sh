#!/bin/sh
# Status line: ⌥ branch  +N -N  ✦ model  ▓▓░░ N%  ⚡N tpm

TPM_STATE_PREFIX="claude-code-statusline-tpm"
TPM_WINDOW_MS=300000  # 5 minutes
MODEL_STATE_PREFIX="claude-code-statusline-model"

input=$(cat)

# Single jq call to extract all fields (floor handles potential floats)
eval "$(echo "$input" | jq -r '
  "cwd=\(.cwd // "" | @sh)",
  "session_id=\(.session_id // "" | @sh)",
  "used=\(.context_window.used_percentage // 0 | floor | @sh)",
  "model=\(.model.display_name // "unknown" | sub(" *\\(.*\\)"; "") | @sh)",
  "total_in=\(.context_window.total_input_tokens // 0 | floor | @sh)",
  "total_out=\(.context_window.total_output_tokens // 0 | floor | @sh)",
  "duration_ms=\(.cost.total_duration_ms // 0 | floor | @sh)"
')"

# Defaults if jq fails or fields are missing
cwd=${cwd:-}; session_id=${session_id:-}; used=${used:-0}; model=${model:-unknown}
total_in=${total_in:-0}; total_out=${total_out:-0}; duration_ms=${duration_ms:-0}

# Session-scoped state key (used by model cache and sliding window TPM)
safe_id=$(printf '%s' "$session_id" | tr -dc 'a-zA-Z0-9_-')

# Temp file cleanup (set once, covers all temp files created below)
tmpfile=""
untracked_list=""
trap 'rm -f "$tmpfile" "$untracked_list"' EXIT

# Tokens per minute (full-session average as default)
total_tokens=$((total_in + total_out))
if [ "$duration_ms" -gt 0 ]; then
  tpm=$(( (total_tokens * 60000) / duration_ms ))
else
  tpm=0
fi

# Per-session model cache — prevents global model changes in other sessions
# from affecting this session's display before it has new activity.
#
# State file format (2 lines):
#   line 1: last known model string for this session
#   line 2: duration_ms at the time that model was recorded
#
# Update rule: only replace the cached model when duration_ms has increased,
# meaning this session processed a real assistant turn.
# A model change with no new turn will take effect on the next turn.
if [ -n "$safe_id" ]; then
  model_file="/tmp/${MODEL_STATE_PREFIX}-${safe_id}"
  if [ -f "$model_file" ]; then
    cached_model=$(head -1 "$model_file")
    cached_duration=$(tail -1 "$model_file")
    # Reject non-numeric cached_duration (e.g. from a corrupted/truncated file)
    cached_duration=$(printf '%s' "$cached_duration" | grep -E '^[0-9]+$' || echo 0)
    cached_duration=${cached_duration:-0}
    if [ "$duration_ms" -lt "$cached_duration" ] 2>/dev/null; then
      # duration_ms went backwards → session restarted; reset cache
      [ "$model" != "unknown" ] && printf '%s\n%s\n' "$model" "$duration_ms" > "$model_file"
    elif [ "$duration_ms" -gt "$cached_duration" ] 2>/dev/null && [ "$model" != "unknown" ]; then
      # New activity with a known model → update cache
      printf '%s\n%s\n' "$model" "$duration_ms" > "$model_file"
    else
      # No new activity, or model is unknown → keep cached model
      [ -n "$cached_model" ] && model="$cached_model"
    fi
  elif [ "$model" != "unknown" ]; then
    # First invocation for this session → initialize cache
    # Skip initialization if model is unknown (jq failure) to avoid caching a bad value
    printf '%s\n%s\n' "$model" "$duration_ms" > "$model_file"
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

# 5-char progress bar (each bar = 20%)
filled=$((used / 20))
[ "$used" -ge 95 ] && filled=5
[ "$filled" -gt 5 ] && filled=5
case $filled in
  0) bar="░░░░░" ;; 1) bar="▓░░░░" ;; 2) bar="▓▓░░░" ;; 3) bar="▓▓▓░░" ;; 4) bar="▓▓▓▓░" ;; 5) bar="▓▓▓▓▓" ;;
esac

# Context color gradient (no green/red to avoid clashing with diff stats)
if [ "$used" -ge 75 ]; then
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

printf "\033[36m⌥ %s${reset}" "$branch"
printf "%b" "$diff_stat"
printf "${sep}\033[38;5;252m✦ %s${reset}" "$model"
printf "${sep}${ctx_color}%s %s%%${reset}" "$bar" "$used"
if [ "$tpm" -gt 0 ]; then
  if [ "$tpm" -ge 10000 ]; then
    tpm_display="$((tpm / 1000))k"
  elif [ "$tpm" -ge 1000 ]; then
    tpm_display="$((tpm / 1000)).$((tpm % 1000 / 100))k"
  else
    tpm_display="$tpm"
  fi
  printf "${sep}${dim}⚡%s tpm${reset}" "$tpm_display"
fi
