#!/usr/bin/env bats

load 'helpers'

@test "name: off by default, even with a matching registry" {
  make_registry "$TEST_SID" extension-69
  CLAUDE_STATUSLINE_SHOW=session run run_sl
  [ "$(plain)" = "# extension-69  ✦ Opus 4.6  █░░░░ 25%" ]
  run run_sl
  [ "$(plain)" = "✦ Opus 4.6  █░░░░ 25%" ]
}

@test "name: SHOW tolerates spaces and ignores unknown names" {
  make_registry "$TEST_SID" extension-69
  CLAUDE_STATUSLINE_SHOW="nope, session" run run_sl
  [ "$(plain)" = "# extension-69  ✦ Opus 4.6  █░░░░ 25%" ]
  CLAUDE_STATUSLINE_SHOW=sessionx run run_sl
  [ "$(plain)" = "✦ Opus 4.6  █░░░░ 25%" ]
}

@test "name: leads line 1 with the name from the matching registry file" {
  make_registry "other-session" decoy 0 200
  make_registry "$TEST_SID" extension-69 1 100
  CLAUDE_STATUSLINE_SHOW=session run run_sl
  [ "$(plain)" = "# extension-69  ✦ Opus 4.6  █░░░░ 25%" ]
}

@test "name: reads the registry fresh on every run" {
  make_registry "$TEST_SID" extension-69
  CLAUDE_STATUSLINE_SHOW=session run run_sl
  [ "$(plain)" = "# extension-69  ✦ Opus 4.6  █░░░░ 25%" ]
  make_registry "$TEST_SID" renamed
  CLAUDE_STATUSLINE_SHOW=session run run_sl
  [ "$(plain)" = "# renamed  ✦ Opus 4.6  █░░░░ 25%" ]
}

@test "name: no matching registry file shows nothing" {
  make_registry "other-session" decoy
  CLAUDE_STATUSLINE_SHOW=session run run_sl
  [ "$status" -eq 0 ]
  [ "$(plain)" = "✦ Opus 4.6  █░░░░ 25%" ]
}

@test "name: missing registry directory shows nothing" {
  CLAUDE_STATUSLINE_SHOW=session CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/none" run run_sl
  [ "$status" -eq 0 ]
  [ "$(plain)" = "✦ Opus 4.6  █░░░░ 25%" ]
}

@test "name: the newest updatedAt wins for a shared session id" {
  make_registry "$TEST_SID" stale 1 100
  make_registry "$TEST_SID" resumed 2 200
  CLAUDE_STATUSLINE_SHOW=session run run_sl
  [ "$(plain)" = "# resumed  ✦ Opus 4.6  █░░░░ 25%" ]
  make_registry "$TEST_SID" stale 1 300
  CLAUDE_STATUSLINE_SHOW=session run run_sl
  [ "$(plain)" = "# stale  ✦ Opus 4.6  █░░░░ 25%" ]
}

@test "name: no match never reads files from the working directory" {
  mkdir "$BATS_TEST_TMPDIR/cwd"
  printf '{"name":"leaked"}' > "$BATS_TEST_TMPDIR/cwd/package.json"
  make_registry "other-session" decoy
  cd "$BATS_TEST_TMPDIR/cwd"
  CLAUDE_STATUSLINE_SHOW=session run run_sl
  [ "$(plain)" = "✦ Opus 4.6  █░░░░ 25%" ]
}

@test "name: a config dir with a space still resolves" {
  CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/sp ace"
  make_registry "$TEST_SID" extension-69 1 100
  make_registry "$TEST_SID" spaced 2 200
  CLAUDE_STATUSLINE_SHOW=session run run_sl
  [ "$(plain)" = "# spaced  ✦ Opus 4.6  █░░░░ 25%" ]
}

@test "name: a long name is middle-truncated" {
  make_registry "$TEST_SID" abcdefghijklmnopqrstuvwxyz
  CLAUDE_STATUSLINE_SHOW=session run run_sl
  [ "$(plain)" = "# abcdefghi…rstuvwxyz  ✦ Opus 4.6  █░░░░ 25%" ]
}
