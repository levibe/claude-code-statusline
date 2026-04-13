# Changelog

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
