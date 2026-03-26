# claude-code-statusline

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![POSIX shell](https://img.shields.io/badge/Shell-POSIX-green.svg)](statusline.sh)
[![macOS / Linux](https://img.shields.io/badge/macOS_|_Linux-compatible-lightgrey.svg)]()

A minimal Claude Code statusline with context usage, branch, model, and diff info. Built for Max subscribers who don't hit their session limits.

<img width="685" height="162" alt="claude-code-statusline-github" src="https://github.com/user-attachments/assets/37575117-a394-4d81-9204-1d49f6b1f46e" />


## Design principles

- **Essential** – relevant indicators shown without extra labels, dividers, or empty states
- **Quiet** – supporting the main action, not competing with it
- **Terminal-first** – plain text symbols, no emojis


## Indicators

| Indicator | Example | Why |
|-----------|---------|-----|
| Branch | `⌥ main` | Active branch |
| Diff | `+42 -7` | Commit before new work |
| Model | `✦ Opus 4.6` | Active model |
| Context | `▓▓░░░ 43%` | Stay under 50% for best results |
| Throughput | `ϟ 1.2k tpm` | How fast you're going |


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

- [`jq`](https://jqlang.github.io/jq/) — JSON parsing
- `git` — branch and diff information

`brew install jq git` or `apt install jq git`


## Limitations

- Subagent token usage is not tracked


## Notes

- Context bar color shifts from grey to yellow-green to yellow to orange as usage increases
- Tracks text diffs, untracked files, and binary file changes (binary files count as +1 added or -1 removed)
- TPM uses a 5-minute sliding window
- Fixes model name bleeding across sessions ([CC bug](https://github.com/anthropics/claude-code/issues/19570))
- Caps line counting at 10k to avoid slowdowns on large diffs
- Works in empty repos, detached HEAD, and normal branches
- Uses `--no-optional-locks` on all git calls to prevent lock contention


## Contributing

[Issues and feature requests](https://github.com/levibe/claude-code-statusline/issues)


## License

[MIT](LICENSE)
