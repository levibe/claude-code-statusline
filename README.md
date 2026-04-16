# claude-code-statusline

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![POSIX shell](https://img.shields.io/badge/Shell-POSIX-green.svg)](statusline.sh)
[![macOS / Linux](https://img.shields.io/badge/macOS_|_Linux-compatible-lightgrey.svg)]()

A minimal Claude Code statusline showing branch, diff, model, context, throughput, and rate limit usage.

<img width="685" height="100" alt="Screenshot" src="https://github.com/user-attachments/assets/5ce0a134-6b07-4754-8b9c-dca3e8fc6574" />


## Design principles

- **Essential** – relevant indicators shown without extra labels, dividers, or empty states
- **Quiet** – supporting the main action, not competing with it
- **Terminal-first** – plain text symbols, no emojis


## What it shows

|   |   |   |
|---|---|---|
| **Branch** | Current git branch |  |
| **Diff** | Uncommitted additions and deletions |  |
| **Model** | Active Claude model |  |
| **Context** | Usage bar and percentage, scaled so 100% matches the actual autocompact point | Grey <35%, yellow-green 35%, yellow 50%, orange 75%, red 90% |
| **Throughput** | Tokens per minute | Grey <1k, yellow 1k, orange 5k, red 10k, violet 20k |
| **Rate limits** | 5-hour and 7-day usage with countdown. Shown on first use, when on pace to hit the limit, and at or above 75%. Hidden means comfortable pace | Grey <50%, yellow 50%, orange 75%, red 90% |

Indicators without data are hidden rather than shown empty.


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
    "command": "~/.claude/statusline.sh"
  }
}
```

3. Restart Claude Code.


## Requirements

- [`jq`](https://jqlang.github.io/jq/) – JSON parsing
- `git` – branch and diff information

`brew install jq git` or `apt install jq git`


## Notes

- Tracks text diffs, untracked files, and binary file changes (binary files count as +1 added or -1 removed)
- Caps line counting at 10k to avoid slowdowns on large diffs
- TPM uses a 5-minute sliding window and includes subagent token usage
- Shows short SHA on detached HEAD; falls back to symbolic ref in empty repos
- Uses `--no-optional-locks` on all git calls to prevent lock contention
- Fixes model name bleeding across sessions ([CC bug](https://github.com/anthropics/claude-code/issues/19570))
- Validates model names to filter garbled input from Claude Code


## Changelog

[CHANGELOG.md](CHANGELOG.md)


## Development

Run the test suite:

```bash
brew install bats-core  # https://bats-core.readthedocs.io/en/stable/installation.html
bats test/
```


## Contributing

[Issues and feature requests](https://github.com/levibe/claude-code-statusline/issues)


## License

[MIT](LICENSE)
