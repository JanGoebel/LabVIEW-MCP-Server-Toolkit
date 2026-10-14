# Working on the LabVIEW MCP Server Toolkit with Claude Code

Instructions for Claude Code sessions in this repository. They describe how
work is done here: who decides what, how LabVIEW code is changed, and how
commits and pull requests are structured.

## The project

A LabVIEW toolkit that turns VIs into an MCP server over HTTP (tools, prompts,
resources). Built on the IG HTTP Server Toolkit and JSONtext.

| Path | Content |
|---|---|
| `src/MCP Server/` | The toolkit: `MCP Server.lvlib` and the `MCP Handler.lvclass` HTTP handler |
| `src/*.vipb`, `src/*.vipc` | Package build specification and runtime dependencies |
| `tests/` | Caraya tests (`MCP Server tests.lvlib`); `Run_Tests_CLI.vi` is the CI entry point |
| `examples/` | Example servers. In this repo they load the toolkit from `src`, not from an installed package |
| `tools/ci/` | Pull request review scripts and the workflow template |
| `tools/setup/`, `tools/test/` | Environment setup and the protocol tester, where present |
| `.github/workflows/` | CI. Maintainer-only, see below |

## Who decides what

- The maintainer reviews and merges every pull request. Never merge, and never
  push to `main`.
- Releases are the maintainer's: never create or push tags, never create
  releases, never trigger the release workflow.
- Files under `.github/workflows/` are changed by the maintainer only. The
  token used here cannot push them. Put workflow changes in `tools/ci/` as a
  template and describe the exact edit in the pull request.
- GitHub settings (rulesets, variables, runners, environments) are the
  maintainer's. Say what is needed; do not try to change them.
- Never ask for tokens, passwords or serial numbers in chat. Sign-ins happen in
  the maintainer's own terminal.

## Branches

- Always work on a branch created from `origin/main` after `git fetch`. Name it
  after the change (`http-transport-behaviour`, `fix-package-build`).
- One topic per branch and pull request. Unrelated work gets its own branch,
  even when it comes up in the same session.
- If work depends on an open pull request, branch from that pull request's
  branch and say so in the description.
- VIs are binary and cannot be merged. Do not open two pull requests that edit
  the same VI; if two tasks need the same VI, say so and ask which goes first.
- Follow-up changes to an open pull request are new commits on its branch,
  announced with a short update comment (see "Pull requests").
  The pull request updates itself; do not open a new one.

## Changing LabVIEW code

- Delegate creating and editing VIs, classes and tests to the `labview-mcp`
  agents (`labview-vi-editor`, `labview-vi-generator`, and so on). Continue the
  same agent for follow-up work so it keeps its context. Reading VIs (exporting
  them to AIXML to inspect a diagram) can be done directly.
- Edit existing VIs in place. Never regenerate a VI that has a designed front
  panel or a hand-drawn diagram; if an in-place edit is not possible, stop and
  say so.
- Every VI is saved in LabVIEW 20.0 format, source-only, with its owning
  library recorded. In LabVIEW 2026 that means saving from inside
  `src/LabVIEW MCP Server SDK.lvproj`. Check the saved file, do not assume.
- New VIs become members of the right library folder (`Private/SubVIs`,
  `Private/RPC Methods`, the `tests` folder of the test library) and get an
  icon in the existing style: green "MCP" banner for toolkit VIs, red banner
  for tests. No default icons.
- "It generated" is not "it works". Check `Execution:State` and run the code.
- The LabVIEW tools need 64-bit LabVIEW 2026 with Nigel open. Do not call
  `lvai_ensure_labview`: it starts the 32-bit LabVIEW, which has none of the
  toolkits, and clears the auto-save folder. If LabVIEW is not reachable, ask.
- A running example server locks `MCP Server.lvlib`. Stop it through its Stop
  button (never abort it) before editing, and restart it afterwards if the
  maintainer was using it.
- LabVIEW dialogs that concern only files of this repository or scratch files
  may be dismissed without saving. Stop and ask for anything else.
- LabVIEW rewrites `*.aliases` and `*.lvlps` when a project is opened. Never
  commit those; restore them.

## Verifying before a pull request

- Run the full Caraya suite and report per-test results. New behaviour gets a
  test in the same style as the existing ones ("Test N: ...", one VI per test,
  wired into `Test_MCP_Server.vi`). Show at least one new test failing against
  a wrong expectation, so it is known that it can fail.
- Protocol behaviour is checked against a running server with real HTTP
  requests (`tools/test/Test-McpServer.ps1` where present, otherwise curl).
  The Datalogger example is the usual test server.
- If an existing test has to change because behaviour changes on purpose, say
  which test and why. Do not adapt a test silently.
- Say plainly what was measured and what was not. A result from LabVIEW 2026
  is not a result for LabVIEW 2020.

## Commits

- One logical change per commit. Tests go with the change they test or in a
  commit of their own directly after it.
- Subject: imperative, at most about 72 characters, no trailing period
  ("Answer unknown JSON-RPC methods with "method not found"").
- Body: what was wrong or missing, what changes for someone using the toolkit,
  and anything deliberately left out. Describe behaviour, not the editing
  steps. Name new VIs and what each is for.
- Stage files explicitly; never `git add -A` over LabVIEW-rewritten files.
- End with the `Co-Authored-By: Claude ...` line.

## Pull requests

Push the branch and open the pull request once the work is verified locally.
Open it as a draft if something is knowingly unfinished. Title: what the
change does, like a commit subject. Description, in this order:

1. **Summary** - what changes and why, in two or three sentences. A
   before/after table when behaviour changes.
2. **Changes** - per VI or file: new or modified, and what it does. GitHub
   cannot diff VIs, so this text carries the reasoning; the generated diff
   comment (see below) carries the exact changes.
3. **Verified** - what was run, where, with which result.
4. **Not verified** - what was not run or could not be checked.
5. **Known rough edges** - auto-arranged diagrams, overlapping nodes, anything
   the reviewer should tidy or should know.
6. Maintainer steps, if any (workflow edits, settings, variables).

End the description with the "Generated with Claude Code" line.

Every pull request that changes VIs carries one review report comment, kept
short:

- the test result in one line, with the per-test table folded away;
- one row per modified VI with a small screenshot of its latest block diagram
  change;
- added VIs folded away;
- a button that opens the full graphical diff as its own page (the report is
  pushed to the `pr-assets/pr-<number>` branch and rendered by GitHub).

The full diff never goes into the comment itself. The pull request workflow
posts this report and builds a test package. If it is not active or has not
run, produce the same comment locally with `tools/ci/New-ViDiffReport.ps1`,
`tools/ci/Convert-CarayaReport.ps1` and `tools/ci/Publish-PrReport.ps1`, and
say in its footer that it was produced locally. After every push to the
branch, refresh the report so it shows the latest block diagrams.

Whenever new commits are pushed to an open pull request, also post a new,
short comment in its conversation: which commits, what changed in a few
bullets, test result, and what is still open. Update the description too if
it has become inaccurate.

## Reporting back

Lead with the outcome. Then: what changed, what was verified, what was not,
side effects on the machine (servers left running, projects left open,
branches created), and what the maintainer has to do. If a step failed or was
skipped, say so.
