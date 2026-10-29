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

```
~/Repositories/                       $REPOS
├── my-api/                           a repo: a direct child with a real .git/ folder
│   ├── .git/
│   └── .claude/worktrees/feat-x/     a worktree inside the repo        ✓ listed under my-api
├── my-api-worktrees/                 a sibling folder of worktrees     ✓ listed under my-api
│   └── fix-login/                    (.git is a file, so not a repo of its own)
├── clients/web/                      nested one level too deep         ✗ not scanned
├── _platform.code-workspace          multi-root workspace              → workspaces tab
├── _platform.claude-code.json        optional, { "name": "…" } for its display name
└── repo-dash/
/tmp/scratch-tree/                    a worktree outside $REPOS         ⚠ flagged
```

Worktrees are found through `git worktree list`, so they can live anywhere git knows about. Only the repos have to be direct children of `$REPOS`.

## Claude desktop

This part is optional. Without it the dashboard still works, but you lose session titles, the `⚑` "Claude needs you" flags and the `c` key.

- **The Claude desktop app** with Code-tab sessions. It reads the app's session files from `~/Library/Application Support/Claude/claude-code-sessions/` (override with `SESSION_STORE`).
- **One session per worktree.** A session belongs to a row when its worktree or working folder is exactly that row's path. The easiest way is to let the app create a worktree for each session. Either of its worktree locations works: `<repo>/.claude/worktrees/…`, or a sibling `<repo>-worktrees/…` folder under `$REPOS`.
- **Archived sessions are ignored.** Archive a session in the app and its title and flag drop off the row.
- **`⚑` text** comes from the app's end-of-turn summary of what the session needs from you. If the app hasn't written one, there's no flag.
- **`c` and `↵`** open the session with the app's `claude://` link, so the app has to be installed on the same Mac.

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
| `x` | open + quit | `y` | copy path (a PR copies its worktree) |
| | | `q` | quit |

`/` searches; `↵` keeps the filter, `esc` clears it. `--park [dir]` / `--unpark [dir]` work from a shell, `--help` lists the rest.
