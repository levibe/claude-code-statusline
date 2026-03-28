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

- **Branch** – current git branch
- **Diff** – uncommitted additions and deletions
- **Model** – active Claude model
- **Context** – usage bar and percentage. Grey under 35%, yellow-green under 50%, yellow under 75%, orange above. Start a new conversation before 50% for best results
- **Throughput** – tokens per minute. Grey under 1k, yellow at 1k, orange at 5k, red at 10k, violet at 20k
- **Rate limits** – 5-hour and weekly usage with countdown. Grey under 50%, yellow at 50%, orange at 75%, red at 90%. Shown on first use of each session, when on pace to hit the limit, and when over 75%. If hidden, you're within a comfortable pace

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
