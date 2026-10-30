# Pull request review automation

Scripts used by the pull request workflow to show what a pull request changes
and whether it works. GitHub cannot diff VIs, so the review material is
generated and posted as a comment on the pull request.

| File | Purpose |
|---|---|
| `Resolve-CiEnvironment.ps1` | First step of every job: finds the LabVIEW for tests and build (oldest ≥ 2020) and for the VI comparison (newest), their VI Server ports, LabVIEW CLI, `vipm` and `gh`; with `-Fix` repairs VI Server settings and port clashes, and with `-CleanStart` ends a leftover VIPM Desktop and the job's own LabVIEWs (never another LabVIEW, none with unsaved changes unless `CI_DEDICATED_MACHINE=1`); writes `LABVIEW_*` for the following steps and a table to the job summary. |
| `LabVIEWCi.psm1` | Functions shared by the scripts here: LabVIEW discovery, VI Server port resolution, which LabVIEW CI may close, tool lookup, running git and other console tools, Markdown escaping. |
| `New-ViDiffReport.ps1` | Compares every changed `.vi`/`.vim`/`.ctl` with its version on the base branch, using LabVIEW's own comparison (`LabVIEWCLI -OperationName CreateComparisonReport`), and writes a Markdown report with before/after images. Added VIs are shown with their block diagram and front panel. Every case frame of the new version of each VI is added in a folded section. |
| `Print Diagram Frames.vi` | Run by `New-ViDiffReport.ps1` through `LabVIEWCLI -OperationName RunVI`: prints one VI with Print.VI To HTML (one picture per case frame) and lists each frame's structure and selector value in print order. Arguments: VI path, HTML file path, frame list path. LabVIEW 20.0. |
| `Invoke-CliTest.ps1` | Runs a test entry VI (`tests\Run_Tests_CLI.vi`, `tests\Run_Protocol_Tests_CLI.vi`) through `LabVIEWCLI -OperationName RunVI`. Exit code 0 passed, 1 tests failed, 2 LabVIEW not reachable (CLI error -350000), 3 entry VI missing on the branch. Used by both workflows. |
| `Convert-CarayaReport.ps1` | Turns `tests\results\caraya-report.txt`, written by `tests\Run_Tests_CLI.vi`, into a table with one row per test, and adds the protocol tester's result from `tests\results\protocol-report.txt`. Says "did not run" instead of showing failures when LabVIEW was not reachable. |
| `Test-TestsWired.ps1` | Fails when a `test *.vi` member of `tests\MCP Server tests.lvlib` is not called by `tests\Test_MCP_Server.vi`, so a test that was added but not wired in cannot be skipped silently. Reads the VI's link table; no LabVIEW. Exit code is the number of test VIs not called. Review job, before the Caraya suite. |
| `Test-InstalledPackage.ps1` | Tests the package users install: fails on `tools\`, `_ci\`, `tests\`, `.github\`, `builds\`, `.git`, `.ps1` or test-library entries in the `.vip`, installs it with `vipm` into the test LabVIEW, starts the installed Datalogger example (under `<LabVIEW>\examples\MCP Server`, not the repository's) with `Start VI.vi`, runs `tools\test\Test-McpServer.ps1` against it, closes that LabVIEW and uninstalls the package. Refuses to run when the toolkit is already installed there (`-Force`); `-ContentsOnly` checks only the contents. Test-build job, after the package is uploaded. Closing LabVIEW ends everything running in it: do not point it at a LabVIEW someone works in. |
| `Start VI.vi` | Run by `Test-InstalledPackage.ps1` through `LabVIEWCLI -OperationName RunVI`: opens the VI whose path is its first argument and starts it without waiting (Run VI, Auto Dispose Ref), so the CLI call returns while that VI keeps running. RunVI itself only runs VIs with its own connector pane (error 1031 otherwise). Exit Code 1 when no path is given, the file is missing or the VI is broken. LabVIEW 20.0. |
| `New-SummaryImage.ps1` | Not part of the workflow. Crops a diagram picture (file or URL) to one spot and draws numbered orange boxes around the nodes a pull request's Code summary explains; see `docs/pull-request-reports.md`. |
| `Publish-PrReport.ps1` | Pushes the diff images to the branch `pr-assets/pr-<number>` (with `GH_TOKEN` when the checkout keeps no credentials) and posts one comment on the pull request containing both reports, or updates the one it posted before (found by a hidden marker and its author). |
| `pull-request.workflow.yml` | The GitHub Actions workflow that runs the above and builds a test package. |
| `release.workflow.yml` | Proposed version of `.github/workflows/release.yml`. On every push to `main` and on every tag it runs the Caraya suite and the protocol tests. On a tag it then builds the package, with the test LabVIEW `Resolve-CiEnvironment.ps1` chooses (the oldest LabVIEW of at least 2020, 64-bit preferred), like the pull request builds, and writes the `.vipb` as UTF-8. A `v*` tag sets the package version and must point to a commit on `main`; it creates the GitHub release with the annotated tag message (subject and body, no signature) as release text. A `test-*` tag only uploads the package as an artifact. The build job runs in the `release` environment and is the only job with write access. |

## Activating the workflow

Copy `pull-request.workflow.yml` to `.github/workflows/pull-request.yml` on
`main`. It is kept here because changes under `.github/workflows` need a
permission that automation tokens for this repository deliberately do not have.

The workflow runs on the self-hosted runner, only for branches of this
repository (never for forks). It takes the report scripts from `main`, so a
change to them takes effect only once it is merged. That is no isolation: the
pull request's own VIs, tests, package lists and `tools/test/Test-McpServer.ps1`
run on the same runner as the same user and could change files, processes or
the report there. In the first run of a pull request that adds a script `main`
does not have yet, the pull request's own copy is used. The checkouts keep no
token (`persist-credentials: false`); only the step that publishes the report
gets one. That is why only branches of this repository run on the runner.

At the start of each job and when a LabVIEW does not listen on its VI Server
port, CI force-closes the test and comparison LabVIEWs it chose; no other
LabVIEW, and none with unsaved changes (a window title with `*`) unless the
runner's environment has `CI_DEDICATED_MACHINE=1`. See tools/setup/README.md,
"Self-hosted runner".

Every step runs in Windows PowerShell with `-ExecutionPolicy Bypass`. Each job
starts with `Resolve-CiEnvironment.ps1`, which picks the LabVIEW versions,
their VI Server ports and the tools on that runner and repairs simple setup
problems (`LabVIEWCi.psm1` holds the shared functions); the review job then
installs the VIPM packages (`tools/setup/Install-Dependencies.ps1`) into the
test LabVIEW and the comparison LabVIEW. A new runner therefore needs only
LabVIEW, the LabVIEW CLI and VIPM; see `tools/setup/README.md`, "What CI finds
by itself".

### Release workflow

`release.workflow.yml` is a full copy of `.github/workflows/release.yml` with
the proposed changes applied. Copy it over the live file on `main`. Keep both
copies in step afterwards: the templates are where changes are proposed.

It expects an environment named `release` (Settings > Environments) with the
maintainer as required reviewer; GitHub creates a missing environment without
any protection on the first run, so create it first. A tag ruleset for `v*`
that only the maintainer may create or move keeps the tag side safe too.

## Running locally

```powershell
.\tools\ci\New-ViDiffReport.ps1 -BaseRef origin/main -OutDir C:\temp\vi-diff `
    -LabVIEWPath "C:\Program Files (x86)\National Instruments\LabVIEW 2026\LabVIEW.exe" -PortNumber 3363
```

