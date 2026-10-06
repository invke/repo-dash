#!/usr/bin/env bash
# A local gh-dash: every repo in ~/Repositories with its branch, worktrees,
# dirty state and the Claude session parked in each worktree.
# Written for bash 3.2 (macOS system bash) — no associative arrays.
set -uo pipefail
# Column widths count characters, which needs a UTF-8 locale.
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in *[Uu][Tt][Ff]-8*|*utf8*) ;; *) export LC_ALL=en_US.UTF-8 ;; esac

# Personal settings (REPOS, RD_ORG, RD_BASES) live outside the script.
RD_CONFIG="${RD_CONFIG:-$HOME/.config/repo-dash/config}"
# shellcheck source=/dev/null
[ -f "$RD_CONFIG" ] && . "$RD_CONFIG"
REPOS="${REPOS:-$HOME/Repositories}"
RD_ORG="${RD_ORG:-}"                                        # empty: PRs from every org
RD_BASES="${RD_BASES:-internal staging develop main master}"  # first one on origin is the target
ORG_Q="${RD_ORG:+org:$RD_ORG }"
export REPOS RD_ORG RD_BASES ORG_Q

# VS Code workspace files are JSONC — strip trailing commas before jq sees them
jsonc() { perl -0pe 's/,(\s*[}\]])/\1/g' "$1"; }
SESSION_STORE="${SESSION_STORE:-$HOME/Library/Application Support/Claude/claude-code-sessions}"
JOBS="${JOBS:-12}"
# Parked repos/worktrees, one absolute path per line: held out of the repos tab until picked back up.
PARKED_FILE="${PARKED_FILE:-$HOME/.config/repo-dash/parked}"
export PARKED_FILE

is_parked() { [ -s "$PARKED_FILE" ] && grep -Fxq -- "$1" "$PARKED_FILE"; }
export -f is_parked

park() {   # park <on|off|toggle> <path>; drops paths that no longer exist while it's there
  local mode=$1 p=$2 tmp
  [ -d "$p" ] || return 0
  p=$(cd "$p" && pwd -P)
  mkdir -p "${PARKED_FILE%/*}"; touch "$PARKED_FILE"
  if [ "$mode" = toggle ]; then is_parked "$p" && mode=off || mode=on; fi
  tmp=$(mktemp)
  while IFS= read -r l; do [ -d "$l" ] && [ "$l" != "$p" ] && printf '%s\n' "$l"; done < "$PARKED_FILE" > "$tmp"
  [ "$mode" = on ] && printf '%s\n' "$p" >> "$tmp"
  mv "$tmp" "$PARKED_FILE"
}

