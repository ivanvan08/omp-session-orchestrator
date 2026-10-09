---
name: project-coordinator
description: "Run a Claude-Projects-style project in omp: one coordinator session that turns a stream of tasks into parallel worker threads (full omp sessions in herdr tabs, one git worktree each) via the `proj` CLI. Use when asked to create/open a project, when you are a project's coordinator, or when a `[thread X] STATUS:` message arrives."
---

# Project coordinator

A **project** is one long-running coordinator session plus worker **threads**. Each thread is a full omp
session in its own herdr tab of the project's workspace; code threads get their own git worktree on
branch `proj/<thread>`. Everything goes through the `proj` CLI (`proj --help`). State lives in
`$PROJ_ROOT/<project>/` (default `~/meta/projects/<project>/`):

| File | Purpose | Who writes it |
|---|---|---|
| `PROJECT.md` | goal, repositories, standing instructions for every thread, coordinator preferences | user, or you when the user asks to change a rule |
| `MEMORY.md` | requirements, decisions, pitfalls threads must know | `proj remember` (user, you, threads) |
| `threads.json` | registry: workspace, coordinator, threads (pane, worktree, branch, last status) | `proj` only, never edit by hand |
| `tasks/<thread>-<n>.md` | every task delivered to a thread | `proj spawn/send` |

Requires `HERDR_ENV=1` (running inside herdr), `jq`, `git`; `gh` for PR status.

## Creating or reopening a project (from any session)

- New: `proj init <name> --goal "<one line>" --repo <path> [--repo <path>...]`. The first repo is the
  default for threads. It creates a herdr workspace `proj:<name>` with a `coord` tab running the
  coordinator. Tell the user the workspace id and that they talk to the coordinator there.
- After a herdr restart, or when the coordinator tab was closed: `proj open <name>` (resumes the
  coordinator's session).
- `proj list` shows all projects.

## When you are the coordinator

You route work; threads do it. Read `PROJECT.md` and `MEMORY.md` at the start and whenever the user
says they changed. Follow the "Coordinator preferences" in `PROJECT.md`; they override the defaults below.

### Route every user message

1. **Quick question** (status, "what does X do", a fact you can check in a minute): answer in place.
   Do not start a thread for it.
2. **New work**: start a thread right away, without asking for confirmation:
   `proj spawn <project> <thread> [--repo PATH | --no-repo] [--model M] <<'EOF' ... EOF`
   - Thread name: short kebab-case topic (`fix-login`, `lint-config`), max 16 chars.
   - Default repo is the first one in `PROJECT.md`; pass `--repo` for another, `--no-repo` for research
     or writing that touches no repository.
   - Tell the user which thread you started.
3. **Follow-up in an area a thread already covers**: `proj send <project> <thread> <<'EOF' ... EOF`.
   Check `proj status` for the matching thread first. `send` revives a thread whose tab or process is gone.
4. **Several unrelated tasks in one message**: one thread each, all spawned in the same turn.
5. **"Remember X"** or a correction that applies to the whole project: `proj remember <project> "<X>"`.
   A change to a standing rule goes into `PROJECT.md` (edit it). Facts useful beyond the project go to
   global memory instead.
6. **"Status"**: run `proj status <project>` and summarise by group: waiting-on-you first, then
   ready-for-review, working, idle.

Do the implementation work yourself only when the user explicitly asks you to.

### Pinging the user

In a project workspace the user gets a desktop notification only when a session is `blocked` on a
dialog. Finished turns, yours and the threads', notify nobody. So:

- A question or decision only the user can make: ask it with the `ask` tool. A question written in
  prose in your reply never reaches them.
- Results, summaries, progress: plain replies. The user reads them when they come back.
- Do not keep threads busy for nothing: one thread per real piece of work. A thread's tab closes
  automatically after it reports `done`; `proj send` resumes the same session later.

### Writing a thread task

Threads start blank: they get `PROJECT.md`, `MEMORY.md`, their worktree, and your task, nothing from
this conversation. Each task must stand alone:

- the outcome and why, in the user's terms;
- what this conversation already established: paths, errors, constraints, decisions;
- what is out of scope;
- how to verify it (command, expected result);
- whether to open a PR (default from `PROJECT.md`).

Write tasks in English. `proj` wraps your text with the thread brief (rules, `proj notify` protocol), so
do not repeat those.

### When a thread reports back

Threads finish each turn with `proj notify`, which arrives in your conversation as
`[thread <t>] STATUS: <done|blocked|needs-input> - <summary> (full report: proj report <project> <t>)`.

- `done`: read `proj report <project> <t>` if the summary is not enough, then tell the user in 1-3
  lines what landed (branch/PR). Close the loop with `proj resolve <project> <t>` only after the user's
  last step (merge, acceptance), or when the user says so.
- `blocked` / `needs-input`: if you can answer from the project context or a quick check, answer with
  `proj send`. Otherwise ask the user with the `ask` tool, naming the thread, then pass the answer on
  with `proj send`.
- A thread that needs approval in a dialog cannot be answered through `proj send`; the user already
  got a notification for it. Mention it in your reply only if they ask about the thread.

### Cleanup

- `proj resolve <project> <t> [--close] [--remove-worktree]`: marks it resolved; `--close` closes the
  tab (kills the session), `--remove-worktree` removes the worktree (git refuses if it is dirty) and
  keeps the branch.
- `proj send` to a resolved thread reopens it.

## When you are a thread

Your first message names the project and the rules. The parts that matter most:

- Last tool call of every turn: `proj notify <project> <thread> <done|blocked|needs-input> "<2-4 sentences>"`.
  After `done` your tab closes once the turn ends.
- Questions go to the coordinator via `needs-input`, not to the user via the `ask` tool: the
  coordinator answers what it can and asks the user the rest.
- Then the final message: first line `STATUS: ...`, then what changed, verification, branch/PR, open questions.
- Project-wide lessons: `proj remember <project> "<one line>"`.

## Failure modes

| Symptom | Cause | Action |
|---|---|---|
| `thread X is waiting on a dialog` | the thread shows an ask/approval prompt | user answers in that tab |
| coordinator tab closed | user closed it to free resources | the next `proj notify` or `proj open <project>` resumes it |
| status `offline` | thread tab or process gone before it reported `done` | `proj send` revives it from its session file |
| `branch proj/<t> already exists` | earlier thread with the same name | choose another name, or delete the old branch |
| PR column `error` | `gh` failed (auth, network) | run `gh auth status` |
