import { List } from "@raycast/api";
import { useCachedPromise } from "@raycast/utils";
import { placeAccessories, PlaceActions, placeIcon } from "./place";
import { RepoRow, repoArgs, tab, WorktreeRow } from "./rd";

type Row = RepoRow | WorktreeRow | { kind: "gone-branch"; path: string; repo: string; branch: string };

export default function Command() {
  const { data, isLoading, revalidate } = useCachedPromise(() => tab<Row>(repoArgs()), [], {
    keepPreviousData: true,
  });

  const sections = new Map<string, (RepoRow | WorktreeRow)[]>();
  for (const row of data?.rows ?? []) {
    if (row.kind === "gone-branch") continue;
    sections.set(row.repo, [...(sections.get(row.repo) ?? []), row]);
  }

  return (
    <List isLoading={isLoading} searchBarPlaceholder="Filter repos, branches, sessions">
      {[...sections].map(([repo, rows]) => (
        <List.Section key={repo} title={repo}>
          {rows.map((row) => (
            <List.Item
              key={row.path}
              icon={placeIcon(row)}
              title={row.kind === "repo" ? row.repo : row.title}
              subtitle={row.branch}
              keywords={row.kind === "repo" ? [row.branch] : [row.repo, row.branch, row.session?.title ?? ""]}
              accessories={placeAccessories(row)}
              actions={<PlaceActions row={row} refresh={revalidate} />}
            />
          ))}
        </List.Section>
      ))}
    </List>
  );
}
