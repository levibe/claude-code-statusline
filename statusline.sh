#!/bin/sh
# Line 1: ⌥ branch  +N -N  ✦ model  ██▒░░ N%  ϟ N tpm
# Line 2: 5h N% XhYm  7d N% XdYh  cache Nm   (rate limits shown when on pace / ≥75%; cache when ≤10m left or cold)

TPM_WINDOW_MS=300000     # 5 minutes
TPM_WINDOW_MIN_MS=60000  # floor: never divide a single early response by a few seconds
TPM_TAIL_BYTES=16777216  # bytes read from the end of each transcript file
MODEL_STATE_PREFIX="claude-code-statusline-model"
USAGE_STATE_PREFIX="claude-code-statusline-usage"
USAGE_FIRST_WINDOW_S=5   # seconds to show rate limits on first invocation
CACHE_SHOW_S=600         # show the prompt cache countdown at or below this many seconds left

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
  "duration_ms=\(.cost.total_duration_ms // 0 | floor | @sh)",
  "rl_5h_pct=\(.rate_limits.five_hour.used_percentage // "" | @sh)",
  "rl_5h_reset=\(.rate_limits.five_hour.resets_at // "" | @sh)",
  "rl_7d_pct=\(.rate_limits.seven_day.used_percentage // "" | @sh)",
  "rl_7d_reset=\(.rate_limits.seven_day.resets_at // "" | @sh)",
  "cache_warm=\(.prompt_cache.warm // "" | @sh)",
  "cache_expires=\(.prompt_cache.expires_at | if type == "number" then floor else 0 end | @sh)"
')"

# Defaults if jq fails or fields are missing
cwd=${cwd:-}; session_id=${session_id:-}; transcript_path=${transcript_path:-}
used=${used:-0}; model=${model:-unknown}; ctx_size=${ctx_size:-0}
duration_ms=${duration_ms:-0}
rl_5h_pct=${rl_5h_pct:-}; rl_5h_reset=${rl_5h_reset:-}
rl_7d_pct=${rl_7d_pct:-}; rl_7d_reset=${rl_7d_reset:-}
cache_warm=${cache_warm:-}; cache_expires=${cache_expires:-}

# Validate numeric fields
case "$rl_5h_reset" in ""|*[!0-9]*) rl_5h_reset="" ;; esac
case "$rl_7d_reset" in ""|*[!0-9]*) rl_7d_reset="" ;; esac
case "$rl_5h_pct" in ""|*[!0-9.]*|*.*.*) rl_5h_pct="" ;; esac
case "$rl_7d_pct" in ""|*[!0-9.]*|*.*.*) rl_7d_pct="" ;; esac
# expires_at is null (jq → 0) when the last response reported no cache tokens
case "$cache_expires" in ""|0|*[!0-9]*) cache_expires="" ;; esac

# Validate model name: must match "Name N" or "Name N.N" (e.g. "Fable 5", "Opus 4.6", "Haiku 4.5")
# Garbled names from Claude Code (e.g. "Op.6") are treated as unknown so they don't pollute the cache
case "$model" in
  unknown) ;;
  *) echo "$model" | grep -qE '^[A-Z][a-z]+ [0-9]+(\.[0-9]+)?$' || model="unknown" ;;
esac

# Session-scoped state key (used by model cache and sliding window TPM)
safe_id=$(printf '%s' "$session_id" | tr -dc 'a-zA-Z0-9_-')

# Indicators to hide, from CLAUDE_STATUSLINE_HIDE: a comma-separated list of
# names (branch, diff, model, context, tpm, limits, cache). Spaces are
# tolerated and unknown names are ignored. A hidden indicator also skips the
# work behind it.
hide_list=",$(printf '%s' "${CLAUDE_STATUSLINE_HIDE:-}" | tr -d ' '),"
hidden() {
  case "$hide_list" in *,"$1",*) return 0 ;; esac
  return 1
}

# Middle-truncate $1 past 19 characters, keeping 9 per side so a full ticket
# id (PRO-14555) survives the cut; 19 or fewer pass through untouched. sed's
# `.` is a byte in the C locale (what we get when Claude Code starts without
# LANG), which would split a multibyte character. So pin the C locale and
# spell out a UTF-8 character ourselves: one non-continuation byte followed
# by its continuation bytes (octal 200-277).
middle_truncate() {
  utf8_char=$(printf '[^\200-\277][\200-\277]*')
  printf '%s' "$1" | LC_ALL=C sed -E "s/^((${utf8_char}){9})(${utf8_char}){2,}((${utf8_char}){9})\$/\\1…\\4/"
}

