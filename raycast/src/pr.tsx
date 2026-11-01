import { Action, ActionPanel, Alert, Color, confirmAlert, Icon, List, showToast, Toast } from "@raycast/api";
import { ciAccessory, PrRow, rd } from "./rd";

export const GROUPS: [PrRow["group"], string][] = [
  ["review-requested", "Waiting on Your Review"],
  ["ready", "Ready to Merge"],
  ["stuck", "Approved, Not Mergeable Yet"],
  ["changes", "Changes Requested"],
  ["review", "In Review"],
  ["draft", "Drafts"],
  ["stale", "Stale · untouched 90+ days"],
];

const MERGE_STATE: Record<string, { value: string; color: Color }> = {
  CLEAN: { value: "mergeable", color: Color.Green },
  HAS_HOOKS: { value: "mergeable", color: Color.Green },
  DIRTY: { value: "conflicts", color: Color.Red },
  BEHIND: { value: "behind", color: Color.Yellow },
  BLOCKED: { value: "blocked", color: Color.Yellow },
  UNSTABLE: { value: "unstable", color: Color.Yellow },
};

function who(pr: PrRow): string {
  switch (pr.group) {
    case "review-requested":
      return `@${pr.author}`;
    case "ready":
    case "stuck":
      return `approved by ${pr.decidedBy.join(", ") || "someone"}`;
    case "changes":
      return `changes from ${pr.decidedBy.join(", ") || "a reviewer"}`;
    case "draft":
      return "not ready for review";
    case "stale":
      return `last touched ${pr.age} ago`;
    default:
      return `waiting on ${pr.reviewers.join(", ") || "anyone"}`;
  }
}

function accessories(pr: PrRow): List.Item.Accessory[] {
  const list: (List.Item.Accessory | null)[] = [];
  const state = pr.group !== "review-requested" && pr.mergeState ? MERGE_STATE[pr.mergeState] : undefined;
  if (state) list.push({ tag: state });
  if (pr.behind) list.push({ text: { value: `↓${pr.behind}`, color: Color.Red }, tooltip: `behind ${pr.base}` });
  list.push(ciAccessory(pr.ci), { text: pr.age, tooltip: "last updated" });
  return list.filter((a): a is List.Item.Accessory => a !== null);
}

async function merge(pr: PrRow, done: () => void) {
  const ok = await confirmAlert({
    title: `Merge #${pr.number}?`,
    message: `${pr.title}\n${pr.head} → ${pr.base} with a merge commit`,
    primaryAction: { title: "Merge", style: Alert.ActionStyle.Destructive },
  });
  if (!ok) return;
  const toast = await showToast({ style: Toast.Style.Animated, title: `Merging #${pr.number}` });
  try {
    await rd(["pr", "merge", pr.url, "--yes"]);
    toast.style = Toast.Style.Success;
    toast.title = `Merged #${pr.number}`;
    done();
  } catch (error) {
    toast.style = Toast.Style.Failure;
    toast.message = String(error);
  }
}

export function PrItem({ pr, refresh }: { pr: PrRow; refresh: () => void }) {
  return (
    <List.Item
      icon={{ source: Icon.Code, tintColor: pr.group === "ready" ? Color.Green : Color.SecondaryText }}
      title={pr.title}
      subtitle={`${pr.repo} #${pr.number} · ${who(pr)}`}
      keywords={[pr.repo, String(pr.number), pr.author, pr.head ?? ""]}
      accessories={accessories(pr)}
      actions={
        <ActionPanel>
          <Action.OpenInBrowser url={pr.url} />
          <Action
            title="Copy Local Worktree Path"
            icon={Icon.Clipboard}
            shortcut={{ modifiers: ["cmd"], key: "y" }}
            onAction={() => rd(["path", "copy", pr.url]).then(() => showToast({ title: "Copied path" }))}
          />
          <Action.CopyToClipboard
            title="Copy URL"
            content={pr.url}
            shortcut={{ modifiers: ["cmd", "shift"], key: "c" }}
          />
          {pr.group !== "review-requested" && (
            <Action
              title="Merge…"
              icon={Icon.ArrowNe}
              style={Action.Style.Destructive}
              shortcut={{ modifiers: ["cmd", "shift"], key: "m" }}
              onAction={() => merge(pr, refresh)}
            />
          )}
          <Action
            title="Refresh"
            icon={Icon.ArrowClockwise}
            shortcut={{ modifiers: ["cmd"], key: "r" }}
            onAction={refresh}
          />
        </ActionPanel>
      }
    />
  );
}