ALL=0; DEAD=0; WATCH=0; INTERVAL=30; ACTIVE=0; PR=0; PICK=0; ROWS=0; LAYOUT=auto
SUMMARY=""
while (( $# )); do
  case "$1" in
    -a|--all)   ALL=1 ;;
    -A|--active) ACTIVE=1 ;;
    -p|--pr)    PR=1 ;;
    -i|--pick)  PICK=1 ;;
    --rows)     ROWS=1 ;;
    --narrow)   LAYOUT=narrow ;;
    --wide)     LAYOUT=wide ;;
    --layout)   LAYOUT_INFO=1 ;;
    --preview)  shift; PREVIEW_TARGET="${1:-}" ;;
    --header)   # tabs + summary, then the keys wrapped to fzf's width, then the legend if toggled
                shift; view=${1:-}; sum=${2:-}; leg=${3:-}
                printf '  \033[2m%s\033[0m\n' "$(sed $'s/\033\\[[0-9;]*m//g' "$sum" 2>/dev/null)"
                width=$(( ${FZF_COLUMNS:-120} - 4 )); line=""; plain=0
                for k in "↵|code + claude" "c|claude" "p|PR" "g|repo" "m|merge" "n|new window" "x|open+quit" "z|park" \
                         "←→ 1-4|tabs" "/|search" "v|preview" "r|refresh" "?|legend" "q|quit"; do
                  key=${k%%|*}; what=${k#*|}; item="$key $what"
                  if [ "$plain" -gt 0 ] && [ $(( plain + 3 + ${#item} )) -gt "$width" ]; then
                    printf '%s\n' "$line"; line=""; plain=0
                  fi
                  [ "$plain" -gt 0 ] && { line="$line   "; plain=$((plain + 3)); }
                  line="$line$(printf '\033[1m%s\033[0m \033[2m%s\033[0m' "$key" "$what")"; plain=$((plain + ${#item}))
                done
                printf '%s\n' "$line"
                [ -n "${FZF_QUERY:-}" ] && printf '\033[1;33m/ %s\033[0m \033[2m· / edit · esc clear\033[0m\n' "$FZF_QUERY"
                if [ -s "$leg" ]; then
                  printf '\033[33m●n\033[0m\033[2m uncommitted  \033[32m↑n\033[0m\033[2m unpushed  \033[31m↓n\033[0m\033[2m behind  ✗n upstream gone  \033[33m⚑\033[0m\033[2m Claude needs you\033[0m\n'
                  printf '\033[2m#n draft  \033[33m#n\033[0m\033[2m review needed  \033[32m#n\033[0m\033[2m approved  \033[32mCI ✓\033[0m \033[31m✗\033[0m \033[33m…\033[0m\033[2m checks  +n -n since base\033[0m\n'
                fi
                exit 0 ;;
    --tabs)     shift   # the tab strip: numbered (the number jumps there) and counted
                cur=$(cat "${1:-}" 2>/dev/null); cur=${cur:-repos}
                rv="$HOME/.cache/repo-dash/pr-list-v1.tsv"
                kinds=$(cut -f1 "$rv" 2>/dev/null)
                n_in=$(printf '%s\n' "$kinds" | grep -cx in)
                n_ready=$(printf '%s\n' "$kinds" | grep -cx ready)
                n_out=$(printf '%s\n' "$kinds" | grep -cxE 'review|stuck|changes')
                n_chg=$(printf '%s\n' "$kinds" | grep -cx changes)
                n_draft=$(printf '%s\n' "$kinds" | grep -cx draft)
                n_repos=$(cat "$HOME/.cache/repo-dash/count-repos" 2>/dev/null)
                n_ws=$(ls "$REPOS"/_*.code-workspace 2>/dev/null | wc -l | tr -d ' ')
                n_parked=$(awk 'END{print NR}' "$PARKED_FILE" 2>/dev/null)
                c_off=$'\033[2m'; pill=$'\033[1;97;45m'; z=$'\033[0m'
                badge() { local n=${3:-0}; if [ "$n" -gt 0 ] 2>/dev/null; then printf '\033[1;%sm%s%s\033[0m' "$1" "$2" "$n"; else printf '\033[%sm%s0\033[0m' "$1" "$2"; fi; }
                # One line that fzf draws into its top border: the active tab is a pill cut into the frame.
                out=""; i=0
                for t in repos prs workspaces parked; do
                  i=$((i + 1))
                  case "$t" in
                    prs)        plain="$i PRs ⚑${n_in:-0} ✓${n_ready:-0} ◷${n_out:-0} ✎${n_draft:-0}"
                                [ "${n_chg:-0}" -gt 0 ] && plain="$plain ✗$n_chg"
                                # someone waiting on you is the one number that shouts
                                if [ "${n_in:-0}" -gt 0 ]; then counts=$'\033[1;30;43m'"⚑$n_in$z"; else counts="$(badge 33 ⚑ 0)"; fi
                                counts="$counts $(badge 32 ✓ "$n_ready") $(badge 34 ◷ "$n_out") $(badge 90 ✎ "$n_draft")"
                                [ "${n_chg:-0}" -gt 0 ] && counts="$counts $(badge 31 ✗ "$n_chg")" ;;
                    repos)      plain="$i repos ⎇${n_repos:-0}";      counts=$(badge 36 ⎇ "$n_repos") ;;
                    workspaces) plain="$i workspaces ▦${n_ws:-0}";    counts=$(badge 33 ▦ "$n_ws") ;;
                    parked)     plain="$i parked ‖${n_parked:-0}";    counts=$(badge 35 ‖ "$n_parked") ;;
                  esac
                  [ "$i" -gt 1 ] && out="${out}${c_off}──${z}"
                  if [ "$t" = "$cur" ]; then out="${out}${c_off}┤${z}${pill} ${plain} ${z}${c_off}├${z}"
                  else out="${out} ${c_off}${i}${z} ${t} ${counts} "; fi
                done
                printf '%s' "$out"
                exit 0 ;;
    --set-tab)  shift; echo "${2:-repos}" > "$1"; exit 0 ;;
    --toggle-tab) shift; view=$1; dir=${2:-1}
                cur=$(cat "$view" 2>/dev/null)
                if [ "$dir" = 1 ]; then
                  case "$cur" in prs) next=workspaces ;; workspaces) next=parked ;; parked) next=repos ;; *) next=prs ;; esac
                else
                  case "$cur" in prs) next=repos ;; workspaces) next=prs ;; parked) next=workspaces ;; *) next=parked ;; esac
                fi
                echo "$next" > "$view"
                exit 0 ;;
    --open|--open-claude)   # a PR URL opens in the browser; a folder opens in VS Code
                mode=$1; shift  # and focuses the Claude session parked there, if there is one
                case "${1:-}" in
                  http*) open "$1" ;;
                  ?*)
                    [ "$mode" = --open ] && code -r "$1"
                    store="$HOME/Library/Application Support/Claude/claude-code-sessions"
                    sid=$(find "$store" -name '*.json' -print0 2>/dev/null \
                      | xargs -0 jq -r --arg p "$1" 'select(.isArchived != true) | select((.worktreePath // .cwd) == $p)
                                                    | [(.lastActivityAt // 0), .sessionId] | @tsv' 2>/dev/null \
                      | sort -rn | head -1 | cut -f2)
                    [ -n "$sid" ] && open "claude://claude.ai/epitaxy/$sid"
                    ;;
                esac
                exit 0 ;;
    --open-repo) shift  # the GitHub repo behind a PR URL or a folder
                case "${1:-}" in
                  http*) open "${1%/pull/*}" ;;
                  ?*) (cd "$1" && gh browse >/dev/null 2>&1) ;;
                esac
                exit 0 ;;
    --open-pr)  shift   # the PR for a URL, or for the branch checked out in a folder
                case "${1:-}" in
                  http*) open "$1" ;;
                  ?*) (cd "$1" && gh pr view --web >/dev/null 2>&1) ;;
                esac
                exit 0 ;;
    --toggle-park) shift; park toggle "${1:-}"; exit 0 ;;
    --merge)    shift   # merge commit (not rebase) for a PR URL or a folder's branch, after a y/N
                url=${1:-}
                case "$url" in http*) ;; ?*) url=$(cd "$url" && gh pr view --json url --jq .url 2>/dev/null) ;; esac
                [ -n "$url" ] || { printf 'no PR here\n'; read -rsn1 -p $'\033[2many key\033[0m'; exit 0; }
                gh pr view "$url" --json number,title,baseRefName,headRefName,mergeStateStatus,reviewDecision \
                  --jq '"\u001b[1;95m#\(.number)\u001b[0m \u001b[1;97m\(.title)\u001b[0m\n  \(.headRefName) → \(.baseRefName)  \u001b[2m\(.reviewDecision // "") · \(.mergeStateStatus)\u001b[0m"'
                printf '\nmerge with a merge commit? [y/N] '; read -rsn1 yn; printf '%s\n' "$yn"
                if [ "$yn" = y ] || [ "$yn" = Y ]; then
                  gh pr merge "$url" --merge && rm -f "$HOME/.cache/repo-dash/pr-list-v1.tsv" "$HOME/.cache/repo-dash/prs-v2.tsv"
                  read -rsn1 -p $'\033[2many key\033[0m'
                fi
                exit 0 ;;
    --bg-refresh) shift  # rebuild the current tab off the UI thread, then swap the cached rows in
                ( export RD_REFRESH=${2:-1}; eval "$RD_ROWCMD" >/dev/null
                  port=$(cat "${1:-}" 2>/dev/null)
                  [ -n "$port" ] && curl -s -XPOST "localhost:$port" -d "reload-sync($RD_CACHEDCMD)" ) >/dev/null 2>&1 </dev/null &
                exit 0 ;;
    --park|--unpark)
                mode=on; [ "$1" = --unpark ] && mode=off; shift
                target=${1:-$PWD}; [ -d "$target" ] || { echo "not a directory: $target" >&2; exit 1; }
                target=$(git -C "$target" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$target")
                park "$mode" "$target"
                printf '%s %s\n' "$([ "$mode" = on ] && echo parked || echo unparked)" "$target"
                exit 0 ;;
    -d|--dead)  DEAD=1 ;;
    -w|--watch) WATCH=1; [[ "${2:-}" =~ ^[0-9]+$ ]] && { INTERVAL=$2; shift; } ;;
    -h|--help)
      cat <<'USAGE'
usage: repo-dash.sh [options]
  -a, --all         every repo, not just the ones with something going on
  -A, --active      only repos that have worktrees (what you're actually working on)
  -p, --pr          annotate branches with their open PR (one GitHub call, cached 5 min)
  -i, --pick        interactive overview: live dashboard you can search and open from
  -w, --watch [n]   the same interactive view (alias for --pick; n sets the refresh)
  -d, --dead        also list branches whose upstream is gone (cleanup view)
      --park [dir]    hold a repo or worktree out of the repos tab (default: the one you're in)
      --unpark [dir]  bring it back; ⌥p toggles either from the picker
      --narrow      force the tall/narrow layout (preview below, tight columns)
      --wide        force the wide layout (preview to the right)
      --layout      print what layout this terminal resolves to, and why
USAGE
      exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ -n "${RD_FORCE_COLOR:-}" ] || { [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; }; then
  B=$'\033[1m'; DIM=$'\033[2m'; R=$'\033[0m'; HEAD1=$'\033[1;95m'; TITLE=$'\033[1;97m'
  RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; BLU=$'\033[34m'; CYN=$'\033[36m'
else
  B=''; DIM=''; R=''; RED=''; GRN=''; YEL=''; BLU=''; CYN=''; HEAD1=''; TITLE=''
fi
# Layout is decided by whether the rows actually FIT, not by a guess at the
# monitor's shape. A 125-column terminal is not "wide" once a preview pane on
# the right eats half of it — that leaves ~60 columns for a 122-column row.
ROW_WIDE=125        # roomy stats + a title worth reading + fzf border, gutter and scrollbar
ROW_NARROW=86       # tight stats + the same
PREVIEW_MIN=55      # below this a side preview costs more than it gives


TERM_COLS=${COLUMNS:-0}
TERM_ROWS=${LINES:-0}
# zsh doesn't export COLUMNS, and tput inside $(…) sees a pipe and says 80 — ask the tty.
if ! [ "$TERM_COLS" -gt 0 ] 2>/dev/null; then
  read -r TERM_ROWS TERM_COLS < <({ stty size </dev/tty; } 2>/dev/null) || true
fi
[ "$TERM_COLS" -gt 0 ] 2>/dev/null || TERM_COLS=$(tput cols 2>/dev/null || echo 120)
[ "$TERM_ROWS" -gt 0 ] 2>/dev/null || TERM_ROWS=$(tput lines 2>/dev/null || echo 40)

PREVIEW_COLS=62     # a side preview is this wide, not a percentage of the screen

# Pick the widest arrangement that actually fits, in order of preference:
#   roomy rows beside a preview -> roomy rows above one -> tight rows above one
if [ $((TERM_COLS - PREVIEW_COLS)) -ge "$ROW_WIDE" ]; then
  NARROW=0; TALL=0
elif [ "$TERM_COLS" -ge "$ROW_WIDE" ]; then
  NARROW=0; TALL=1
else
  NARROW=1; TALL=1
fi
# A terminal taller than it is wide always reads better with the preview below.
[ "$TERM_ROWS" -gt "$TERM_COLS" ] && TALL=1
case "$LAYOUT" in
  narrow) NARROW=1; TALL=1 ;;
  wide)   NARROW=0; TALL=0 ;;