# Temp file cleanup (set once, covers all temp files created below)
untracked_list=""
trap 'rm -f "$untracked_list"' EXIT

# Tokens per minute: a sliding window over the session transcript.
#
# The bolt measures work, not cost. Every assistant line in the transcript
# carries a timestamp and the API's usage block, and the sum of fresh input,
# cache writes, and cache reads is the size of the context that call saw.
# A message's work is how much that context grew over the previous message
# in the same file (the new tool results and user text) plus its output.
# The previous output is part of that growth, since it joins the context for
# the next call, so it is subtracted rather than counted twice. Re-reading
# existing context, or rewriting it to cache after the cache went cold,
# moves tokens between usage columns without growing the context, so it
# doesn't register; line 2 already shows the cache going cold. A shrink
# (compaction) counts as zero, and the first message in a file has nothing
# to diff against, so only its output counts. Claude Code also writes
# synthetic assistant entries after API errors, with an id and timestamp but
# no usage; anything with no input context is dropped so it can't become a
# zero baseline that makes the next real response look like all new work.
# Streaming repeats a message id
# once per content block with a growing output count, so each id is taken
# at its largest output. Subagent transcripts are summed the same way.
#
# The window is capped at the session's own lifetime (total_duration_ms,
# which restarts from zero on resume even though cost carries over), so a
# resumed session doesn't inherit pre-resume messages and a fresh one gets
# a real rate from its first response, with a one-minute floor so that
# first response isn't divided by a handful of seconds. The floor widens the
# divisor only, never the lookback, so a session resumed seconds ago still
# sees nothing from the previous process. Only files modified inside the
# window are parsed, and only their tails; assistant lines are a few percent
# of a transcript's bytes, so grep narrows the input before jq parses it. A
# busy five minutes can write several MB, hence the 16MB tail.
#
# The cutoff is a UTC ISO-8601 string compared lexically against the
# transcript's timestamps (always UTC with a Z suffix). jq 1.6, still what
# apt ships, parses ISO dates in local time, so no date parsing happens in jq.
tpm=0
if ! hidden tpm && [ -n "$transcript_path" ] && [ "$duration_ms" -gt 0 ] 2>/dev/null; then
  lookback_ms=$TPM_WINDOW_MS
  [ "$duration_ms" -lt "$lookback_ms" ] && lookback_ms=$duration_ms
  window_ms=$lookback_ms
  [ "$window_ms" -lt "$TPM_WINDOW_MIN_MS" ] && window_ms=$TPM_WINDOW_MIN_MS
  # BSD find documents rounding file age up to whole minutes, so look one
  # minute past the window; the timestamp cutoff below enforces the edge.
  window_files=$(find "$transcript_path" "${transcript_path%.jsonl}/subagents" \
    -maxdepth 1 -name '*.jsonl' -mmin "-$((TPM_WINDOW_MS / 60000 + 1))" 2>/dev/null)
  cutoff_s=$(( $(date +%s) - lookback_ms / 1000 ))
  # BSD date takes -r <epoch>, GNU date takes -d @<epoch>. The .000Z suffix
  # keeps a fractional timestamp in the cutoff second from sorting below it.
  cutoff=$(date -u -r "$cutoff_s" +%Y-%m-%dT%H:%M:%S.000Z 2>/dev/null \
    || date -u -d "@$cutoff_s" +%Y-%m-%dT%H:%M:%S.000Z 2>/dev/null)
  # An empty cutoff would admit the whole tail, so require one
  if [ -n "$window_files" ] && [ -n "$cutoff" ]; then
    window_tokens=$(printf '%s\n' "$window_files" | while IFS= read -r f; do
        # dd with a 1MB block skip, not tail -c: BSD tail walks the whole
        # file for a byte count, which costs ~0.3s on a 13MB transcript.
        size=$(wc -c < "$f")
        if [ "$size" -gt "$TPM_TAIL_BYTES" ] 2>/dev/null; then
          dd if="$f" bs=1048576 skip=$(( (size - TPM_TAIL_BYTES) / 1048576 )) 2>/dev/null
        else
          cat "$f"
        fi | grep -a -F '"type":"assistant"' | jq -nR --arg cutoff "$cutoff" '
          [ inputs | fromjson? | select(.type == "assistant") | .message as $m
            | select($m.id != null and (.timestamp | type) == "string"
                     and (.timestamp | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T.*Z$")))
            | { id: $m.id, ts: .timestamp,
                ctx: (($m.usage.input_tokens // 0) + ($m.usage.cache_creation_input_tokens // 0)
                      + ($m.usage.cache_read_input_tokens // 0)),
                out: ($m.usage.output_tokens // 0) }
            | select(.ctx > 0) ]
          | group_by(.id) | map(max_by(.out)) | sort_by(.ts)
          | [ range(length) as $i | .[$i] + { prev: (if $i > 0 then .[$i - 1] else null end) } ]
          | map(select(.ts >= $cutoff)
                | .out + (if .prev == null then 0
                          else ([.ctx - .prev.ctx - .prev.out, 0] | max) end))
          | add // 0
        ' 2>/dev/null
      done | awk '{ s += $1 } END { print s + 0 }')
    case "$window_tokens" in ""|*[!0-9]*) window_tokens=0 ;; esac
    tpm=$(( window_tokens * 60000 / window_ms ))
  fi
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

# Git branch + uncommitted diff stats (tracked + untracked).
# Skipped entirely when both are hidden; the diff scan alone when only diff is.
branch=""
diff_stat=""
worktree_name=""          # worktree folder name, only when it differs from the branch
worktree_display=""       # worktree name as rendered beside the branch (may be truncated)
branch_display=""         # branch as rendered beside the worktree name (may be truncated)
branch_glyph="⌥"          # main checkout
branch_color="\033[36m"   # cyan
if [ -n "$cwd" ] && { ! hidden branch || ! hidden diff; }; then
  branch=$(git --no-optional-locks -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)
  # Detached HEAD: show short SHA instead of literal "HEAD"
  [ "$branch" = "HEAD" ] && branch=$(git --no-optional-locks -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  # Empty repo (no commits): fall back to symbolic ref for branch name
  [ -z "$branch" ] && branch=$(git --no-optional-locks -C "$cwd" symbolic-ref --short HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    # Worktree indicator: in a linked worktree the per-worktree git dir
    # (.git/worktrees/<name>) differs from the shared --git-common-dir (.git);
    # in the main checkout they're identical. Covers nested, sibling, and
    # detached-HEAD worktrees regardless of whether cwd is the top or a subdir.
    # --path-format=absolute forces --git-dir and --git-common-dir to the same
    # (absolute) form; without it, from a subdir of the main checkout git prints
    # git-dir absolute but common-dir relative, so the string compare below would
    # false-positive a plain main checkout as a worktree.
    if ! hidden branch; then
      gitpaths=$(git --no-optional-locks -C "$cwd" rev-parse --path-format=absolute --git-dir --git-common-dir --show-toplevel 2>/dev/null)
      gd=$(printf '%s\n' "$gitpaths" | sed -n '1p')
      gcd=$(printf '%s\n' "$gitpaths" | sed -n '2p')
      if [ -n "$gd" ] && [ "$gd" != "$gcd" ]; then
        branch_glyph="⧉"                # worktree = a parallel copy of the repo
        branch_color="\033[38;5;182m"   # light mauve, distinct from the cyan main checkout
        # Worktree name = folder name of the worktree root (third rev-parse
        # output, --show-toplevel). Not the git-dir basename: that goes stale
        # after `git worktree move` and gains numeric suffixes on basename
        # collisions. Suppressed when it matches the branch (the common case)
        # so we don't render "feature feature".
        worktree_name=$(printf '%s\n' "$gitpaths" | sed -n '3p')
        worktree_name=${worktree_name##*/}
        # Three folder spellings carry no information the branch doesn't, so
        # they collapse too:
        #   - the branch with slashes flattened to dashes (fix/tpm -> fix-tpm)
        #   - Claude Code's own layout, .claude/worktrees/<name> on branch
        #     worktree-<name> (it already turns slashes into "+" on both sides)
        #   - a sibling folder prefixed with the repo name (myrepo-fix-tpm),
        #     the repo being the main checkout that owns --git-common-dir
        # A collision suffix (fix-tpm-2) deliberately does not: it's the one
        # thing that tells two worktrees on the same branch apart.
        norm_branch=$(printf '%s' "$branch" | tr '/' '-')
        repo_name=${gcd%/.git}
        repo_name=${repo_name##*/}
        repo_name=${repo_name%.git}
        case "$worktree_name" in
          "$norm_branch" | "${branch#worktree-}" | "${repo_name}-${norm_branch}")
            worktree_name="" ;;
        esac
        # Different names render as a pair; middle-truncate both so the pair
        # can't blow out the line. The tail is kept, so a collision suffix
        # survives the cut.
        if [ -n "$worktree_name" ]; then
          worktree_display=$(middle_truncate "$worktree_name")
          branch_display=$(middle_truncate "$branch")
        fi
      fi
    fi
    if ! hidden diff; then
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
        diff_stat=""
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
fi

# Rate limit visibility (each window shown independently)
show_5h=0
show_7d=0
rl_5h_pct_int=0
rl_7d_pct_int=0
remaining_5h=0
remaining_7d=0

if ! hidden limits && { [ -n "$rl_5h_pct" ] || [ -n "$rl_7d_pct" ]; }; then
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

# Prompt cache state. Warmth is computed from expires_at against the clock
# rather than trusting `warm`: Claude Code re-runs the script the moment a warm
# cache reaches expires_at, but the payload it hands over may still say warm.
# Hidden while comfortably warm (> CACHE_SHOW_S left) or when there is no data.
cache_seg=""
if ! hidden cache && [ -n "$cache_expires" ]; then
  _now=${_now:-$(date +%s)}
  cache_left=$((cache_expires - _now))
  if [ "$cache_warm" != "true" ] || [ "$cache_left" -le 0 ]; then
    cache_seg="\033[38;5;63mcache cold"          # blue
  elif [ "$cache_left" -le "$CACHE_SHOW_S" ]; then
    if [ "$cache_left" -lt 120 ]; then
      cache_color="\033[91m"                       # red: under 2m
    elif [ "$cache_left" -lt 300 ]; then
      cache_color="\033[38;5;208m"                 # orange: under 5m
    else
      cache_color="\033[93m"                       # yellow: 5m to 10m
    fi
    if [ "$cache_left" -lt 60 ]; then
      cache_countdown="<1m"    # a refresh tick can't support second precision
    else
      cache_countdown=$(fmt_countdown "$cache_left")
    fi
    cache_seg="${cache_color}cache ${cache_countdown}"
  fi
fi

# ─── Line 1: branch, diff, model, context, tpm ───

# emit FORMAT [ARG...]: print one segment, separated from the previous one
line1_empty=1
emit() {
  if [ "$line1_empty" -eq 1 ]; then line1_empty=0; else printf '%s' "$sep"; fi
  printf "$@"
}

if ! hidden branch && [ -n "$branch" ]; then
  if [ -n "$worktree_name" ]; then
    # Worktree name (always mauve here) leads; branch trails dimmed
    emit "${branch_color}${branch_glyph} %s${reset} ${dim}%s${reset}" "$worktree_display" "$branch_display"
  else
    emit "${branch_color}${branch_glyph} %s${reset}" "$branch"
  fi
fi
if [ -n "$diff_stat" ]; then
  emit '%b' "$diff_stat"
fi
if ! hidden model; then
  emit "\033[38;5;252m✦ %s${reset}" "$model"
  if [ "$ctx_size" -ge 1000000 ] 2>/dev/null; then
    printf " \033[38;5;252m1M${reset}"
  fi
fi
if ! hidden context; then
  emit "${ctx_color}%s %s%%${reset}" "$bar" "$used"
fi
if [ "$tpm" -gt 0 ]; then
  if [ "$tpm" -ge 100000000 ]; then
    tpm_display="$((tpm / 1000000))M"
  elif [ "$tpm" -ge 1000000 ]; then
    tpm_display="$((tpm / 1000000)).$((tpm % 1000000 / 100000))M"
  elif [ "$tpm" -ge 100000 ]; then
    tpm_display="$((tpm / 1000))k"
  elif [ "$tpm" -ge 1000 ]; then
    tpm_display="$((tpm / 1000)).$((tpm % 1000 / 100))k"
  else
    tpm_display="$tpm"
  fi
  if [ "$tpm" -ge 1000000 ]; then
    bolt="\033[38;5;198mϟ${dim}"  # hot pink — ludicrous tier, likely a measurement glitch
  elif [ "$tpm" -ge 20000 ]; then
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
  emit "${dim}${bolt} %s tpm${reset}" "$tpm_display"
fi

# ─── Line 2: rate limit usage, prompt cache ───

if [ "$show_5h" -eq 1 ] || [ "$show_7d" -eq 1 ] || [ -n "$cache_seg" ]; then
  [ "$line1_empty" -eq 0 ] && printf '\n'

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

  if [ -n "$cache_seg" ]; then
    { [ "$show_5h" -eq 1 ] || [ "$show_7d" -eq 1 ]; } && printf "$sep"
    printf "%b${reset}" "$cache_seg"
  fi
fi

