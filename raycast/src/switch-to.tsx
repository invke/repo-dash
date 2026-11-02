import { Action, Color, Icon, List } from "@raycast/api";
import { useCachedPromise, useCachedState, useFrecencySorting } from "@raycast/utils";
import { PlaceActions, placeAccessories, prAccessory } from "./place";
import { ciAccessory, PlaceRow, RepoRow, tab, WorkspaceRow, WorktreeRow } from "./rd";

type Row = PlaceRow | WorkspaceRow;
type Full = RepoRow | WorktreeRow;

const activity = (row: Row) => (row.kind === "workspace" ? 0 : row.lastActivity);

function icon(row: Row, full?: Full): List.Item.Props["icon"] {
  const dirty = (full?.dirty ?? 0) > 0;
  switch (row.kind) {
    case "workspace":
      return { source: Icon.AppWindowGrid2x2, tintColor: Color.Purple };
    case "repo":
      return { source: Icon.Folder, tintColor: dirty ? Color.Yellow : Color.SecondaryText };
    default:
      return { source: Icon.Tree, tintColor: dirty ? Color.Yellow : Color.Green };
  }
}

function accessories(row: Row, full?: Full): List.Item.Accessory[] {
  if (row.kind === "workspace") return [{ text: "workspace" }];
  const list: (List.Item.Accessory | null)[] = [];
  if (full) {
    list.push(...placeAccessories(full));
  } else {
    if (row.session?.needsAction) {
      list.push({ icon: { source: Icon.Flag, tintColor: Color.Orange }, tooltip: row.session.needsAction });
    }
    list.push(prAccessory(row.pr), ciAccessory(row.pr?.ci ?? null));
  }
  if (row.parked) list.push({ icon: Icon.Pin, tooltip: "parked" });
  if (row.lastActivity) list.push({ date: new Date(row.lastActivity), tooltip: "last activity" });
  return list.filter((a): a is List.Item.Accessory => a !== null);
}

function detail(row: Row, full?: Full): string {
  if (row.kind === "workspace") return `## ${row.name}\n\n\`${row.path}\``;
  const lines = [`## ${row.title}`, `\`${row.repo}\` · \`${row.branch}\``];
  if (row.session?.needsAction) lines.push(`### ⚑ Needs you\n\n> ${row.session.needsAction}`);
  if (row.session) lines.push(`**Claude:** ${row.session.title}`);
  const pr = full?.pr ?? row.pr;
  if (pr)
    lines.push(`**PR #${pr.number}:** ${pr.title} — ${pr.state ?? "review needed"}${pr.ci ? `, CI ${pr.ci}` : ""}`);
  if (full) {
    const status = [full.dirty > 0 ? `${full.dirty} uncommitted` : "clean"];
    if (full.kind === "repo") {
      if (full.ahead) status.push(`${full.ahead} unpushed`);
      if (full.behind) status.push(`${full.behind} behind`);
    } else if (full.commits) {
      status.push(`${full.commits} commits on ${full.base} (+${full.insertions} −${full.deletions})`);
    }
    lines.push(`**Status:** ${status.join(", ")}`);
  }
  return lines.join("\n\n");
}

export default function Command() {
  const [showDetail, setShowDetail] = useCachedState("switch-to-detail", false);

  // place list paints in under a second; repo list fills in status, diffs and CI behind it
  const light = useCachedPromise(async () => (await tab<Row>(["place", "list"])).rows, [], { keepPreviousData: true });
  const heavy = useCachedPromise(async () => (await tab<Full>(["repo", "list", "--all"])).rows, [], {
    keepPreviousData: true,
  });

  const byPath = new Map((heavy.data ?? []).map((r) => [r.path, r]));
  const refresh = () => {
    light.revalidate();
    heavy.revalidate();
  };

  const { data: places, visitItem } = useFrecencySorting(light.data, {
    key: (row) => row.path,
    sortUnvisited: (a, b) => activity(b) - activity(a),
  });

  return (
    <List
      isLoading={light.isLoading || heavy.isLoading}
      isShowingDetail={showDetail}
      searchBarPlaceholder="Switch to a worktree, repo or workspace"
    >
      {places.map((row) => {
        const full = byPath.get(row.path);
        return (
          <List.Item
            key={row.path}
            icon={icon(row, full)}
            title={row.kind === "workspace" ? row.name : row.title}
            subtitle={
              showDetail
                ? undefined
                : row.kind === "worktree"
                  ? `${row.repo} · ${row.branch}`
                  : row.kind === "repo"
                    ? row.branch
                    : ""
            }
            keywords={row.kind === "workspace" ? [] : [row.repo, row.branch, row.session?.title ?? ""]}
            accessories={showDetail ? undefined : accessories(row, full)}
            detail={<List.Item.Detail markdown={detail(row, full)} />}
            actions={
              <PlaceActions row={full ?? row} refresh={refresh} onOpen={() => visitItem(row)}>
                <Action
                  title={showDetail ? "Hide Details" : "Show Details"}
                  icon={Icon.Sidebar}
                  shortcut={{ modifiers: ["cmd"], key: "d" }}
                  onAction={() => setShowDetail(!showDetail)}
                />
              </PlaceActions>
            }
          />
        );
      })}
    </List>
  );
}
