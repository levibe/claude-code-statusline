# Changelog

## 1.8.0

### Added

- Show the worktree's folder name in the branch segment when it differs from the branch (folder in mauve, branch dimmed alongside). Three spellings count as a match: the branch with slashes flattened (`fix-tpm` for `fix/tpm`), Claude Code's own `.claude/worktrees/<name>` on branch `worktree-<name>`, and a sibling folder prefixed with the repo name (`myrepo-fix-tpm`)
- Middle-truncate both names in that pair past 19 characters

## 1.7.0

### Added

- Show a prompt cache countdown on line 2: yellow from 10 minutes, orange under 5m, red under 2m, and `cache cold` in blue once it expires. Hidden while more than 10 minutes remain, and requires Claude Code 2.1.251 or later
- Add `CLAUDE_STATUSLINE_HIDE` to hide any indicators from a comma-separated list: `branch`, `diff`, `model`, `context`, `tpm`, `cache`, `limits`

### Fixed

- Compute TPM from the session transcript instead of the context-window snapshot. Fixes the inflated rate early in a session, the stuck non-zero rate on idle sessions, the stale rate after compaction, and the multi-million spike on resume
- Count only tokens added to the conversation plus output, so re-reading or rewriting context after the cache goes cold no longer counts as throughput

### Removed

- The sliding-window and subagent state files in `/tmp`, and the resume sentinel; the transcript is now the only source

## 1.6.0

### Added

- Mark a linked git worktree in the branch segment with a distinct icon and light-mauve color, distinguishing it from the main checkout at a glance

## 1.5.1

### Fixed

- Accept model names with a bare major version (e.g. "Fable 5"), which previously failed validation and displayed as "unknown"

## 1.5.0

### Added

- Format TPM values at or above 1M as `N.NM` with a hot-pink bolt color tier for high-throughput sessions
- Red color tier at 90%+ context usage to signal compaction is imminent (previous top tier was orange at 75%+)
- Respect `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` (1-100) when computing the effective context capacity

### Changed

- Context percentage now rescales so 100% matches the actual autocompact point instead of the raw window size. Displayed values will appear higher than before (e.g. 70% raw → 83% displayed on a 200k window) because Claude Code reserves ~33k tokens as an autocompact buffer. The old display suggested headroom that didn't exist

### Fixed

- Prevent spurious multi-million TPM readings after session resume by seeding the sliding window with a synthetic baseline and hiding the segment until a real post-resume rate is produced

## 1.4.0

### Added

- Show 1M context indicator after model name to disambiguate 200k and 1M context variants
- Use 4-shade progress bar (░▒▓█) for finer context usage granularity (20 visual steps instead of 5)

## 1.3.2

### Changed

- Display decimal precision for TPM values between 10k and 100k (e.g., "12.3k" instead of "12k")

## 1.3.1

### Fixed

- Hide branch indicator entirely in non-git directories instead of showing a lone icon

## 1.3.0

### Added

- Rate limit usage tracking for 5-hour and 7-day windows, shown on a second line
  - Smart visibility: shown on first session invocation, when on pace to hit the limit, or when usage exceeds 75%
  - Color-coded usage tiers (dim/yellow/orange/red) with rounded countdown to reset

### Fixed

- Fix bolt icon rendering as emoji on some terminals by using ϟ (koppa) text glyph

## 1.2.0

### Added

- Track subagent token usage in TPM calculation with mtime-based caching
- Add color tiers to TPM bolt indicator
- Add BATS test suite

### Fixed

- Fix wrong model name displaying when data from Claude Code is corrupted by adding model name format validation

## 1.1.0

### Added

- Sliding window TPM calculation using a 5-minute window for real-time throughput

### Fixed

- Fix model name bleeding across sessions

## 1.0.0

Initial release. Break out from dotfiles.

### Added

- Statusline showing branch, diff stats, model, context usage, and throughput
- Color-coded context bar with usage gradient
- POSIX shell compatibility