esac

if [ "$NARROW" -eq 1 ]; then
  W_REPO=24; W_DIFF=9;  W_COMMITS=4;  W_WS=24; W_DEAD=40
else
  W_REPO=30; W_DIFF=11; W_COMMITS=10; W_WS=31; W_DEAD=60
fi
W_STATS=$((3 + 1 + W_DIFF + 1 + W_COMMITS + 1 + 4))   # mark, diff, commits, CI

if [ "$TALL" -eq 1 ]; then
  PREVIEW_WIN='down:38%:wrap:border-top'
  LIST_COLS=$TERM_COLS
else
  PREVIEW_WIN="right:${PREVIEW_COLS}:wrap"
  LIST_COLS=$((TERM_COLS - PREVIEW_COLS))
fi

# Worktree cards: "  └ #1234  <title>  <stats>". The title gets everything the
# stats don't; repo rows stretch their branch column so their flags line up.
W_TITLE=$((LIST_COLS - 6 - 11 - 1 - W_STATS))   # fzf chrome, "  └ #1234  ", gap
[ "$W_TITLE" -lt 12 ] && W_TITLE=12
W_HEAD=$((11 + W_TITLE - W_REPO - 1))
[ "$W_HEAD" -lt 10 ] && W_HEAD=10

if [ -n "${LAYOUT_INFO:-}" ]; then
  printf 'terminal %s cols x %s rows\ncolumns: %s (rows need %s)\npreview: %s\n' \
    "$TERM_COLS" "$TERM_ROWS" \
    "$([ "$NARROW" -eq 1 ] && echo tight || echo roomy)" "$ROW_NEED" \
    "$([ "$TALL" -eq 1 ] && echo below || echo right)"
  printf 'list gets %s cols; title %s, stats %s\n' "$LIST_COLS" "$W_TITLE" "$W_STATS"
  exit 0
fi

export B DIM R HEAD1 TITLE RED GRN YEL BLU CYN ALL DEAD REPOS ACTIVE PR
export NARROW TALL TERM_COLS TERM_ROWS LIST_COLS W_REPO W_HEAD W_TITLE W_STATS W_DIFF W_COMMITS W_WS W_DEAD PREVIEW_WIN

