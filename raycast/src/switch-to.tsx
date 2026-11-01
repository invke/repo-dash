import { List } from "@raycast/api";
import { useCachedPromise, useFrecencySorting } from "@raycast/utils";
import { Place, placeAccessories, PlaceActions, placeIcon } from "./place";
import { RepoRow, tab, WorkspaceRow, WorktreeRow } from "./rd";

type Row = RepoRow | WorktreeRow | WorkspaceRow | { kind: "gone-branch" };

const activity = (row: Place) => (row.kind === "workspace" ? 0 : row.lastActivity);

function title(row: Place): string {
  switch (row.kind) {
    case "workspace":
      return row.name;
    case "repo":
      return row.repo;
    default:
      return row.title;
  }
}

function subtitle(row: Place): string {
  if (row.kind === "workspace") return "";
  return row.kind === "worktree" ? `${row.repo} · ${row.branch}` : row.branch;
}

export default function Command() {
  const { data, isLoading, revalidate } = useCachedPromise(
    async () => {
      // every repo, not just the busy ones: this is where you go to get anywhere
      const [repos, workspaces] = await Promise.all([
        tab<Row>(["repo", "list", "--all"]),
        tab<Row>(["workspace", "list"]),
      ]);
      return [...repos.rows, ...workspaces.rows].filter((row): row is Place => row.kind !== "gone-branch");
    },
    [],
    { keepPreviousData: true },
  );

  const { data: places, visitItem } = useFrecencySorting(data, {
    key: (row) => row.path,
    sortUnvisited: (a, b) => activity(b) - activity(a),
  });

  return (
    <List isLoading={isLoading} searchBarPlaceholder="Switch to a worktree, repo or workspace">
      {places.map((row) => (
        <List.Item
          key={row.path}
          icon={placeIcon(row)}
          title={title(row)}
          subtitle={subtitle(row)}
          keywords={row.kind === "worktree" ? [row.repo, row.branch, row.session?.title ?? ""] : []}
          accessories={placeAccessories(row)}
          actions={<PlaceActions row={row} refresh={revalidate} onOpen={() => visitItem(row)} />}
        />
      ))}
    </List>
  );
}
