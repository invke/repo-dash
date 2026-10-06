# repo-dash

A local gh-dash for a folder of repos: every repo with its branch, worktrees, dirty state, open PR, CI, reviews and the Claude desktop session parked in each worktree — in one fzf screen.

## Needs

- macOS (`open`, BSD `find`, the Claude desktop session store)
- `fzf` ≥ 0.59, `gh` (logged in), `jq`, `perl`, `curl`, VS Code's `code` on PATH
- system bash 3.2 is fine

## Setup

```bash
git clone git@github.com:invke/repo-dash.git ~/Repositories/repo-dash
alias rdp='~/Repositories/repo-dash/repo-dash.sh --active --pr --pick'
```

Optional `~/.config/repo-dash/config` (plain shell, sourced on start):

```bash
REPOS=~/Repositories          # where your repos live (default)
RD_ORG=paperkite              # only PRs from this GitHub org; unset for every org
RD_BASES="internal staging develop main master"   # first one on origin is the PR target
```

## Layout it expects

- Repos are **direct children** of `$REPOS` with a normal `.git` folder.
- Worktrees can live anywhere; ones outside `$REPOS` are flagged `⚠`.
- The workspaces tab lists `$REPOS/_<name>.code-workspace` (display name from an optional `_<name>.claude-code.json`).
- Claude session titles and ⚑ flags appear when worktrees have Claude desktop sessions; everything else works without.

## Use

Tabs: `1 repos` · `2 PRs` · `3 workspaces` · `4 parked`. The PRs tab lists every open PR of yours, grouped by what stands between it and merged — ready to merge, approved but not mergeable yet, changes requested, in review, drafts, stale (90+ days) — plus the ones waiting on your review, each with its merge state and how far it trails its target.

| key | | key | |
|---|---|---|---|
| `↵` | VS Code + Claude session | `z` | park / unpark |
| `c` | Claude session | `←` `→` `1`–`4` | tabs |
| `p` | PR | `v` | preview |
| `g` | GitHub repo | `r` | refresh |
| `m` | merge (merge commit, asks first) | `?` | legend |
| `n` | new VS Code window | `j` `k` | down / up |
| `x` | open + quit | `q` | quit |

`/` searches; `↵` keeps the filter, `esc` clears it. `--park [dir]` / `--unpark [dir]` work from a shell, `--help` lists the rest.
