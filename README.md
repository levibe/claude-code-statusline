# claude-code-statusline

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![POSIX shell](https://img.shields.io/badge/Shell-POSIX-green.svg)](statusline.sh)
[![macOS / Linux](https://img.shields.io/badge/macOS_|_Linux-compatible-lightgrey.svg)]()

A clean, opinionated statusline for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

```
⌥ main  +42 -7  ✦ Opus 4.6  ▓▓▓░░ 58%  ⚡1.2k tpm
```


## Indicators

| Indicator | Example | Why |
|-----------|---------|-----|
| Branch | `⌥ main` | Active branch |
| Diff | `+42 -7` | Commit before new work |
| Model | `✦ Opus 4.6` | Active model |
| Context | `▓▓▓░░ 58%` | Stay under 50% for best results |
| Throughput | `⚡ 1.2k tpm` | How fast you're going |


## Requirements

- [`jq`](https://jqlang.github.io/jq/) — JSON parsing
- `git` — branch and diff information

`brew install jq git` or `apt install jq git`


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


## Limitations

- Subagent token usage is not tracked (not exposed by Claude Code)


## Notes

- Works in empty repos, detached HEAD, and normal branches
- Tracks text diffs, binary file changes, and untracked files
- Caps untracked line counting at 10k to avoid slowdowns on large repos
- Uses `--no-optional-locks` on all git calls to prevent lock contention
- Context bar color shifts from dim to yellow-green to yellow to orange as usage increases
- POSIX shell — no bash required


## Contributing

[Issues and feature requests](https://github.com/levibe/claude-code-statusline/issues)


## License

[MIT](LICENSE)
