# Repo Dash for Raycast

The repo-dash dashboard as Raycast commands: **Repos**, **Pull Requests** and a menu bar item counting Claude sessions that need you (⚑), PRs ready to merge (✓) and reviews waiting on you (👀). Everything comes from `repo-dash.sh … --json`, so the script stays the one source of truth.

```bash
npm install
npm run dev     # installs it into Raycast; it stays after you stop dev mode
```

Preferences: the path to `repo-dash.sh` (default `~/Repositories/repo-dash/repo-dash.sh`) and whether Repos shows only repos with worktrees.
