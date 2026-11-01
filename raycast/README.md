# Repo Dash for Raycast

The repo-dash dashboard as Raycast commands. Everything comes from `repo-dash.sh … --json`, so the script stays the one source of truth.

| command | |
|---|---|
| **Switch to** | every worktree, repo and `.code-workspace`, most used first (unvisited ones by last activity); ↵ opens VS Code + the Claude session. Reads `rd place list`, so it skips status and PRs and loads in under a second |
| **Needs Me** | Claude sessions waiting on you, reviews waiting on you, your PRs with changes requested / failing CI / conflicts, and ones ready to merge |
| **New Worktree** | `feat/fix/chore/…` + a few words → a branch cut from staging into `<repo>-worktrees/`, opened in VS Code |
| **Repos** · **Pull Requests** | the dashboard's repos and PRs tabs |
| **Repo Dash Menu Bar** | counts Claude sessions that need you (⚑), PRs ready to merge (✓) and reviews waiting on you (👀) |

```bash
npm install
npm run dev     # installs it into Raycast; it stays after you stop dev mode
```

Preferences: the path to `repo-dash.sh` (default `~/Repositories/repo-dash/repo-dash.sh`) and whether Repos shows only repos with worktrees.
