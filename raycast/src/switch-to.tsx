import { Color, Icon, List } from "@raycast/api";
import { useCachedPromise, useFrecencySorting } from "@raycast/utils";
import { PlaceActions } from "./place";
import { PlaceRow, tab, WorkspaceRow } from "./rd";

type Row = PlaceRow | WorkspaceRow;

const activity = (row: Row) => (row.kind === "workspace" ? 0 : row.lastActivity);

function icon(row: Row): List.Item.Props["icon"] {
  switch (row.kind) {
    case "workspace":
      return { source: Icon.AppWindowGrid2x2, tintColor: Color.Purple };
    case "repo":
      return { source: Icon.Folder, tintColor: Color.SecondaryText };
    default:
      return { source: Icon.Tree, tintColor: Color.Green };
  }
}

function accessories(row: Row): List.Item.Accessory[] {
  if (row.kind === "workspace") return [{ text: "workspace" }];
  const list: List.Item.Accessory[] = [];
  if (row.session?.needsAction) {
    list.push({ icon: { source: Icon.Flag, tintColor: Color.Orange }, tooltip: row.session.needsAction });
  }
  if (row.parked) list.push({ icon: Icon.Pin, tooltip: "parked" });
  if (row.lastActivity) list.push({ date: new Date(row.lastActivity), tooltip: "last activity" });
  return list;
}

export default function Command() {
  const { data, isLoading, revalidate } = useCachedPromise(async () => (await tab<Row>(["place", "list"])).rows, [], {
    keepPreviousData: true,
  });

  const { data: places, visitItem } = useFrecencySorting(data, {
    key: (row) => row.path,
    sortUnvisited: (a, b) => activity(b) - activity(a),
  });

  return (
    <List isLoading={isLoading} searchBarPlaceholder="Switch to a worktree, repo or workspace">
      {places.map((row) => (
        <List.Item
          key={row.path}
          icon={icon(row)}
          title={row.kind === "workspace" ? row.name : row.title}
          subtitle={row.kind === "worktree" ? `${row.repo} · ${row.branch}` : row.kind === "repo" ? row.branch : ""}
          keywords={row.kind === "workspace" ? [] : [row.repo, row.branch, row.session?.title ?? ""]}
          accessories={accessories(row)}
          actions={<PlaceActions row={row} refresh={revalidate} onOpen={() => visitItem(row)} />}
        />
      ))}
    </List>
  );
}
