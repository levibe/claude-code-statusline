# claude-code-statusline

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![POSIX shell](https://img.shields.io/badge/Shell-POSIX-green.svg)](statusline.sh)
[![macOS / Linux](https://img.shields.io/badge/macOS_|_Linux-compatible-lightgrey.svg)]()

A minimal, configurable Claude Code statusline showing branch, diff, model, context, throughput, rate limit usage, and prompt cache state.

<img width="685" alt="A calm session: branch, diff, model, context, throughput" src="screenshots/default.png" />

## Design principles

- **Essential**: relevant indicators shown without extra labels, dividers, or empty states
- **Quiet**: supporting the main action, not competing with it
- **Terminal-first**: plain text symbols, no emojis


## What it shows

| Indicator | Description | Thresholds |
|---|---|---|
| **Branch** | Current git branch |  |
| **Diff** | Uncommitted additions and deletions |  |
| **Model** | Active Claude model |  |
| **Context** | Usage bar and percentage, scaled so 100% matches the actual autocompact point | Grey <35%, yellow-green 35%, yellow 50%, orange 75%, red 90% |
| **Throughput** | Tokens per minute | Grey <1k, yellow 1k, orange 5k, red 10k, violet 20k |
| **Rate limits** | 5-hour and 7-day usage with a countdown to reset. Hidden while on a comfortable pace | Shown on first use, when on pace to hit the limit, and at 75% and above. Grey <50%, yellow 50%, orange 75%, red 90% |
| **Prompt cache** | Countdown to the cached prefix going cold, then `cache cold` until the next response warms it. Hidden while warm with time to spare | Shown in the last 10 minutes and once cold. Yellow 10m, orange 5m, red 2m, blue when cold |

<img width="685" alt="Every indicator at once" src="screenshots/everything.png" />

*Every indicator at once: context near compaction, throughput in the top tier, both rate limit windows on pace, and the prompt cache about to go cold.*

Indicators without data are hidden rather than shown empty, and any indicator can be turned off for good. See [Configuration](#configuration).


## Install

1. Download the script:

```bash
curl -o ~/.claude/statusline.sh https://raw.githubusercontent.com/levibe/claude-code-statusline/main/statusline.sh && chmod +x ~/.claude/statusline.sh
```

Or clone and symlink: `git clone https://github.com/levibe/claude-code-statusline && ln -s claude-code-statusline/statusline.sh ~/.claude/statusline.sh`

2. Add to your `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh",
    "refreshInterval": 30
  }
}
```

`refreshInterval` re-runs the script every 30 seconds while the session is idle so the prompt cache countdown keeps ticking. Without it, the countdown still updates on every event and still flips to cold on time. It just stays fixed between events.

3. Restart Claude Code.


## Configuration

Hide indicators you don't want by setting `CLAUDE_STATUSLINE_HIDE` to a comma-separated list of names. Prefix the command in `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "CLAUDE_STATUSLINE_HIDE=tpm ~/.claude/statusline.sh"
  }
}
```

Or add it to the `env` block in the same file, which the statusline inherits.

| Name | Hides |
|---|---|
| `branch` | Branch name and worktree marker |
| `diff` | Uncommitted additions and deletions |
| `model` | Model name and 1M marker |
| `context` | Context usage bar and percentage |
| `tpm` | Throughput (tokens per minute) |
| `limits` | 5-hour and 7-day rate limits |
| `cache` | Prompt cache countdown and cold state |

Unknown names are ignored. A hidden indicator also skips the work behind it, so hiding `diff` avoids the git diff scan and hiding `tpm` avoids reading the session transcript.


## Requirements

- [`jq`](https://jqlang.github.io/jq/): JSON parsing
- `git`: branch and diff information

`brew install jq git` or `apt install jq git`


## Notes

- Tracks text diffs, untracked files, and binary file changes (binary files count as +1 added or -1 removed)
- Caps line counting at 10k to avoid slowdowns on large diffs
- Throughput counts tokens added to the conversation plus model output over the last 5 minutes of the transcript, subagents included; re-reading or re-caching existing context is not new work and does not count
- Shows short SHA on detached HEAD; falls back to symbolic ref in empty repos
- Marks a linked git worktree with a distinct icon and color, separating it from the main checkout. When the worktree's folder name differs from its branch, both are shown, each middle-truncated past 19 characters. Flattened slashes, Claude Code's own `worktree-<name>` branch prefix, and a repo-name folder prefix don't count as a difference
- Computes prompt cache warmth from `expires_at` against the clock rather than trusting the `warm` flag, which can lag when Claude Code re-runs the script at the moment of expiry (requires Claude Code 2.1.251 or later for `prompt_cache`)
- Uses `--no-optional-locks` on all git calls to prevent lock contention
- Fixes model name bleeding across sessions ([Claude Code bug](https://github.com/anthropics/claude-code/issues/19570))
- Validates model names to filter garbled input from Claude Code


## Changelog

[CHANGELOG.md](CHANGELOG.md)


## Development

Run the test suite:

```bash
brew install bats-core  # https://bats-core.readthedocs.io/en/stable/installation.html
bats test/
```

Regenerate the README screenshots (needs Chrome or Chromium; set `CHROME=` to point at one if it isn't found):

```bash
screenshots/generate.sh            # all cases
screenshots/generate.sh default    # one case
```

Each case in `screenshots/generate.sh` feeds a hand-built payload to `statusline.sh` and renders the output in the style of Claude Code in Cursor's terminal.


## Contributing

[Issues and feature requests](https://github.com/levibe/claude-code-statusline/issues)


## License

[MIT](LICENSE)
