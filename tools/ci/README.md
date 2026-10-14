# Pull request review automation

Scripts used by the pull request workflow to show what a pull request changes
and whether it works. GitHub cannot diff VIs, so the review material is
generated and posted as a comment on the pull request.

| File | Purpose |
|---|---|
| `New-ViDiffReport.ps1` | Compares every changed `.vi`/`.vim`/`.ctl` with its version on the base branch, using LabVIEW's own comparison (`LabVIEWCLI -OperationName CreateComparisonReport`), and writes a Markdown report with before/after images. Added VIs are shown with their block diagram and front panel. |
| `Convert-CarayaReport.ps1` | Turns `tests\results\caraya-report.txt`, written by `tests\Run_Tests_CLI.vi`, into a table with one row per test. |
| `Publish-PrReport.ps1` | Pushes the diff images to the branch `pr-assets/pr-<number>` and posts or updates one comment on the pull request containing both reports. |
| `pull-request.workflow.yml` | The GitHub Actions workflow that runs the above and builds a test package. |

## Activating the workflow

Copy `pull-request.workflow.yml` to `.github/workflows/pull-request.yml` on
`main`. It is kept here because changes under `.github/workflows` need a
permission that automation tokens for this repository deliberately do not have.

The workflow runs on the self-hosted runner, only for branches of this
repository (never for forks), and takes the scripts from `main`, so a pull
request cannot change how its own report is produced.

## Running locally

```powershell
.\tools\ci\New-ViDiffReport.ps1 -BaseRef main -OutDir C:\temp\vi-diff `
    -LabVIEWPath "C:\Program Files\National Instruments\LabVIEW 2026\LabVIEW.exe" -PortNumber 3364
```

LabVIEW must have VI Server TCP access enabled on the given port. A comparison
takes roughly 15 seconds per VI.

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
