import { Action, ActionPanel, Color, Icon, List, showToast, Toast } from "@raycast/api";
import { useCachedPromise } from "@raycast/utils";
import { ciAccessory, openSession, Pr, rd, RepoRow, repoArgs, tab, WorktreeRow } from "./rd";

type Row = RepoRow | WorktreeRow | { kind: "gone-branch"; path: string; repo: string; branch: string };

function prAccessory(pr: Pr | null): List.Item.Accessory | null {
  if (!pr) return null;
  const color = pr.state === "draft" ? Color.SecondaryText : pr.state === "APPROVED" ? Color.Green : Color.Yellow;
  return { tag: { value: `#${pr.number}`, color }, tooltip: pr.state ?? "review needed" };
}

function accessories(row: RepoRow | WorktreeRow): List.Item.Accessory[] {
  const list: (List.Item.Accessory | null)[] = [];
  if (row.kind === "worktree" && row.session?.needsAction) {
    list.push({ icon: { source: Icon.Flag, tintColor: Color.Orange }, tooltip: row.session.needsAction });
  }
  if (row.dirty > 0) list.push({ text: { value: `●${row.dirty}`, color: Color.Yellow }, tooltip: "uncommitted" });
  if (row.kind === "repo") {
    if (row.ahead > 0) list.push({ text: { value: `↑${row.ahead}`, color: Color.Green }, tooltip: "unpushed" });
    if (row.behind > 0) list.push({ text: { value: `↓${row.behind}`, color: Color.Red }, tooltip: "behind" });
  } else if (row.commits > 0) {
    list.push({ text: `+${row.insertions} −${row.deletions}`, tooltip: `${row.commits} commits on ${row.base}` });
  }
  list.push(prAccessory(row.pr), ciAccessory(row.pr?.ci ?? null));
  return list.filter((a): a is List.Item.Accessory => a !== null);
}

async function run(args: string[], title: string, done: () => void) {
  const toast = await showToast({ style: Toast.Style.Animated, title });
  try {
    await rd(args);
    toast.style = Toast.Style.Success;
    done();
  } catch (error) {
    toast.style = Toast.Style.Failure;
    toast.message = String(error);
  }
}

function Actions({ row, refresh }: { row: RepoRow | WorktreeRow; refresh: () => void }) {
  const session = row.kind === "worktree" ? row.session : null;
  return (
    <ActionPanel>
      <ActionPanel.Section>
        <Action title="Open in VS Code + Claude" icon={Icon.Code} onAction={() => rd(["worktree", "open", row.path])} />
        {session && (
          <Action
            title="Open Claude Session"
            icon={Icon.Message}
            shortcut={{ modifiers: ["cmd"], key: "c" }}
            onAction={() => openSession(session.id)}
          />
        )}
        {row.pr && (
          <Action
            title="Open Pull Request"
            icon={Icon.Globe}
            shortcut={{ modifiers: ["cmd"], key: "p" }}
            onAction={() => rd(["pr", "view", row.path])}
          />
        )}
        <Action
          title="Open GitHub Repo"
          icon={Icon.Link}
          shortcut={{ modifiers: ["cmd"], key: "g" }}
          onAction={() => rd(["repo", "browse", row.path])}
        />
      </ActionPanel.Section>
      <ActionPanel.Section>
        <Action.CopyToClipboard title="Copy Path" content={row.path} shortcut={{ modifiers: ["cmd"], key: "y" }} />
        <Action.ShowInFinder path={row.path} />
        <Action
          title={row.parked ? "Unpark" : "Park"}
          icon={Icon.Pin}
          shortcut={{ modifiers: ["cmd"], key: "z" }}
          onAction={() =>
            run(["park", row.parked ? "remove" : "add", row.path], row.parked ? "Unparking" : "Parking", refresh)
          }
        />
        <Action
          title="Refresh"
          icon={Icon.ArrowClockwise}
          shortcut={{ modifiers: ["cmd"], key: "r" }}
          onAction={refresh}
        />
      </ActionPanel.Section>
    </ActionPanel>
  );
}

export default function Command() {
  const { data, isLoading, revalidate } = useCachedPromise(() => tab<Row>(repoArgs()), [], {
    keepPreviousData: true,
  });

  const sections = new Map<string, Row[]>();
  for (const row of data?.rows ?? []) {
    if (row.kind === "gone-branch") continue;
    sections.set(row.repo, [...(sections.get(row.repo) ?? []), row]);
  }

  return (
    <List isLoading={isLoading} searchBarPlaceholder="Filter repos, branches, sessions">
      {[...sections].map(([repo, rows]) => (
        <List.Section key={repo} title={repo}>
          {rows.map((row) =>
            row.kind === "repo" ? (
              <List.Item
                key={row.path}
                icon={{ source: Icon.Folder, tintColor: row.dirty > 0 ? Color.Yellow : Color.SecondaryText }}
                title={row.repo}
                subtitle={row.branch}
                keywords={[row.branch]}
                accessories={accessories(row)}
                actions={<Actions row={row} refresh={revalidate} />}
              />
            ) : row.kind === "worktree" ? (
              <List.Item
                key={row.path}
                icon={{ source: Icon.Tree, tintColor: row.dirty > 0 ? Color.Yellow : Color.Green }}
                title={row.title}
                subtitle={row.branch}
                keywords={[row.repo, row.branch, row.session?.title ?? ""]}
                accessories={accessories(row)}
                actions={<Actions row={row} refresh={revalidate} />}
              />
            ) : null,
          )}
        </List.Section>
      ))}
    </List>
  );
}
