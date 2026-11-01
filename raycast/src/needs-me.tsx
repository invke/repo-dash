import { Action, ActionPanel, Color, Icon, List } from "@raycast/api";
import { useCachedPromise } from "@raycast/utils";
import { openPlace } from "./place";
import { PrItem } from "./pr";
import { openSession, PrRow, repoArgs, RepoRow, tab, WorktreeRow } from "./rd";

// my PRs past draft that are stuck on something I have to do
function needsWork(pr: PrRow): boolean {
  if (pr.group === "review-requested" || pr.group === "draft" || pr.group === "stale" || pr.group === "ready") {
    return false;
  }
  return (
    pr.group === "changes" ||
    pr.ci === "FAILURE" ||
    pr.ci === "ERROR" ||
    pr.mergeState === "DIRTY" ||
    pr.mergeState === "BEHIND"
  );
}

export default function Command() {
  const { data, isLoading, revalidate } = useCachedPromise(
    async () => {
      const [repos, prs] = await Promise.all([tab<RepoRow | WorktreeRow>(repoArgs()), tab<PrRow>(["pr", "list"])]);
      return {
        flagged: repos.rows
          .filter((r): r is WorktreeRow => r.kind === "worktree" && !!r.session?.needsAction)
          .sort((a, b) => b.lastActivity - a.lastActivity),
        toReview: prs.rows.filter((pr) => pr.group === "review-requested"),
        needsWork: prs.rows.filter(needsWork),
        ready: prs.rows.filter((pr) => pr.group === "ready"),
      };
    },
    [],
    { keepPreviousData: true },
  );

  const empty = data && !data.flagged.length && !data.toReview.length && !data.needsWork.length && !data.ready.length;

  return (
    <List isLoading={isLoading} searchBarPlaceholder="Filter what needs you">
      {empty && <List.EmptyView icon={Icon.Checkmark} title="Nothing needs you" description="Go drink some water." />}
      <List.Section title="Claude Needs You" subtitle={String(data?.flagged.length ?? 0)}>
        {data?.flagged.map((wt) => (
          <List.Item
            key={wt.path}
            icon={{ source: Icon.Flag, tintColor: Color.Orange }}
            title={wt.session?.needsAction ?? wt.title}
            subtitle={`${wt.repo} · ${wt.title}`}
            keywords={[wt.repo, wt.branch, wt.title]}
            actions={
              <ActionPanel>
                <Action
                  title="Open Claude Session"
                  icon={Icon.Message}
                  onAction={() => wt.session && openSession(wt.session.id)}
                />
                <Action title="Open in VS Code + Claude" icon={Icon.Code} onAction={() => openPlace(wt)} />
                <Action.CopyToClipboard
                  title="Copy Path"
                  content={wt.path}
                  shortcut={{ modifiers: ["cmd"], key: "y" }}
                />
                <Action
                  title="Refresh"
                  icon={Icon.ArrowClockwise}
                  shortcut={{ modifiers: ["cmd"], key: "r" }}
                  onAction={revalidate}
                />
              </ActionPanel>
            }
          />
        ))}
      </List.Section>
      <List.Section title="Waiting on Your Review" subtitle={String(data?.toReview.length ?? 0)}>
        {data?.toReview.map((pr) => (
          <PrItem key={pr.url} pr={pr} refresh={revalidate} />
        ))}
      </List.Section>
      <List.Section title="Your PRs Need Work" subtitle={String(data?.needsWork.length ?? 0)}>
        {data?.needsWork.map((pr) => (
          <PrItem key={pr.url} pr={pr} refresh={revalidate} />
        ))}
      </List.Section>
      <List.Section title="Ready to Merge" subtitle={String(data?.ready.length ?? 0)}>
        {data?.ready.map((pr) => (
          <PrItem key={pr.url} pr={pr} refresh={revalidate} />
        ))}
      </List.Section>
    </List>
  );
}
