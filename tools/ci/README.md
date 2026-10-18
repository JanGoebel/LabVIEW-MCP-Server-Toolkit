# Pull request review automation

Scripts used by the pull request workflow to show what a pull request changes
and whether it works. GitHub cannot diff VIs, so the review material is
generated and posted as a comment on the pull request.

| File | Purpose |
|---|---|
| `Resolve-CiEnvironment.ps1` | First step of every job: finds the LabVIEW for tests and build (oldest ≥ 2020) and for the VI comparison (newest), their VI Server ports, LabVIEW CLI, `vipm` and `gh`; with `-Fix` repairs VI Server settings and port clashes; writes `LABVIEW_*` for the following steps and a table to the job summary. |
| `LabVIEWCi.psm1` | Functions shared by the scripts here: LabVIEW discovery, VI Server port resolution, tool lookup. |
| `New-ViDiffReport.ps1` | Compares every changed `.vi`/`.vim`/`.ctl` with its version on the base branch, using LabVIEW's own comparison (`LabVIEWCLI -OperationName CreateComparisonReport`), and writes a Markdown report with before/after images. Added VIs are shown with their block diagram and front panel. Every case frame of the new version of each VI is added in a folded section. |
| `Print Diagram Frames.vi` | Run by `New-ViDiffReport.ps1` through `LabVIEWCLI -OperationName RunVI`: prints one VI with Print.VI To HTML (one picture per case frame) and lists each frame's structure and selector value in print order. Arguments: VI path, HTML file path, frame list path. LabVIEW 20.0. |
| `Invoke-CliTest.ps1` | Runs a test entry VI (`tests\Run_Tests_CLI.vi`, `tests\Run_Protocol_Tests_CLI.vi`) through `LabVIEWCLI -OperationName RunVI`. Exit code 0 passed, 1 tests failed, 2 LabVIEW not reachable (CLI error -350000), 3 entry VI missing on the branch. Used by both workflows. |
| `Convert-CarayaReport.ps1` | Turns `tests\results\caraya-report.txt`, written by `tests\Run_Tests_CLI.vi`, into a table with one row per test, and adds the protocol tester's result from `tests\results\protocol-report.txt`. Says "did not run" instead of showing failures when LabVIEW was not reachable. |
| `New-SummaryImage.ps1` | Not part of the workflow. Crops a diagram picture (file or URL) to one spot and draws numbered orange boxes around the nodes a pull request's Code summary explains; see `docs/pull-request-reports.md`. |
| `Publish-PrReport.ps1` | Pushes the diff images to the branch `pr-assets/pr-<number>` and posts or updates one comment on the pull request containing both reports. |
| `pull-request.workflow.yml` | The GitHub Actions workflow that runs the above and builds a test package. |
| `release.workflow.yml` | Proposed version of `.github/workflows/release.yml`: runs the Caraya suite and the protocol tests before a build, uses the annotated tag message as release text, writes the `.vipb` as UTF-8 and builds for LabVIEW 2020 64-bit like the pull request builds. |

## Activating the workflow

Copy `pull-request.workflow.yml` to `.github/workflows/pull-request.yml` on
`main`. It is kept here because changes under `.github/workflows` need a
permission that automation tokens for this repository deliberately do not have.

The workflow runs on the self-hosted runner, only for branches of this
repository (never for forks), and takes the scripts from `main`, so a pull
request cannot change how its own report is produced.

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
