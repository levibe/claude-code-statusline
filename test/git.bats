#!/usr/bin/env bats

load 'helpers'

# ─── Git integration ───

@test "git: shows branch name" {
  make_git_repo test-branch
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_GIT_REPO"
  [[ "$(plain)" == *"⌥ test-branch"* ]]
}

@test "git: shows diff stats for tracked changes" {
  make_git_repo
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
  make_git_repo
  printf 'a\nb\nc\n' > "$TEST_GIT_REPO/untracked.txt"
  # Must run from repo dir: git ls-files outputs relative paths that grep reads from cwd
  cd "$TEST_GIT_REPO"
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_GIT_REPO"
  [[ "$(plain)" == *"+3"* ]]
}

@test "git: detached HEAD shows short SHA" {
  make_git_repo
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

@test "git: no branch indicator outside git repo" {
  TEST_GIT_REPO=$(mktemp -d)
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_GIT_REPO"
  [[ "$(plain)" != *"⌥"* ]]
  [[ "$(plain)" == *"✦ Opus 4.6"* ]]
}

@test "git: main checkout uses the main-checkout glyph" {
  make_git_repo
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_GIT_REPO"
  [[ "$(plain)" == *"⌥ main"* ]]
  [[ "$(plain)" != *"⧉"* ]]
}

@test "git: linked worktree uses the worktree glyph" {
  make_git_repo
  make_worktree feature -b feature
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_WORKTREE"
  [[ "$(plain)" == *"⧉ feature"* ]]
  [[ "$(plain)" != *"⌥"* ]]
  # Worktree folder matches the branch, so the name is not shown twice
  [[ "$(plain)" != *"feature feature"* ]]
}

@test "git: shows the worktree name alongside the branch when they differ" {
  make_git_repo
  make_worktree wt-alpha -b feature
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_WORKTREE"
  [[ "$(plain)" == *"⧉ wt-alpha feature"* ]]
}

@test "git: shows the worktree name from a subdir of the worktree" {
  make_git_repo
  make_worktree wt-alpha -b feature
  mkdir -p "$TEST_WORKTREE/src"
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_WORKTREE/src"
  [[ "$(plain)" == *"⧉ wt-alpha feature"* ]]
}

@test "git: detached HEAD in a worktree still shows the worktree name" {
  make_git_repo
  make_worktree wt-alpha --detach
  local sha
  sha=$(git -C "$TEST_WORKTREE" rev-parse --short HEAD)
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_WORKTREE"
  [[ "$(plain)" == *"⧉ wt-alpha ${sha}"* ]]
}

@test "git: slashed branch is shown alongside the worktree name, not suppressed" {
  make_git_repo
  make_worktree foo -b feature/foo
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_WORKTREE"
  # Folder "foo" != branch "feature/foo" even after flattening slashes, so both render
  [[ "$(plain)" == *"⧉ foo feature/foo"* ]]
}

@test "git: folder matching the branch with slashes flattened is not a divergence" {
  make_git_repo
  make_worktree feature-foo -b feature/foo
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_WORKTREE"
  [[ "$(plain)" == *"⧉ feature/foo"* ]]
  [[ "$(plain)" != *"feature-foo"* ]]
}

@test "git: Claude Code worktree (.claude/worktrees/<name> on worktree-<name>) is not a divergence" {
  make_git_repo
  make_worktree_at "$TEST_GIT_REPO/.claude/worktrees/foo" -b worktree-foo
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_WORKTREE"
  [[ "$(plain)" == *"⧉ worktree-foo"* ]]
  [[ "$(plain)" != *"foo worktree-foo"* ]]
}

@test "git: Claude Code worktree with a plus-joined name is not a divergence" {
  make_git_repo
  # Claude Code writes feature/auth as feature+auth in both the folder and the branch
  make_worktree_at "$TEST_GIT_REPO/.claude/worktrees/feature+auth" -b worktree-feature+auth
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_WORKTREE"
  [[ "$(plain)" == *"⧉ worktree-feature+auth"* ]]
  [[ "$(plain)" != *"feature+auth worktree-feature+auth"* ]]
}

@test "git: sibling folder prefixed with the repo name is not a divergence" {
  make_git_repo
  make_worktree_at "${TEST_GIT_REPO}-feature" -b feature
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_WORKTREE"
  [[ "$(plain)" == *"⧉ feature"* ]]
  [[ "$(plain)" != *"-feature feature"* ]]
}

@test "git: repo-prefixed sibling with flattened slashes is not a divergence" {
  make_git_repo
  make_worktree_at "${TEST_GIT_REPO}-fix-tpm" -b fix/tpm
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_WORKTREE"
  [[ "$(plain)" == *"⧉ fix/tpm"* ]]
  [[ "$(plain)" != *"-fix-tpm fix/tpm"* ]]
}

@test "git: repo-prefixed sibling on a different branch still shows both names" {
  make_git_repo
  make_worktree_at "${TEST_GIT_REPO}-feature" -b hotfix
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_WORKTREE"
  # The folder is long enough to be middle-truncated, so match its kept tail
  [[ "$(plain)" == *"-feature hotfix"* ]]
  [[ "$(plain)" != *"⧉ hotfix"* ]]
}

@test "git: collision suffix on the folder is shown, so same-branch worktrees stay distinct" {
  make_git_repo
  make_worktree feature-2 -b feature
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_WORKTREE"
  [[ "$(plain)" == *"⧉ feature-2 feature"* ]]
}

@test "git: collision suffix plus flattened slashes still shows both names" {
  make_git_repo
  make_worktree fix-tpm-2 -b fix/tpm
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_WORKTREE"
  [[ "$(plain)" == *"⧉ fix-tpm-2 fix/tpm"* ]]
}

@test "git: digit-ending branch matching its folder exactly is not shown twice" {
  make_git_repo
  make_worktree fix-2 -b fix-2
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_WORKTREE"
  [[ "$(plain)" == *"⧉ fix-2"* ]]
  [[ "$(plain)" != *"fix-2 fix-2"* ]]
}

@test "git: long branch is middle-truncated when shown alongside the worktree name" {
  make_git_repo
  make_worktree wt-alpha -b feature/very-long-branch-name
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_WORKTREE"
  [[ "$(plain)" == *"⧉ wt-alpha feature/v…anch-name"* ]]
  [[ "$(plain)" != *"very-long-branch-name"* ]]
}

@test "git: long worktree name is middle-truncated too, keeping its collision suffix" {
  make_git_repo
  make_worktree feature-very-long-branch-name-2 -b feature/very-long-branch-name
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_WORKTREE"
  [[ "$(plain)" == *"⧉ feature-v…ch-name-2 feature/v…anch-name"* ]]
}

@test "git: truncation keeps a leading ticket id intact" {
  make_git_repo
  make_worktree wt-alpha -b PRO-14555-add-login-flow
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_WORKTREE"
  [[ "$(plain)" == *"⧉ wt-alpha PRO-14555…ogin-flow"* ]]
}

@test "git: multibyte branch truncates on character boundaries, not bytes" {
  make_git_repo
  make_worktree wt-alpha -b naïve-feature-branch-name
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_WORKTREE"
  [[ "$(plain)" == *"⧉ wt-alpha naïve-fea…anch-name"* ]]
}

@test "git: multibyte branch truncates on character boundaries in the C locale" {
  make_git_repo
  # ï sits at character 9, so a byte-counting cut lands inside it
  make_worktree wt-alpha -b abcdefghïjklmnopqrstuvwx
  LC_ALL=C run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_WORKTREE"
  [[ "$(plain)" == *"⧉ wt-alpha abcdefghï…pqrstuvwx"* ]]
}

@test "git: 19-char branch renders in full alongside the worktree name" {
  make_git_repo
  make_worktree wt-alpha -b abcdefghijklmnopqrs
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_WORKTREE"
  [[ "$(plain)" == *"⧉ wt-alpha abcdefghijklmnopqrs"* ]]
}

@test "git: 20-char branch is the shortest that truncates" {
  make_git_repo
  make_worktree wt-alpha -b abcdefghijklmnopqrst
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_WORKTREE"
  [[ "$(plain)" == *"⧉ wt-alpha abcdefghi…lmnopqrst"* ]]
}

@test "git: worktree name reflects the folder after git worktree move" {
  make_git_repo
  make_worktree wt-alpha -b feature
  # Internal git dir stays .git/worktrees/wt-alpha after the move; only
  # --show-toplevel tracks the new folder, which is why the script uses it
  git -C "$TEST_GIT_REPO" worktree move "$TEST_WORKTREE" "$TEST_GIT_REPO/.worktrees/wt-beta" >/dev/null 2>&1
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_GIT_REPO/.worktrees/wt-beta"
  [[ "$(plain)" == *"⧉ wt-beta feature"* ]]
  [[ "$(plain)" != *"wt-alpha"* ]]
}

@test "git: shows diff stats alongside the worktree name" {
  make_git_repo
  make_worktree wt-alpha -b feature
  printf 'a\nb\n' > "$TEST_WORKTREE/untracked.txt"
  # Must run from repo dir: git ls-files outputs relative paths that grep reads from cwd
  cd "$TEST_WORKTREE"
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_WORKTREE"
  [[ "$(plain)" == *"⧉ wt-alpha feature  +2"* ]]
}

@test "git: subdir of main checkout is not mistaken for a worktree" {
  make_git_repo
  mkdir -p "$TEST_GIT_REPO/subdir"
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_GIT_REPO/subdir"
  [[ "$(plain)" == *"⌥ main"* ]]
  [[ "$(plain)" != *"⧉"* ]]
}
