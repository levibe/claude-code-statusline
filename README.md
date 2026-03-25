# claude-code-statusline

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![POSIX shell](https://img.shields.io/badge/Shell-POSIX-green.svg)](statusline.sh)
[![macOS / Linux](https://img.shields.io/badge/macOS_|_Linux-compatible-lightgrey.svg)]()

A minimal Claude Code statusline with context usage, branch, model, and diff info.

<img width="640" height="91" src="https://github.com/user-attachments/assets/0ab768af-caf8-4a3f-9800-a07621fa3df7" />

## What's included

| Indicator | Example | Why |
|-----------|---------|-----|
| Branch | `⌥ main` | Active branch |
| Diff | `+42 -7` | Commit before new work |
| Model | `✦ Opus 4.6` | Active model |
| Context | `▓▓▓░░ 58%` | Stay under 50% for best results |
| Throughput | `⚡ 1.2k tpm` | How fast you're going |


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

- Context bar color shifts from dim to yellow-green to yellow to orange as usage increases
- Tracks text diffs, binary file changes, and untracked files
- Caps untracked line counting at 10k to avoid slowdowns on large diffs
- Works in empty repos, detached HEAD, and normal branches
- Uses `--no-optional-locks` on all git calls to prevent lock contention
- TPM uses a 5-minute sliding window for real-time throughput
- Fixes model name bleeding across sessions ([CC bug](https://github.com/anthropics/claude-code/issues/19570))


## Contributing

[Issues and feature requests](https://github.com/levibe/claude-code-statusline/issues)


## License

[MIT](LICENSE)
