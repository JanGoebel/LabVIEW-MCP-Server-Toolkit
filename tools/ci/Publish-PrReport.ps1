<#
.SYNOPSIS
Posts the test report and the VI diff report as one comment on a pull request.

.DESCRIPTION
Pull request comments cannot carry uploaded images through the API, so the
diff images are pushed to a branch of their own (pr-assets/pr-<number>, one
commit, replaced on every run) and the comment links to them by commit.

The comment is updated in place on later runs; it is found by a hidden marker.

Needs git push access to the repository (the checkout's own credentials) and
GH_TOKEN for the gh CLI. Delete the pr-assets branch once the pull request is
closed.
#>
param(
    [Parameter(Mandatory = $true)][int]$PrNumber,
    [Parameter(Mandatory = $true)][string]$Repo,
    [string]$DiffDir,
    [string]$TestReport,
    [string]$Footer,
    [string]$RepoDir = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

$ErrorActionPreference = 'Stop'
$marker = '<!-- labview-pr-report -->'
$maxLength = 60000   # GitHub rejects comments longer than 65536 characters
$utf8 = New-Object System.Text.UTF8Encoding $false
$body = New-Object System.Text.StringBuilder
[void]$body.AppendLine($marker)

if ($TestReport -and (Test-Path $TestReport)) {
    [void]$body.AppendLine([System.IO.File]::ReadAllText($TestReport))
}

$diffReport = if ($DiffDir) { Join-Path $DiffDir 'report.md' } else { $null }
if ($diffReport -and (Test-Path $diffReport)) {
    $diff = [System.IO.File]::ReadAllText($diffReport)
    $imageDir = Join-Path $DiffDir 'images'

    if (Test-Path $imageDir) {
        # Commit the images on an orphan branch through a temporary worktree,
        # so the main checkout and its credentials are reused untouched.
        $branch = "pr-assets/pr-$PrNumber"
        $tree = Join-Path ([System.IO.Path]::GetTempPath()) ("assets_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        & git -C $RepoDir worktree add --detach $tree HEAD | Out-Null
        try {
            & git -C $tree checkout --quiet --orphan assets-tmp
            & git -C $tree rm -rf --quiet . | Out-Null
            Copy-Item $imageDir (Join-Path $tree 'images') -Recurse
            [System.IO.File]::WriteAllText((Join-Path $tree 'README.md'), "Images for the review report of pull request #$PrNumber. Safe to delete after the pull request is closed.`n", $utf8)
            & git -C $tree add -A | Out-Null
            & git -C $tree -c user.name='github-actions[bot]' -c user.email='41898282+github-actions[bot]@users.noreply.github.com' `
                commit --quiet -m "Review images for pull request #$PrNumber" | Out-Null
            $sha = (& git -C $tree rev-parse HEAD).Trim()
            & git -C $tree push --force --quiet origin "HEAD:refs/heads/$branch"
            if ($LASTEXITCODE -ne 0) { throw "Pushing the images to $branch failed." }
        }
        finally {
            & git -C $RepoDir worktree remove --force $tree | Out-Null
            & git -C $RepoDir branch --quiet -D assets-tmp
        }
        $diff = $diff.Replace('](images/', "](https://raw.githubusercontent.com/$Repo/$sha/images/")
    }

    if ($body.Length + $diff.Length -gt $maxLength) {
        $diff = $diff.Substring(0, [Math]::Max(0, $maxLength - $body.Length))
        $diff = $diff.Substring(0, [Math]::Max(0, $diff.LastIndexOf("`n### ")))
        $diff += "`n`n_The diff report was cut here because it is too long for one comment. The full report is in the run's artifacts._`n"
    }
    [void]$body.AppendLine($diff)
}

if ($Footer) { [void]$body.AppendLine($Footer) }

$bodyFile = Join-Path ([System.IO.Path]::GetTempPath()) ("pr_comment_" + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.md')
[System.IO.File]::WriteAllText($bodyFile, $body.ToString(), $utf8)

try {
    # Looks at the first 100 comments; the report comment is posted early.
    $comments = (& gh api "repos/$Repo/issues/$PrNumber/comments?per_page=100" | Out-String) | ConvertFrom-Json
    $existing = @($comments | Where-Object { $_.body -like "*$marker*" } | ForEach-Object { $_.id }) | Select-Object -First 1
    if ($existing) {
        & gh api --method PATCH "repos/$Repo/issues/comments/$existing" -F "body=@$bodyFile" --silent
    } else {
        & gh api --method POST "repos/$Repo/issues/$PrNumber/comments" -F "body=@$bodyFile" --silent
    }
    if ($LASTEXITCODE -ne 0) { throw 'Posting the pull request comment failed.' }
}
finally {
    Remove-Item $bodyFile -ErrorAction SilentlyContinue
}
Write-Host "Report published on pull request #$PrNumber."
