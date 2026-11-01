import { Icon, launchCommand, LaunchType, MenuBarExtra, open } from "@raycast/api";
import { useCachedPromise } from "@raycast/utils";
import { openSession, PrRow, repoArgs, RepoRow, tab, WorktreeRow } from "./rd";

export default function Command() {
  const { data, isLoading } = useCachedPromise(
    async () => {
      const [repos, prs] = await Promise.all([tab<RepoRow | WorktreeRow>(repoArgs()), tab<PrRow>(["pr", "list"])]);
      return {
        flagged: repos.rows.filter((r): r is WorktreeRow => r.kind === "worktree" && !!r.session?.needsAction),
        ready: prs.rows.filter((pr) => pr.group === "ready"),
        toReview: prs.rows.filter((pr) => pr.group === "review-requested"),
      };
    },
    [],
    { keepPreviousData: true },
  );

  const flagged = data?.flagged ?? [];
  const ready = data?.ready ?? [];
  const toReview = data?.toReview ?? [];
  const parts = [
    flagged.length && `⚑${flagged.length}`,
    ready.length && `✓${ready.length}`,
    toReview.length && `👀${toReview.length}`,
  ];

  return (
    <MenuBarExtra icon={Icon.Tree} title={parts.filter(Boolean).join(" ") || undefined} isLoading={isLoading}>
      <MenuBarExtra.Section title="Claude Needs You">
        {flagged.map((wt) => (
          <MenuBarExtra.Item
            key={wt.path}
            icon={Icon.Flag}
            title={wt.title}
            subtitle={wt.repo}
            tooltip={wt.session?.needsAction ?? undefined}
            onAction={() => wt.session && openSession(wt.session.id)}
          />
        ))}
      </MenuBarExtra.Section>
      <MenuBarExtra.Section title="Ready to Merge">
        {ready.map((pr) => (
          <MenuBarExtra.Item
            key={pr.url}
            icon={Icon.CheckCircle}
            title={pr.title}
            subtitle={`${pr.repo} #${pr.number}`}
            onAction={() => open(pr.url)}
          />
        ))}
      </MenuBarExtra.Section>
      <MenuBarExtra.Section title="Waiting on Your Review">
        {toReview.map((pr) => (
          <MenuBarExtra.Item
            key={pr.url}
            icon={Icon.Eye}
            title={pr.title}
            subtitle={`${pr.repo} #${pr.number}`}
            onAction={() => open(pr.url)}
          />
        ))}
      </MenuBarExtra.Section>
      <MenuBarExtra.Section>
        <MenuBarExtra.Item
          title="Open Repos"
          onAction={() => launchCommand({ name: "repos", type: LaunchType.UserInitiated })}
        />
        <MenuBarExtra.Item
          title="Open Pull Requests"
          onAction={() => launchCommand({ name: "prs", type: LaunchType.UserInitiated })}
        />
      </MenuBarExtra.Section>
    </MenuBarExtra>
  );
}
