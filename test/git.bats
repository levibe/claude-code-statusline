#!/usr/bin/env bats

load 'helpers'

# ─── Git integration ───

@test "git: shows branch name" {
  TEST_GIT_REPO=$(mktemp -d)
  git -C "$TEST_GIT_REPO" init -b test-branch >/dev/null 2>&1
  git -C "$TEST_GIT_REPO" -c user.name=test -c user.email=test@test commit --allow-empty -m "init" >/dev/null 2>&1
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_GIT_REPO"
  [[ "$(plain)" == *"⌥ test-branch"* ]]
}

@test "git: shows diff stats for tracked changes" {
  TEST_GIT_REPO=$(mktemp -d)
  git -C "$TEST_GIT_REPO" init -b main >/dev/null 2>&1
  git -C "$TEST_GIT_REPO" -c user.name=test -c user.email=test@test commit --allow-empty -m "init" >/dev/null 2>&1
  printf 'line1\nline2\nline3\n' > "$TEST_GIT_REPO/file.txt"
  git -C "$TEST_GIT_REPO" add file.txt
  git -C "$TEST_GIT_REPO" -c user.name=test -c user.email=test@test commit -m "add file" >/dev/null 2>&1
  printf 'changed\nline2\nline3\nnew\n' > "$TEST_GIT_REPO/file.txt"
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_GIT_REPO"
  # 1 insertion (+new line, +changed), 1 deletion (-line1)
  [[ "$(plain)" == *"+2"* ]]
  [[ "$(plain)" == *"-1"* ]]
}

@test "git: counts untracked file lines" {
  TEST_GIT_REPO=$(mktemp -d)
  git -C "$TEST_GIT_REPO" init -b main >/dev/null 2>&1
  git -C "$TEST_GIT_REPO" -c user.name=test -c user.email=test@test commit --allow-empty -m "init" >/dev/null 2>&1
  printf 'a\nb\nc\n' > "$TEST_GIT_REPO/untracked.txt"
  # Must run from repo dir: git ls-files outputs relative paths that grep reads from cwd
  cd "$TEST_GIT_REPO"
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_GIT_REPO"
  [[ "$(plain)" == *"+3"* ]]
}

@test "git: detached HEAD shows short SHA" {
  TEST_GIT_REPO=$(mktemp -d)
  git -C "$TEST_GIT_REPO" init -b main >/dev/null 2>&1
  git -C "$TEST_GIT_REPO" -c user.name=test -c user.email=test@test commit --allow-empty -m "init" >/dev/null 2>&1
  local sha
  sha=$(git -C "$TEST_GIT_REPO" rev-parse --short HEAD)
  git -C "$TEST_GIT_REPO" checkout --detach HEAD >/dev/null 2>&1
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_GIT_REPO"
  [[ "$(plain)" == *"⌥ ${sha}"* ]]
}

@test "git: empty repo shows branch name" {
  TEST_GIT_REPO=$(mktemp -d)
  git -C "$TEST_GIT_REPO" init -b main >/dev/null 2>&1
  # No commits -- empty repo
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_GIT_REPO"
  [[ "$(plain)" == *"⌥ main"* ]]
}
