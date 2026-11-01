import { execFile } from "node:child_process";
import { homedir } from "node:os";
import { Color, getPreferenceValues, Icon, List, open } from "@raycast/api";

export type Pr = { number: number; state: string | null; ci: string | null; base: string | null; title: string };
export type Session = { id: string; title: string; needsAction: string | null };

export type RepoRow = {
  kind: "repo";
  path: string;
  repo: string;
  branch: string;
  dirty: number;
  ahead: number;
  behind: number;
  goneBranches: number;
  parked: boolean;
  pr: Pr | null;
  lastCommit: string | null;
};

export type WorktreeRow = {
  kind: "worktree";
  path: string;
  repo: string;
  repoPath: string;
  branch: string;
  title: string;
  dirty: number;
  base: string | null;
  commits: number;
  insertions: number;
  deletions: number;
  parked: boolean;
  outsideRepos: boolean;
  pr: Pr | null;
  session: Session | null;
};

export type PrRow = {
  kind: "pr";
  group: "review-requested" | "ready" | "stuck" | "changes" | "review" | "draft" | "stale";
  repo: string;
  nameWithOwner: string;
  number: number;
  title: string;
  url: string;
  author: string;
  age: string;
  ci: string | null;
  reviewers: string[];
  reviewDecision: string | null;
  mergeState: string | null;
  decidedBy: string[];
  base: string | null;
  head: string | null;
  behind: number | null;
};

export type Tab<Row> = { view: string; generatedAt: string; rows: Row[] };

type Preferences = { script?: string; activeOnly?: boolean };

// Raycast runs commands with a bare PATH; gh, jq, fzf and code live in Homebrew.
const PATH = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin", process.env.PATH]
  .filter(Boolean)
  .join(":");

function script(): string {
  const path = getPreferenceValues<Preferences>().script || "~/Repositories/repo-dash/repo-dash.sh";
  return path.replace(/^~(?=\/|$)/, homedir());
}

export function rd(args: string[]): Promise<string> {
  return new Promise((resolve, reject) => {
    execFile(
      "/bin/bash",
      [script(), ...args],
      { env: { ...process.env, PATH, LC_ALL: "en_US.UTF-8" }, maxBuffer: 32 * 1024 * 1024, timeout: 120_000 },
      (error, stdout, stderr) => (error ? reject(new Error(stderr.trim() || error.message)) : resolve(stdout)),
    );
  });
}

export async function tab<Row>(args: string[]): Promise<Tab<Row>> {
  return JSON.parse(await rd([...args, "--json"])) as Tab<Row>;
}

export function repoArgs(): string[] {
  return getPreferenceValues<Preferences>().activeOnly === false ? ["repo", "list"] : ["repo", "list", "--active"];
}

export async function openSession(id: string): Promise<void> {
  await open(`claude://claude.ai/epitaxy/${id}`);
}

export function ciAccessory(ci: string | null): List.Item.Accessory | null {
  switch (ci) {
    case "SUCCESS":
      return { icon: { source: Icon.CheckCircle, tintColor: Color.Green }, tooltip: "CI passing" };
    case "FAILURE":
    case "ERROR":
      return { icon: { source: Icon.XMarkCircle, tintColor: Color.Red }, tooltip: "CI failing" };
    case "PENDING":
    case "EXPECTED":
      return { icon: { source: Icon.Clock, tintColor: Color.Yellow }, tooltip: "CI running" };
    default:
      return null;
  }
}
