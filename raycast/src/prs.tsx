import { List } from "@raycast/api";
import { useCachedPromise } from "@raycast/utils";
import { GROUPS, PrItem } from "./pr";
import { PrRow, tab } from "./rd";

export default function Command() {
  const { data, isLoading, revalidate } = useCachedPromise(() => tab<PrRow>(["pr", "list"]), [], {
    keepPreviousData: true,
  });
  const rows = data?.rows ?? [];

  return (
    <List isLoading={isLoading} searchBarPlaceholder="Filter pull requests">
      {GROUPS.map(([group, title]) => {
        const prs = rows.filter((pr) => pr.group === group);
        return (
          <List.Section key={group} title={title} subtitle={String(prs.length)}>
            {prs.map((pr) => (
              <PrItem key={pr.url} pr={pr} refresh={revalidate} />
            ))}
          </List.Section>
        );
      })}
    </List>
  );
}