Use a LabVIEW you do not develop in (see tools/setup/README.md, "LabVIEW for
the VI comparison"): one that has `MCP Server.lvlib` loaded from another
checkout cannot compare the library's VIs. LabVIEW must have VI Server TCP
access enabled on the given port. A comparison takes roughly 10 seconds per
VI. When LabVIEW cannot be reached (error -350000), the script stops after the
first VI instead of waiting for the same timeout on every VI.

The comparison images show each case structure on its visible frame only. So
the script also runs `Print Diagram Frames.vi` (LabVIEW CLI RunVI, same
LabVIEW and port) on the new version of every added and modified VI. It prints
the VI with Print.VI To HTML, which writes one picture per frame, and lists the
frames of every case structure in LabVIEW's print order. `report.md` gets a
folded "All case frames" section per VI, one row per frame, captioned with the
structure and its selector value. If the number of pictures and of listed
frames ever differ, the pictures are numbered instead of named. The helper is
saved in LabVIEW 20.0 format; a base branch without it gets the report without
frames and a warning.

The exit code is 1 when any changed VI could not be compared or its frames
could not be printed, and the pull request workflow fails on it: a pull
request without its diff is not ready for review.

## Housekeeping

`pr-assets/pr-<number>` branches hold only images and can be deleted once the
pull request is closed.

## The review report comment

`Publish-PrReport.ps1` keeps the pull request conversation short. The comment
holds the test result in one line (per-test table folded), one row per
modified VI with a small picture of its first changed spot (the first six
visible, the rest folded), the added VIs folded, and a button that opens the
full graphical diff. The full diff (`report.md` and its images) is pushed to
the branch `pr-assets/pr-<number>` and opened from there, where GitHub renders
it as a page. GitHub does not let a link in a comment force a new tab; use
Ctrl+click or the middle mouse button.
