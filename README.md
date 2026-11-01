# repo-dash

A local gh-dash for a folder of repos: every repo with its branch, worktrees, dirty state, open PR, CI, reviews and the Claude desktop session parked in each worktree — in one fzf screen.

## Needs

- macOS (`open`, BSD `find`, the Claude desktop session store)
- `fzf` ≥ 0.59, `gh` (logged in), `jq`, `perl`, `curl`, VS Code's `code` on PATH
- system bash 3.2 is fine

## Setup

```bash
git clone git@github.com:invke/repo-dash.git ~/Repositories/repo-dash
alias rd='~/Repositories/repo-dash/repo-dash.sh'
alias rdp='rd dash --active'
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

`/` searches; `↵` keeps the filter, `esc` clears it.

## Commands

Outside the dashboard it's `rd <noun> <verb>`. `[dir]` defaults to the checkout you're in, and `rd help` lists everything.

| command | |
|---|---|
| `rd` / `rd dash` | the dashboard (takes `-a` `-A` `-d`) |
| `rd repo list` · `rd pr list` · `rd workspace list` · `rd park list` | a tab as a table |
| `rd pr view [dir\|url]` · `rd pr merge [dir\|url] [--yes]` | the PR in the browser · merge commit after a y/N |
| `rd repo browse [dir]` | the GitHub repo |
| `rd worktree new <repo> <branch> [--base b]` | cut a branch from staging (the first of `RD_BASES`) into `<repo>-worktrees/`; prints its path |
| `rd worktree open [dir]` · `rd session open [dir]` | VS Code + Claude session · just the session |
| `rd workspace open <file>` | a `.code-workspace` in VS Code |
| `rd path copy [dir\|url]` | a folder, or a PR's local worktree, to the clipboard |
| `rd park add\|remove [dir]` | hold it out of the repos tab, or bring it back |

The old flags (`--pick`, `--pr`, `--park`, `--unpark`, `--json`) still work. The ones with a new form say so on stderr.

## JSON

The list verbs print JSON when piped (or with `--json`), for building other front ends on (a Raycast extension, a menu bar item). Each is one document, `{ view, generatedAt, summary, rows }`:

```bash
rd repo list --active | jq .   # repos tab, same filters as the dashboard
rd pr list --json              # PRs tab, rows in the same group order
```

Each row has a `kind`: `repo`, `worktree` (with its `pr` and Claude `session`, whose `id` opens as `claude://claude.ai/epitaxy/<id>`), `gone-branch` (with `--dead`), `workspace` or `pr`. The PRs tab's `group` is `review-requested`, `ready`, `stuck`, `changes`, `review`, `draft` or `stale`.
