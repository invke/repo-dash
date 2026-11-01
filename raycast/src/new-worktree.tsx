import { Action, ActionPanel, Form, Icon, popToRoot, showToast, Toast } from "@raycast/api";
import { FormValidation, useCachedPromise, useForm } from "@raycast/utils";
import { rd, RepoRow, tab } from "./rd";

type Values = { repo: string; type: string; name: string; base: string; open: boolean };

const TYPES = ["feat", "fix", "chore", "refactor", "docs"];

const kebab = (s: string) =>
  s
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");

export default function Command() {
  const { data: repos, isLoading } = useCachedPromise(
    async () =>
      (await tab<RepoRow | { kind: string }>(["repo", "list", "--all"])).rows
        .filter((row): row is RepoRow => row.kind === "repo")
        .map((row) => row.repo)
        .sort(),
    [],
    { keepPreviousData: true },
  );

  const { handleSubmit, itemProps, values } = useForm<Values>({
    initialValues: { type: "feat", open: true },
    validation: {
      repo: FormValidation.Required,
      name: (value) => (kebab(value ?? "") ? undefined : "A few words for the branch name"),
    },
    async onSubmit({ repo, type, name, base, open }) {
      const branch = `${type}/${kebab(name)}`;
      const toast = await showToast({ style: Toast.Style.Animated, title: `Creating ${branch}` });
      try {
        const path = (
          await rd(["worktree", "new", repo, branch, ...(base.trim() ? ["--base", base.trim()] : [])])
        ).trim();
        if (open) await rd(["worktree", "open", path]);
        toast.style = Toast.Style.Success;
        toast.title = `Created ${branch}`;
        toast.message = path;
        await popToRoot();
      } catch (error) {
        toast.style = Toast.Style.Failure;
        toast.title = `Couldn't create ${branch}`;
        toast.message = String(error);
      }
    },
  });

  return (
    <Form
      isLoading={isLoading}
      actions={
        <ActionPanel>
          <Action.SubmitForm title="Create Worktree" icon={Icon.Plus} onSubmit={handleSubmit} />
        </ActionPanel>
      }
    >
      <Form.Dropdown title="Repo" storeValue {...itemProps.repo}>
        {(repos ?? []).map((repo) => (
          <Form.Dropdown.Item key={repo} value={repo} title={repo} />
        ))}
      </Form.Dropdown>
      <Form.Dropdown title="Type" {...itemProps.type}>
        {TYPES.map((type) => (
          <Form.Dropdown.Item key={type} value={type} title={type} />
        ))}
      </Form.Dropdown>
      <Form.TextField title="Name" placeholder="what this branch does" {...itemProps.name} />
      <Form.Description text={`Branch: ${values.type}/${kebab(values.name ?? "") || "…"}`} />
      <Form.TextField title="Base" placeholder="default: first of RD_BASES on origin (staging…)" {...itemProps.base} />
      <Form.Checkbox label="Open in VS Code" {...itemProps.open} />
    </Form>
  );
}