short() { local s=$1 n=$2; if [ ${#s} -gt "$n" ]; then printf '%s…' "${s:0:$((n-1))}"; else printf '%s' "$s"; fi; }
# printf %-*s pads by bytes in bash 3.2, so ▸ ⚠ ● throw columns out — pad by characters.
pad() { local s=$1 n=$2; printf '%s%*s' "$s" $(( n > ${#s} ? n - ${#s} : 0 )) ''; }
export -f short pad

pr_line() {   # pr_line <gh-repo> <branch> -> repo, branch, number, state, ci, base, title
  [ "$PR" -eq 1 ] || return 0
  [ -n "${PR_TSV:-}" ] && [ -f "$PR_TSV" ] || return 0
  [ -n "$1" ] && [ -n "$2" ] || return 0
  # exact repo match wins; a prefix match covers repos GitHub has since renamed
  awk -F'\t' -v r="$1" -v b="$2" '
    $2==b {
      if ($1==r) exact=$0
      else if (index($1,r)==1 || index(r,$1)==1) pre=$0
    }
    END { line = exact ? exact : pre; if (line) print line }' "$PR_TSV"
}

pr_for() {   # pr_for <gh-repo> <branch> -> "#123" coloured by state
  local l; l=$(pr_line "$1" "$2"); [ -n "$l" ] || return 0
  local number state c
  number=$(printf '%s' "$l" | cut -f3); state=$(printf '%s' "$l" | cut -f4)
  case "$state" in draft) c=$DIM ;; APPROVED) c=$GRN ;; *) c=$YEL ;; esac
  printf '%s#%s%s' "$c" "$number" "$R"
}
export -f pr_line pr_for

build_prs() {
  [ "$PR" -eq 1 ] || return 0
  command -v gh >/dev/null || { echo "--pr needs the gh CLI" >&2; PR=0; return 0; }
  local cache="$HOME/.cache/repo-dash"; mkdir -p "$cache"
  PR_TSV="$cache/prs-v2.tsv"; export PR_TSV
  if [ -s "$PR_TSV" ] && [ -z "$(find "$PR_TSV" -mmin +5 2>/dev/null)" ]; then return 0; fi
  gh api graphql -f query='
    { search(query: "'"$ORG_Q"'is:pr is:open author:@me", type: ISSUE, first: 100) {
        nodes { ... on PullRequest {
          number headRefName baseRefName title isDraft reviewDecision repository { name }
          commits(last: 1) { nodes { commit { statusCheckRollup { state } } } } } } } }' \
    --jq '.data.search.nodes[]
          | [.repository.name, .headRefName, .number,
             (if .isDraft then "draft" else (.reviewDecision // "") end),
             (.commits.nodes[0].commit.statusCheckRollup.state // ""),
             .baseRefName, (.title | gsub("\t"; " "))] | @tsv' \
    > "$PR_TSV.tmp" 2>/dev/null && mv "$PR_TSV.tmp" "$PR_TSV" || rm -f "$PR_TSV.tmp"
}

scan_repo() {
  local dir=$1 out=$2 name=${1##*/}
  local head dirty track ahead behind dead flags interesting=0 nwt=0 rparked=0 nshown=0
  local vparked=0; [ "${VIEW:-}" = parked ] && vparked=1
  is_parked "$dir" && rparked=1
  if [ "$vparked" -eq 0 ] && [ "$rparked" -eq 1 ]; then
    printf '0\t0\t0\n' > "$out.stats"; : > "$out"; return 0
  fi

  head=$(git -C "$dir" branch --show-current 2>/dev/null); [ -n "$head" ] || head="(detached)"
  dirty=$(git -C "$dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  track=$(git -C "$dir" rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null)
  if [ -n "$track" ]; then behind=${track%%[!0-9]*}; ahead=${track##*[!0-9]}; else behind=0; ahead=0; fi
  dead=$(git -C "$dir" for-each-ref --format='%(upstream:track)' refs/heads 2>/dev/null | grep -c 'gone')

  local ghrepo=""
  if [ "$PR" -eq 1 ]; then
    ghrepo=$(git -C "$dir" config --get remote.origin.url 2>/dev/null)
    ghrepo=${ghrepo##*/}; ghrepo=${ghrepo%.git}
  fi

  flags=""
  [ "$dirty" -gt 0 ]  && { flags="$flags ${YEL}●${dirty}${R}"; interesting=1; }
  [ "$ahead" -gt 0 ]  && { flags="$flags ${GRN}↑${ahead}${R}"; interesting=1; }
  [ "$behind" -gt 0 ] && flags="$flags ${RED}↓${behind}${R}"
  [ "$dirty" -eq 0 ] && [ "$ahead" -eq 0 ] && flags="$flags ${GRN}✓${R}"
  [ "$dead" -gt 0 ]   && flags="$flags ${DIM}✗${dead}${R}"
  local rpr; rpr=$(pr_for "$ghrepo" "$head"); [ -n "$rpr" ] && flags="$flags $rpr"

  # Repo cards mirror the worktree ones: name + status on top, branch and last commit below.
  local rmark rtrack rdead rpl rci rcistr last
  if [ "$dirty" -gt 0 ]; then rmark="${YEL}$(pad "●$dirty" 3)${R}"; else rmark="${GRN}$(pad "✓" 3)${R}"; fi
  rtrack=""; local tplain=""
  [ "$ahead" -gt 0 ]  && { rtrack="${GRN}↑${ahead}${R} "; tplain="↑${ahead} "; }
  [ "$behind" -gt 0 ] && { rtrack="$rtrack${RED}↓${behind}${R}"; tplain="$tplain↓${behind}"; }
  rtrack="$rtrack$(printf '%*s' $(( ${#tplain} < W_DIFF ? W_DIFF - ${#tplain} : 0 )) '')"
  rdead=""; [ "$dead" -gt 0 ] && rdead="✗${dead} gone"
  [ "$NARROW" -eq 1 ] && [ -n "$rdead" ] && rdead="✗${dead}"
  rdead="${DIM}$(pad "$rdead" "$W_COMMITS")${R}"
  rpl=$(pr_line "$ghrepo" "$head"); rci=$(printf '%s' "$rpl" | cut -f5)
  case "$rci" in
    SUCCESS) rcistr="${GRN}CI ✓${R}" ;; FAILURE|ERROR) rcistr="${RED}CI ✗${R}" ;;
    PENDING|EXPECTED) rcistr="${YEL}CI …${R}" ;; *) rcistr="" ;;
  esac
  local rhead rplain
  rhead=$(short "$head" $((11 + W_TITLE - ${#name} - 2 - 7)))
  rplain="$name  $rhead"
  local rname="${HEAD1}${name}${R}  ${CYN}${rhead}${R}"
  [ -n "$rpr" ] && { rname="$rname $rpr"; rplain="$rplain #$(printf '%s' "$rpl" | cut -f3)"; }
  last=$(git -C "$dir" log -1 --format='%cr · %s' 2>/dev/null)
  { printf '%s%s %s %s %s %s\037  %s%s%s\t%s\n' \
      "$rname" "$(printf '%*s' $(( ${#rplain} < 11 + W_TITLE ? 11 + W_TITLE - ${#rplain} : 0 )) '')" \
      "$rmark" "$rtrack" "$rdead" "$rcistr" \
      "$DIM" "$(short "$last" $((W_TITLE + W_STATS + 8)))" "$R" "$dir"; } > "$out"

  # Worktrees are two-line cards; \037 marks the inner line break until fzf's --read0 sees it.
  local wt br wdirty title action mark repobase
  repobase=$(preview_base "$dir")
  while IFS= read -r wt; do
    [ -z "$wt" ] && continue
    [ "$wt" = "$dir" ] && continue
    if [ "$vparked" -eq 1 ]; then
      [ "$rparked" -eq 1 ] || is_parked "$wt" || continue
      nshown=$((nshown+1))
    else
      is_parked "$wt" && continue
    fi
    interesting=1; nwt=$((nwt+1))
    br=$(git -C "$wt" branch --show-current 2>/dev/null); [ -n "$br" ] || br="(detached)"
    wdirty=$(git -C "$wt" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    if [ "$wdirty" -gt 0 ]; then mark="${YEL}$(pad "●$wdirty" 3)${R}"; else mark="${GRN}$(pad "✓" 3)${R}"; fi

    local pl wpr wname ci base
    pl=$(pr_line "$ghrepo" "$br")
    wpr=$(pr_for "$ghrepo" "$br")
    wname=$(printf '%s' "$wpr" | sed $'s/\033\\[[0-9;]*m//g')
    wname="${B}${wpr}${R}$(printf '%*s' $(( ${#wname} < 6 ? 6 - ${#wname} : 0 )) '')"
    ci=$(printf '%s' "$pl" | cut -f5); base=$(printf '%s' "$pl" | cut -f6)
    base=${base:+origin/$base}; base=${base:-$repobase}

    title=""; action=""
    case "$wt" in "$REPOS"/*) ;; *) title="⚠ outside ~/Repositories";; esac
    if [ -z "$title" ] && [ -f "${SESSION_TSV:-}" ]; then
      IFS=$'\t' read -r title action < <(awk -F'\t' -v p="$wt" '$1==p{print $2 "\t" $3; exit}' "$SESSION_TSV")
    fi
    # Titles lead with "repo number · " — the row already shows both.
    case "$title" in *" · "*) title="${title#* · }";; esac
    # A session outlives the PR it was named for, so the PR's own title wins.
    local prtitle; prtitle=$(printf '%s' "$pl" | cut -f7)
    case "$title" in "⚠"*) ;; *) [ -n "$prtitle" ] && title=$prtitle ;; esac
    if [ -z "$title" ]; then
      if [ "$br" = "(detached)" ]; then title=${wt##*/}; else title=${br#*/}; fi
    fi

    local ins=0 del=0 commits=0 diff cstr cistr stat
    if [ -n "$base" ]; then
      commits=$(git -C "$wt" rev-list --count "$base..HEAD" 2>/dev/null || echo 0)
      stat=$(git -C "$wt" diff --shortstat "$base...HEAD" 2>/dev/null)
      ins=$(printf '%s' "$stat" | sed -n 's/.* \([0-9]*\) insertion.*/\1/p'); ins=${ins:-0}
      del=$(printf '%s' "$stat" | sed -n 's/.* \([0-9]*\) deletion.*/\1/p'); del=${del:-0}
    fi
    diff=""; [ "$commits" -gt 0 ] && diff="${GRN}+${ins}${R} ${RED}-${del}${R}"
    local dplain="+${ins} -${del}"; [ "$commits" -gt 0 ] || dplain=""
    diff="$diff$(printf '%*s' $(( ${#dplain} < W_DIFF ? W_DIFF - ${#dplain} : 0 )) '')"
    cstr=""
    if [ "$commits" -gt 0 ]; then
      if [ "$NARROW" -eq 1 ]; then cstr="${commits}c"
      elif [ "$commits" -eq 1 ]; then cstr="1 commit"; else cstr="$commits commits"; fi
    fi
    cstr="${DIM}$(pad "$cstr" "$W_COMMITS")${R}"
    case "$ci" in
      SUCCESS) cistr="${GRN}CI ✓${R}" ;;
      FAILURE|ERROR) cistr="${RED}CI ✗${R}" ;;
      PENDING|EXPECTED) cistr="${YEL}CI …${R}" ;;
      *) cistr="" ;;
    esac

    local line2="${CYN}${DIM}${br}${R}"
    [ -n "$action" ] && line2="$line2  ${YEL}⚑ $(short "$action" $((W_TITLE - ${#br} - 4 > 10 ? W_TITLE - ${#br} - 4 : 10)))${R}"
    printf '  %s└%s %s %s %s %s %s\037           %s\t%s\n' \
      "$DIM" "$R" "$wname" "${TITLE}$(pad "$(short "$title" "$W_TITLE")" "$W_TITLE")${R}" \
      "$mark" "$diff $cstr" "$cistr" "$line2" "$wt" >> "$out"
  done < <(git -C "$dir" worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2}')

  if [ "$vparked" -eq 1 ]; then
    printf '%s\t%s\t%s\n' "$nwt" "$dirty" "$dead" > "$out.stats"
    [ "$rparked" -eq 1 ] || [ "$nshown" -gt 0 ] || : > "$out"
    return 0
  fi

  if [ "$DEAD" -eq 1 ] && [ "$dead" -gt 0 ]; then
    interesting=1
    git -C "$dir" for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads 2>/dev/null \
      | grep 'gone' | awk '{print $1}' \
      | while IFS= read -r br; do printf '  %s✗ %s%s\t%s\n' "$DIM" "$(short "$br" "$W_DEAD")" "$R" "$dir" >> "$out"; done
  fi

  printf '%s\t%s\t%s\n' "$nwt" "$dirty" "$dead" > "$out.stats"
  if [ "$ACTIVE" -eq 1 ]; then
    [ "$nwt" -gt 0 ] || : > "$out"
  else
    [ "$ALL" -eq 1 ] || [ "$interesting" -eq 1 ] || : > "$out"
  fi
}
export -f scan_repo

build_sessions() {
  SESSION_TSV=""
  [ -d "$SESSION_STORE" ] || return 0
  command -v jq >/dev/null || return 0
  SESSION_TSV=$(mktemp)
  find "$SESSION_STORE" -name '*.json' -print0 2>/dev/null \
    | xargs -0 jq -r 'select(.isArchived != true) | select((.worktreePath // .cwd) != null)
                      | [(.worktreePath // .cwd), (.title // "untitled"),
                         (.postTurnSummary.needs_action // "")] | @tsv' 2>/dev/null \
    > "$SESSION_TSV"
  export SESSION_TSV
}

preview_target() {
  local t=$1
  case "$t" in
    "") ;;
    http*)
      command -v gh >/dev/null || return 0
      gh pr view "$t" --json number,title,author,additions,deletions,changedFiles,body,reviewRequests,latestReviews,statusCheckRollup \
        --jq '
          def checks: [.statusCheckRollup[]? | (.conclusion // .state // .status)];
          "\u001b[1;95m#\(.number)\u001b[0m \u001b[1;97m\(.title)\u001b[0m",
          "  @\(.author.login)  \u001b[32m+\(.additions)\u001b[0m \u001b[31m-\(.deletions)\u001b[0m  \(.changedFiles) files"
            + (checks as $c | if ($c | length) == 0 then ""
               elif any($c[]; . == "FAILURE" or . == "ERROR" or . == "TIMED_OUT") then "  \u001b[31mCI failing\u001b[0m"
               elif any($c[]; . == "IN_PROGRESS" or . == "QUEUED" or . == "PENDING" or . == "EXPECTED") then "  \u001b[33mCI running\u001b[0m"
               else "  \u001b[32mCI green\u001b[0m" end),
          "",
          "\u001b[35m── reviews ──\u001b[0m",
          (.latestReviews[]? | "  \(.author.login)  " + (if .state == "APPROVED" then "\u001b[32mapproved\u001b[0m"
             elif .state == "CHANGES_REQUESTED" then "\u001b[31mchanges requested\u001b[0m" else "\u001b[2m\(.state | ascii_downcase)\u001b[0m" end)),
          (.reviewRequests[]? | "  \(.login // .name)  \u001b[33mrequested\u001b[0m"),
          "",
          "\u001b[35m── description ──\u001b[0m",
          (.body | split("\n") | .[0:25][])' 2>/dev/null
      ;;
    *.code-workspace)
      printf '\033[1;33m%s\033[0m\n\n\033[35m── folders ──\033[0m\n' "${t##*/}"
      command -v jq >/dev/null && jsonc "$t" | jq -r '.folders[]?.path | "  \u001b[36m" + . + "\u001b[0m"' 2>/dev/null
      local cfg="${t%.code-workspace}.claude-code.json"
      [ -f "$cfg" ] && { printf '\n\033[35m── claude-code config ──\033[0m\n  '; jsonc "$cfg" | jq -r '.name' 2>/dev/null; }
      ;;
    *)
      local br pr base
      br=$(git -C "$t" branch --show-current 2>/dev/null)
      printf '\033[1;36m%s\033[0m  \033[2m%s\033[0m\n' "${br:-(detached)}" "$t"
      preview_session "$t"
      [ -n "$br" ] && pr=$(preview_pr "$t" "$br")
      if [ -n "$pr" ]; then
        printf '%s\n' "$pr" | sed '1d'
        base=$(printf '%s' "$pr" | head -1)
      fi
      [ -n "$base" ] || base=$(preview_base "$t")

      local logfmt='%C(yellow)%h%C(reset) %s %C(green)%cr%C(reset) %C(blue)%an%C(reset)%C(auto)%d'
      printf '\n\033[35m── status ──\033[0m\n'
      git -C "$t" -c color.status=always status -sb 2>/dev/null | head -15
      # Only a branch with its own commits gets the base..branch view; the base itself shows history.
      if [ -n "$base" ] && [ "$(git -C "$t" rev-list --count "$base..HEAD" 2>/dev/null || echo 0)" -gt 0 ] \
         && [ "${br#heads/}" != "${base#origin/}" ]; then
        printf '\n\033[35m── %s..%s ──\033[0m\n' "${base#origin/}" "$br"
        git -C "$t" log --color=always --format="$logfmt" "$base..HEAD" 2>/dev/null | head -15
        git -C "$t" diff --shortstat "$base...HEAD" 2>/dev/null \
          | sed -E $'s/^ */  /; s/([0-9]+ insertions?\\(\\+\\))/\033[32m\\1\033[0m/; s/([0-9]+ deletions?\\(-\\))/\033[31m\\1\033[0m/'
      else
        printf '\n\033[35m── recent ──\033[0m\n'
        git -C "$t" log --color=always --format="$logfmt" -12 2>/dev/null
      fi
      ;;
  esac
}

preview_base() {   # the integration branch this repo merges into
  local b
  for b in $RD_BASES; do
    git -C "$1" rev-parse --verify --quiet "origin/$b" >/dev/null && { printf 'origin/%s' "$b"; return; }
  done
}
export -f preview_base

preview_session() {   # the Claude session parked here: title, age, what it last said
  [ -d "$SESSION_STORE" ] && command -v jq >/dev/null || return 0
  find "$SESSION_STORE" -name '*.json' -print0 2>/dev/null \
    | xargs -0 jq -r --arg p "$1" '
        select(.isArchived != true) | select((.worktreePath // .cwd) == $p)
        | [(.lastActivityAt // 0), (.title // "untitled"),
           (.postTurnSummary.status_detail // ""), (.postTurnSummary.needs_action // "")] | @tsv' 2>/dev/null \
    | sort -rn | head -1 \
    | while IFS=$'\t' read -r at title detail action; do
        local ago=$(( ($(date +%s) - at / 1000) / 60 )) when
        if [ "$ago" -lt 60 ]; then when="${ago}m ago"
        elif [ "$ago" -lt 1440 ]; then when="$((ago / 60))h ago"
        else when="$((ago / 1440))d ago"; fi
        printf '\033[1;34m▸ %s\033[0m \033[2m· %s\033[0m\n' "$title" "$when"
        [ -n "$detail" ] && printf '  %s\n' "$detail"
        [ -n "$action" ] && printf '  \033[33m⚑ %s\033[0m\n' "$action"
      done
}

preview_pr() {   # line 1: the PR's base ref; the rest: a summary block. Cached a minute.
  command -v gh >/dev/null || return 0
  local cache="$HOME/.cache/repo-dash/pr-$(printf '%s' "$1:$2" | cksum | cut -d' ' -f1).json"
  if ! [ -s "$cache" ] || [ -n "$(find "$cache" -mmin +1 2>/dev/null)" ]; then
    mkdir -p "${cache%/*}"
    (cd "$1" && gh pr view "$2" --json number,title,url,isDraft,reviewDecision,baseRefName,additions,deletions,statusCheckRollup) \
      > "$cache.tmp" 2>/dev/null && mv "$cache.tmp" "$cache" || { rm -f "$cache.tmp"; : > "$cache"; }
  fi
  [ -s "$cache" ] || return 0
  jq -r '
    def checks: [.statusCheckRollup[]? | (.conclusion // .state // .status)];
    "origin/" + .baseRefName,
    "\u001b[1;95m#\(.number)\u001b[0m \u001b[1;97m\(.title)\u001b[0m",
    "  " + (if .isDraft then "\u001b[2mdraft\u001b[0m"
            elif .reviewDecision == "APPROVED" then "\u001b[32mapproved\u001b[0m"
            elif .reviewDecision == "CHANGES_REQUESTED" then "\u001b[31mchanges requested\u001b[0m"
            else "\u001b[33mreview needed\u001b[0m" end)
      + "  \u001b[32m+\(.additions)\u001b[0m \u001b[31m-\(.deletions)\u001b[0m"
      + (checks as $c | if ($c | length) == 0 then ""
         elif any($c[]; . == "FAILURE" or . == "ERROR" or . == "TIMED_OUT") then "  \u001b[31mCI failing\u001b[0m"
         elif any($c[]; . == "IN_PROGRESS" or . == "QUEUED" or . == "PENDING" or . == "EXPECTED") then "  \u001b[33mCI running\u001b[0m"
         else "  \u001b[32mCI green\u001b[0m" end),
    "  \u001b[2m\(.url)\u001b[0m"' "$cache" 2>/dev/null
}

list_workspaces() {   # the _*.code-workspace multi-root workspaces
  local ws slug name
  for ws in "$REPOS"/_*.code-workspace; do
    [ -f "$ws" ] || continue
    slug=${ws##*/_}; slug=${slug%.code-workspace}
    name=$slug
    [ -f "$REPOS/_$slug.claude-code.json" ] && command -v jq >/dev/null \
      && name=$(jsonc "$REPOS/_$slug.claude-code.json" | jq -r '.name // empty' 2>/dev/null)
    [ -n "$name" ] || name=$slug
    printf '%sWS%s %s%-*s%s %sworkspace%s\t%s\n' \
      "$YEL" "$R" "$B" "$W_WS" "$(short "$name" "$W_WS")" "$R" "$DIM" "$R" "$ws"
  done
}

pick() {   # live dashboard inside fzf: searchable, self-refreshing, openable
  command -v fzf >/dev/null || { echo "--pick needs fzf" >&2; exit 1; }
  command -v code >/dev/null || { echo "--pick needs the 'code' command on PATH" >&2; exit 1; }

  local self rowargs rowcmd rowcols hintcmd
  self=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")

  rowargs=""
  [ "$ALL" -eq 1 ]    && rowargs="$rowargs --all"
  [ "$ACTIVE" -eq 1 ] && rowargs="$rowargs --active"
  [ "$DEAD" -eq 1 ]   && rowargs="$rowargs --dead"
  [ "$PR" -eq 1 ]     && rowargs="$rowargs --pr"
  [ "$NARROW" -eq 1 ] && rowargs="$rowargs --narrow"
  rowcols="COLUMNS=$TERM_COLS LINES=$TERM_ROWS"


  # Normal mode is plain keys; / hands them back to the query until enter or esc.
  local keys='c,p,g,m,n,x,z,v,r,?,j,k,q,left,right,1,2,3,4'
  sumfile=$(mktemp); portfile=$(mktemp)
  viewfile=$(mktemp); echo repos > "$viewfile"
  legendfile=$(mktemp)
  headercmd="'$self' --header '$viewfile' '$sumfile' '$legendfile'"
  rowcmd="$rowcols RD_FORCE_COLOR=1 RD_SUMMARY_FILE='$sumfile' RD_VIEW_FILE='$viewfile' '$self' --rows$rowargs"
  # Tab switches draw the tab's last rows at once and rebuild them in the background.
  cachedcmd="RD_CACHED=1 $rowcmd"
  RD_ROWCMD=$rowcmd; RD_CACHEDCMD=$cachedcmd; export RD_ROWCMD RD_CACHEDCMD
  local nexttab prevtab
  jumptab() { printf "execute-silent('%s' --set-tab '%s' %s)+reload-sync(%s)+first+execute-silent('%s' --bg-refresh '%s')" \
    "$self" "$viewfile" "$1" "$cachedcmd" "$self" "$portfile"; }
  nexttab="execute-silent('$self' --toggle-tab '$viewfile' 1)+reload-sync($cachedcmd)+first+execute-silent('$self' --bg-refresh '$portfile')"
  prevtab="execute-silent('$self' --toggle-tab '$viewfile' -1)+reload-sync($cachedcmd)+first+execute-silent('$self' --bg-refresh '$portfile')"

  # nudge fzf to reload itself every INTERVAL seconds over its own HTTP port
  ( while :; do
      sleep "$INTERVAL"
      port=$(cat "$portfile" 2>/dev/null) || continue
      [ -n "$port" ] || continue
      curl -s -XPOST "localhost:$port" -d "reload-sync($rowcmd)" >/dev/null 2>&1 || exit 0
    done ) >/dev/null 2>&1 </dev/null &
  refresher=$!
  trap 'kill "${refresher:-}" 2>/dev/null; rm -f "${sumfile:-}" "${portfile:-}" "${viewfile:-}" "${legendfile:-}" "${SESSION_TSV:-}"' EXIT INT TERM

  RD_CACHED=1 RD_SUMMARY_FILE="$sumfile" RD_VIEW_FILE="$viewfile" rows | fzf \
    --read0 --highlight-line \
    --ansi --delimiter=$'\t' --with-nth=1 \
    --height=100% --layout=reverse --border=rounded --info=inline \
    --border-label-pos=2 --prompt='/ ' --header-first --track --no-input \
    --listen \
    --preview="'$self' --preview {2}" --preview-window="$PREVIEW_WIN" \
    --bind "start:execute-silent(echo \$FZF_PORT > '$portfile'; '$self' --bg-refresh '$portfile')" \
    --bind "load:transform-header($headercmd)+transform-border-label('$self' --tabs '$viewfile')" \
    --bind "resize:transform-header($headercmd)+transform-border-label('$self' --tabs '$viewfile')" \
    --bind "/:show-input+unbind($keys)" \
    --bind "enter:transform:[ \"\$FZF_INPUT_STATE\" = hidden ] && echo \"execute-silent('$self' --open {2})\" || echo \"hide-input+rebind($keys)+transform-header($headercmd)\"" \
    --bind "esc:transform:if [ \"\$FZF_INPUT_STATE\" != hidden ]; then echo \"clear-query+hide-input+rebind($keys)+transform-header($headercmd)\"; elif [ -n \"\$FZF_QUERY\" ]; then echo \"clear-query+transform-header($headercmd)\"; else echo abort; fi" \
    --bind "q:abort" \
    --bind "j:down,k:up" \
    --bind "v:toggle-preview" \
    --bind "?:execute-silent([ -s '$legendfile' ] && : > '$legendfile' || echo on > '$legendfile')+transform-header($headercmd)" \
    --bind "r:reload-sync($rowcmd)" \
    --bind "tab:$nexttab,right:$nexttab" \
    --bind "shift-tab:$prevtab,left:$prevtab" \
    --bind "1:$(jumptab repos),2:$(jumptab prs),3:$(jumptab workspaces),4:$(jumptab parked)" \
    --bind "m:execute('$self' --merge {2})+reload-sync($rowcmd)" \
    --bind "z:execute-silent('$self' --toggle-park {2})+exclude+execute-silent('$self' --bg-refresh '$portfile' force)" \
    --bind "p:execute-silent('$self' --open-pr {2})" \
    --bind "g:execute-silent('$self' --open-repo {2})" \
    --bind "c:execute-silent('$self' --open-claude {2})" \
    --bind "n:execute-silent(code -n {2})" \
    --bind "x:become(code -r {2})" \
    >/dev/null
  kill "${refresher:-}" 2>/dev/null
}

scan_all() {   # every repo+worktree row, each with a trailing tab + path
  local repos=() d tmp n_wt=0 n_dirty=0 n_dead=0 f
  for d in "$REPOS"/*/; do
    d=${d%/}
    [ -d "$d/.git" ] || continue     # a worktree has .git as a file — it lists under its parent
    repos+=("$d")
  done

  tmp=$(mktemp -d)
  printf '%s\0' "${repos[@]}" \
    | xargs -0 -P "$JOBS" -I{} bash -c 'scan_repo "$1" "'"$tmp"'/$(basename "$1")"' _ {} 2>/dev/null

  for f in "$tmp"/*; do
    case "$f" in *.stats) continue;; esac
    [ -s "$f" ] && cat "$f"
  done

  for f in "$tmp"/*.stats; do
    [ -f "$f" ] || continue
    IFS=$'\t' read -r a b c < "$f"
    n_wt=$((n_wt + a)); [ "$b" -gt 0 ] && n_dirty=$((n_dirty+1)); n_dead=$((n_dead + c))
  done
  rm -rf "$tmp"

  local n_parked; n_parked=$(awk 'END{print NR}' "$PARKED_FILE" 2>/dev/null)
  [ "${VIEW:-}" = parked ] || { mkdir -p "$HOME/.cache/repo-dash"; printf '%s\n' "$n_wt" > "$HOME/.cache/repo-dash/count-repos"; }
  SUMMARY=$(printf '%s%s repos · %s worktrees · %s dirty · %s dead branches · %s parked · %s%s' \
    "$DIM" "${#repos[@]}" "$n_wt" "$n_dirty" "$n_dead" "${n_parked:-0}" "$(date '+%H:%M:%S')" "$R")
  [ -n "${RD_SUMMARY_FILE:-}" ] && printf "%s\n" "$SUMMARY" > "$RD_SUMMARY_FILE"
  return 0
}

legend() {
  printf '%s\n' "$SUMMARY"
  if [ "$NARROW" -eq 1 ]; then
    printf '%s%s●%s dirty %s↑%s ahead %s↓%s behind %s✗%s gone %s⚑%s Claude asks%s\n' \
      "$DIM" "$YEL" "$DIM" "$GRN" "$DIM" "$RED" "$DIM" "$DIM" "$DIM" "$YEL" "$DIM" "$R"
  else
    printf '%s%s●n%s uncommitted  %s↑n%s unpushed  %s↓n%s behind  %s✗n%s upstream gone  %s⚑%s Claude needs you%s\n' \
      "$DIM" "$YEL" "$DIM" "$GRN" "$DIM" "$RED" "$DIM" "$DIM" "$DIM" "$YEL" "$DIM" "$R"
    [ "$PR" -eq 1 ] && printf '%s%s#n%s draft  %s#n%s review needed  %s#n%s approved  %sCI ✓ ✗ …%s\n' \
      "$DIM" "$DIM" "$DIM" "$YEL" "$DIM" "$GRN" "$DIM" "$DIM" "$R"
  fi
  return 0
}

render() {   # plain, non-interactive: same rows with the path column stripped
  local sf body
  sf=$(mktemp)
  body=$(RD_SUMMARY_FILE="$sf" scan_all)
  printf '%s%s%s  %s%s%s\n\n' "$B" "REPOSITORIES" "$R" "$DIM" "$(date '+%H:%M')" "$R"
  printf '%s\n' "$body" | tr '\037' '\n' | cut -f1
  printf '\n'
  cat "$sf" 2>/dev/null
  rm -f "$sf"
}

build_pr_list() {   # every open PR of mine, plus the ones waiting on my review
  command -v gh >/dev/null || return 0
  local cache="$HOME/.cache/repo-dash/pr-list-v1.tsv"; mkdir -p "${cache%/*}"
  if [ -s "$cache" ] && [ -z "$(find "$cache" -mmin +5 2>/dev/null)" ]; then return 0; fi
  gh api graphql -f query='
    fragment pr on PullRequest {
      number title url updatedAt isDraft reviewDecision mergeStateStatus baseRefName headRefName
      repository { name nameWithOwner } author { login }
      latestReviews(first: 10) { nodes { state author { login } } }
      reviewRequests(first: 5) { nodes { requestedReviewer { ... on User { login } ... on Team { name } } } }
      commits(last: 1) { nodes { commit { statusCheckRollup { state } } } } }
    { toMe: search(query: "'"$ORG_Q"'is:pr is:open review-requested:@me", type: ISSUE, first: 50) { nodes { ...pr } }
      mine: search(query: "'"$ORG_Q"'is:pr is:open author:@me", type: ISSUE, first: 100) { nodes { ...pr } } }' \
    --jq '
      # "-" stands in for empty: bash read collapses consecutive tabs
      def orDash: if . == null or . == "" then "-" else . end;
      def fresh: ((now - (.updatedAt | fromdateiso8601)) / 86400) < 90;
      def by(s): [.latestReviews.nodes[] | select(.state == s) | .author.login] | join(", ");
      # which group a PR of mine sits in, by what stands between it and merged
      def kind:
        if (fresh | not) then "stale"
        elif .isDraft then "draft"
        elif .reviewDecision == "APPROVED" then
          (if (.mergeStateStatus | IN("CLEAN", "HAS_HOOKS", "UNSTABLE")) then "ready" else "stuck" end)
        elif .reviewDecision == "CHANGES_REQUESTED" then "changes"
        else "review" end;
      def row(k): [k, .repository.name, (.number | tostring), (.title | gsub("\t"; " ")), .url, .author.login,
        (((now - (.updatedAt | fromdateiso8601)) / 3600) as $h
          | if $h < 1 then "now" elif $h < 24 then "\($h | floor)h" elif $h < 2400 then "\($h / 24 | floor)d"
            elif $h < 8760 then "\($h / 168 | floor)w" else "\($h / 8760 | floor)y" end),
        (.commits.nodes[0].commit.statusCheckRollup.state | orDash),
        ([.reviewRequests.nodes[].requestedReviewer | (.login // .name) | select(.)] | join(", ") | orDash),
        (.reviewDecision | orDash), (.mergeStateStatus | orDash),
        ((if k == "changes" then by("CHANGES_REQUESTED") else by("APPROVED") end) | orDash),
        .repository.nameWithOwner, .baseRefName, .headRefName] | @tsv;
      (.data.toMe.nodes[] | select(fresh) | row("in")), (.data.mine.nodes[] | row(kind))' \
    > "$cache.tmp" 2>/dev/null || { rm -f "$cache.tmp"; return 0; }
  # How far each of my PRs trails its target branch — one compare call each, in parallel.
  local tmpd i=0 line kind nwo base head
  tmpd=$(mktemp -d)
  while IFS= read -r line; do
    i=$((i + 1))
    kind=${line%%$'\t'*}
    nwo=$(printf '%s' "$line" | cut -f13); base=$(printf '%s' "$line" | cut -f14); head=$(printf '%s' "$line" | cut -f15)
    if [ "$kind" = in ]; then printf '%s\t-\n' "$line" > "$tmpd/$i"
    else
      ( b=$(gh api "repos/$nwo/compare/$base...$head" --jq .behind_by 2>/dev/null)
        printf '%s\t%s\n' "$line" "${b:--}" > "$tmpd/$i" ) &
    fi
  done < "$cache.tmp"
  wait
  for ((n = 1; n <= i; n++)); do cat "$tmpd/$n"; done > "$cache.tmp"
  rm -rf "$tmpd"
  mv "$cache.tmp" "$cache"
}

list_prs() {   # the PRs tab: grouped by what stands between each PR and merged
  local cache="$HOME/.cache/repo-dash/pr-list-v1.tsv" kind heading n
  for kind in in ready stuck changes review draft stale; do
    n=$(awk -F'\t' -v k="$kind" '$1==k' "$cache" 2>/dev/null | wc -l | tr -d ' ')
    [ "$n" -gt 0 ] || [ "$kind" = in ] || continue
    case "$kind" in
      in)      heading="WAITING ON YOUR REVIEW" ;;
      ready)   heading="READY TO MERGE" ;;
      stuck)   heading="APPROVED, NOT MERGEABLE YET" ;;
      changes) heading="CHANGES REQUESTED" ;;
      review)  heading="IN REVIEW" ;;
      draft)   heading="DRAFTS" ;;
      stale)   heading="STALE · untouched 90+ days" ;;
    esac
    printf '%s%s%s (%s)%s\t\n' "$B" "$heading" "$R$DIM" "$n" "$R"
    awk -F'\t' -v k="$kind" '$1==k' "$cache" 2>/dev/null \
      | while IFS=$'\t' read -r _ repo number title url author age ci reviewers decision mstate people _ base _ behind; do
          local who cistr dstr
          case "$ci" in
            SUCCESS) cistr="${GRN}CI ✓${R}" ;; FAILURE|ERROR) cistr="${RED}CI ✗${R}" ;;
            PENDING|EXPECTED) cistr="${YEL}CI …${R}" ;; *) cistr="" ;;
          esac
          # For my PRs, GitHub's merge state is the thing that still stands in the way.
          dstr="$(pad "" "$W_DIFF")"
          if [ "$kind" = draft ] || [ "$kind" = stale ]; then dstr="${DIM}$(pad "$kind" "$W_DIFF")${R}"
          elif [ "$kind" != in ]; then
            case "$mstate" in
              CLEAN|HAS_HOOKS) dstr="${GRN}$(pad "mergeable" "$W_DIFF")${R}" ;;
              DIRTY)    dstr="${RED}$(pad "conflicts" "$W_DIFF")${R}" ;;
              BEHIND)   dstr="${YEL}$(pad "behind" "$W_DIFF")${R}" ;;
              BLOCKED)  dstr="${YEL}$(pad "blocked" "$W_DIFF")${R}" ;;
              UNSTABLE) dstr="${YEL}$(pad "unstable" "$W_DIFF")${R}" ;;
            esac
          fi
          [ "$reviewers" = - ] && reviewers=""
          [ "${people:--}" = - ] && people=""
          local bstr="" bplain=""
          case "${behind:--}" in
            -|"") ;;
            0) bplain="✓"; bstr="${GRN}✓${R}" ;;
            *) bplain="↓$behind"; bstr="${RED}↓${behind}${R}" ;;
          esac
          bstr="$bstr$(printf '%*s' $(( ${#bplain} < W_COMMITS ? W_COMMITS - ${#bplain} : 0 )) '')"
          [ "$kind" != in ] && [ -n "$bplain" ] && [ "${base:--}" != - ] && repo="$repo → $base"
          case "$kind" in
            in)          who="@$author" ;;
            ready|stuck) who="approved by ${people:-someone}" ;;
            changes)     who="changes from ${people:-a reviewer}" ;;
            draft)       who="not ready for review" ;;
            stale)       who="last touched $age ago" ;;
            *)           who="waiting on ${reviewers:-anyone}" ;;
          esac
          printf '  %s└%s %s %s %s %s %s %s\037           %s%s · %s%s\t%s\n' \
            "$DIM" "$R" "${B}$(pad "#$number" 6)${R}" "${TITLE}$(pad "$(short "$title" "$W_TITLE")" "$W_TITLE")${R}" \
            "${DIM}$(pad "$age" 3)${R}" "$dstr" "$bstr" "$cistr" \
            "$CYN$DIM" "$repo" "$who" "$R" "$url"
        done
  done
}

build_rows() {   # the current tab: repos and worktrees, PRs, workspaces, or parked
  VIEW=$(cat "${RD_VIEW_FILE:-/dev/null}" 2>/dev/null); export VIEW
  case "$VIEW" in
    workspaces) list_workspaces ;;
    prs)        list_prs ;;
    parked)     scan_all
                [ -s "$PARKED_FILE" ] || printf '  %snothing parked · z on a repo or worktree holds it here%s\t\n' "$DIM" "$R" ;;
    *)          scan_all ;;
  esac
}

[ -n "${PREVIEW_TARGET:-}" ] && { preview_target "$PREVIEW_TARGET"; exit 0; }

row_cache() {   # the last rows drawn for this tab, keyed by everything that shapes them
  local view; view=$(cat "${RD_VIEW_FILE:-/dev/null}" 2>/dev/null)
  printf '%s/.cache/repo-dash/rows-%s' "$HOME" \
    "$(printf '%s' "${view:-repos} $TERM_COLS $ALL$ACTIVE$DEAD$PR$NARROW" | cksum | cut -d' ' -f1)"
}

rows() {   # RD_CACHED: serve the cache if there is one · RD_REFRESH: skip a rebuild that's seconds old
  local cache; cache=$(row_cache)
  if [ -n "${RD_CACHED:-}" ] && [ -s "$cache" ]; then cat "$cache"; return 0; fi
  [ "${RD_REFRESH:-}" = 1 ] && [ -n "$(find "$cache" -mtime -15s 2>/dev/null)" ] && return 0
  mkdir -p "${cache%/*}"
  build_sessions; build_prs; build_pr_list
  build_rows | tr '\n\037' '\0\n' > "$cache.$$" && mv "$cache.$$" "$cache"
  [ -n "${RD_REFRESH:-}" ] || cat "$cache"
}

if [ "$ROWS" -eq 1 ]; then
  rows
  [ -n "${SESSION_TSV:-}" ] && rm -f "$SESSION_TSV"
  exit 0
fi

build_sessions
build_prs
{ [ "$PICK" -eq 1 ] || [ "$WATCH" -eq 1 ]; } && build_pr_list
trap '[ -n "${SESSION_TSV:-}" ] && rm -f "$SESSION_TSV"' EXIT

if [ "$PICK" -eq 1 ] || [ "$WATCH" -eq 1 ]; then
  pick
else
  render
fi
