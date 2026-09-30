# repo-dash

A local gh-dash for everything under `~/Repositories`: every repo with its branch, worktrees, dirty state, open PR, CI and the Claude desktop session parked in each worktree. Bash 3.2 (macOS system bash), fzf ≥ 0.59, `gh`, `jq`.

```bash
repo-dash.sh --active --pr --pick   # the interactive dashboard (alias it, e.g. rdp)
repo-dash.sh                        # plain one-shot listing
repo-dash.sh --help
```

## Tabs

`1 repos` · `2 reviews` (waiting on you / ready to merge / waiting on others, with how far each PR trails its target) · `3 workspaces` (`_*.code-workspace`) · `4 parked`.

## Keys

Plain keys in normal mode; `/` starts a search, `↵` keeps the filter, `esc` clears it.

| key | | key | |
|---|---|---|---|
| `↵` | VS Code + Claude session | `z` | park / unpark |
| `c` | Claude session | `←` `→` `1`–`4` | tabs |
| `p` | PR | `v` | preview |
| `g` | GitHub repo | `r` | refresh |
| `m` | merge (merge commit, asks first) | `?` | legend |
| `n` | new VS Code window | `j` `k` | down / up |
| `x` | open + quit | `q` | quit |

Parked paths live in `~/.config/repo-dash/parked`; `--park [dir]` / `--unpark [dir]` work from a shell. Rows are cached per tab in `~/.cache/repo-dash/` and rebuilt in the background.
