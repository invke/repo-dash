import { Action, ActionPanel, Color, Icon, List, showToast, Toast } from "@raycast/api";
import { ReactNode } from "react";
import { ciAccessory, openSession, Pr, rd, RepoRow, Session, WorkspaceRow, WorktreeRow } from "./rd";

export type Place = RepoRow | WorktreeRow | WorkspaceRow;

export function prAccessory(pr: Pr | null): List.Item.Accessory | null {
  if (!pr) return null;
  const color = pr.state === "draft" ? Color.SecondaryText : pr.state === "APPROVED" ? Color.Green : Color.Yellow;
  return { tag: { value: `#${pr.number}`, color }, tooltip: pr.state ?? "review needed" };
}

export function placeAccessories(row: Place): List.Item.Accessory[] {
  if (row.kind === "workspace") return [{ text: "workspace" }];
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

export function placeIcon(row: Place): List.Item.Props["icon"] {
  switch (row.kind) {
    case "workspace":
      return { source: Icon.AppWindowGrid2x2, tintColor: Color.Purple };
    case "repo":
      return { source: Icon.Folder, tintColor: row.dirty > 0 ? Color.Yellow : Color.SecondaryText };
    default:
      return { source: Icon.Tree, tintColor: row.dirty > 0 ? Color.Yellow : Color.Green };
  }
}

export async function runToast(args: string[], title: string, done?: () => void) {
  const toast = await showToast({ style: Toast.Style.Animated, title });
  try {
    await rd(args);
    toast.style = Toast.Style.Success;
    done?.();
  } catch (error) {
    toast.style = Toast.Style.Failure;
    toast.message = String(error);
  }
}

// what the actions need: a full row, or a light one from place list
type Actionable = { kind: string; path: string; parked?: boolean; pr?: Pr | null; session?: Session | null };

export async function openPlace(row: Actionable): Promise<void> {
  try {
    await rd(row.kind === "workspace" ? ["workspace", "open", row.path] : ["worktree", "open", row.path]);
  } catch (error) {
    await showToast({ style: Toast.Style.Failure, title: "Couldn't open", message: String(error) });
  }
}

export function PlaceActions({
  row,
  refresh,
  onOpen,
  children,
}: {
  row: Actionable;
  refresh: () => void;
  onOpen?: () => void;
  children?: ReactNode;
}) {
  const session = row.session ?? null;
  const git = row.kind !== "workspace" ? row : null;
  return (
    <ActionPanel>
      <ActionPanel.Section>
        <Action
          title={row.kind === "workspace" ? "Open in VS Code" : "Open in VS Code + Claude"}
          icon={Icon.Code}
          onAction={() => {
            onOpen?.();
            openPlace(row);
          }}
        />
        {session && (
          <Action
            title="Open Claude Session"
            icon={Icon.Message}
            shortcut={{ modifiers: ["cmd"], key: "c" }}
            onAction={() => {
              onOpen?.();
              openSession(session.id);
            }}
          />
        )}
        {git?.pr && (
          <Action
            title="Open Pull Request"
            icon={Icon.Globe}
            shortcut={{ modifiers: ["cmd"], key: "p" }}
            onAction={() => rd(["pr", "view", git.path])}
          />
        )}
        {git && (
          <Action
            title="Open GitHub Repo"
            icon={Icon.Link}
            shortcut={{ modifiers: ["cmd"], key: "g" }}
            onAction={() => rd(["repo", "browse", git.path])}
          />
        )}
      </ActionPanel.Section>
      <ActionPanel.Section>
        <Action.CopyToClipboard title="Copy Path" content={row.path} shortcut={{ modifiers: ["cmd"], key: "y" }} />
        <Action.ShowInFinder path={row.path} />
        {git && (
          <Action
            title={git.parked ? "Unpark" : "Park"}
            icon={Icon.Pin}
            shortcut={{ modifiers: ["cmd"], key: "z" }}
            onAction={() =>
              runToast(["park", git.parked ? "remove" : "add", git.path], git.parked ? "Unparking" : "Parking", refresh)
            }
          />
        )}
        <Action
          title="Refresh"
          icon={Icon.ArrowClockwise}
          shortcut={{ modifiers: ["cmd"], key: "r" }}
          onAction={refresh}
        />
        {children}
      </ActionPanel.Section>
    </ActionPanel>
  );
}
