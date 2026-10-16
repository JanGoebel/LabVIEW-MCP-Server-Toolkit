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
    $summaryFile = Join-Path $DiffDir 'summary.md'
    $summary = if (Test-Path $summaryFile) { [System.IO.File]::ReadAllText($summaryFile) } else { $null }
    $imageDir = Join-Path $DiffDir 'images'
    $sha = $null

    if (Test-Path $imageDir) {
        # Commit the full report and its images on an orphan branch through a
        # temporary worktree, so the main checkout and its credentials are
        # reused untouched. GitHub renders report.md there with its images,
        # which is the "full diff" page the comment links to.
        $branch = "pr-assets/pr-$PrNumber"
        $tree = Join-Path ([System.IO.Path]::GetTempPath()) ("assets_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        & git -C $RepoDir worktree add --detach $tree HEAD | Out-Null
        try {
            & git -C $tree checkout --quiet --orphan assets-tmp
            & git -C $tree rm -rf --quiet . | Out-Null
            Copy-Item $imageDir (Join-Path $tree 'images') -Recurse
            [System.IO.File]::WriteAllText((Join-Path $tree 'report.md'), $diff, $utf8)
            [System.IO.File]::WriteAllText((Join-Path $tree 'README.md'), "Review report of pull request #$PrNumber, see report.md. Safe to delete after the pull request is closed.`n", $utf8)
            & git -C $tree add -A | Out-Null
            & git -C $tree -c user.name='github-actions[bot]' -c user.email='41898282+github-actions[bot]@users.noreply.github.com' `
                commit --quiet -m "Review report for pull request $PrNumber" | Out-Null
            $sha = (& git -C $tree rev-parse HEAD).Trim()
            & git -C $tree push --force --quiet origin "HEAD:refs/heads/$branch"
            if ($LASTEXITCODE -ne 0) { throw "Pushing the report to $branch failed." }
        }
        finally {
            & git -C $RepoDir worktree remove --force $tree | Out-Null
            & git -C $RepoDir branch --quiet -D assets-tmp
        }
    }

    $raw = "https://raw.githubusercontent.com/$Repo/$sha/images/"
    if ($summary -and $sha) {
        # Short form: counts, one picture per modified VI, and a button to the
        # full report. The full report never goes into the comment.
        [void]$body.AppendLine('### VI changes')
        [void]$body.AppendLine()
        [void]$body.AppendLine("[![Open the full VI diff](https://img.shields.io/badge/Open%20the%20full%20VI%20diff-0969da?style=for-the-badge)](https://github.com/$Repo/blob/$sha/report.md)")
        [void]$body.AppendLine()
        [void]$body.AppendLine($summary.Replace('src="images/', "src=""$raw").Replace('](images/', "]($raw"))
    } else {
        # Older diff folders without summary.md: the full report, cut to size.
        if ($sha) { $diff = $diff.Replace('](images/', "]($raw") }
        if ($body.Length + $diff.Length -gt $maxLength) {
            $diff = $diff.Substring(0, [Math]::Max(0, $maxLength - $body.Length))
            $diff = $diff.Substring(0, [Math]::Max(0, $diff.LastIndexOf("`n### ")))
            $diff += "`n`n_The diff report was cut here because it is too long for one comment._`n"
        }
        [void]$body.AppendLine($diff)
    }
}

if ($Footer) { [void]$body.AppendLine($Footer) }

$bodyFile = Join-Path ([System.IO.Path]::GetTempPath()) ("pr_comment_" + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.md')
[System.IO.File]::WriteAllText($bodyFile, $body.ToString(), $utf8)

# gh where it is installed; otherwise the REST API directly, with the same
# token (GH_TOKEN), so a runner without the GitHub CLI still gets its report.
$useGh = [bool](Get-Command gh -CommandType Application -ErrorAction SilentlyContinue)
if (-not $useGh) {
    $ghDefault = Join-Path $env:ProgramFiles 'GitHub CLI\gh.exe'
    if (Test-Path $ghDefault) { $env:PATH = "$(Split-Path $ghDefault);$env:PATH"; $useGh = $true }
}
if (-not $useGh) {
    if (-not $env:GH_TOKEN) { throw 'Neither the GitHub CLI (gh) nor GH_TOKEN is available to post the comment.' }
    Write-Host 'gh not found; posting through the REST API.'
}
$apiHeaders = @{ Authorization = "Bearer $env:GH_TOKEN"; Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28' }

function Invoke-GitHubApi([string]$Method, [string]$Path, [string]$BodyFile) {
    if ($useGh) {
        if ($BodyFile) {
            & gh api --method $Method $Path -F "body=@$BodyFile" --silent
        } else {
            return (& gh api --method $Method $Path | Out-String) | ConvertFrom-Json
        }
        if ($LASTEXITCODE -ne 0) { throw "GitHub API $Method $Path failed." }
        return
    }
    $parameters = @{ Method = $Method; Uri = "https://api.github.com/$Path"; Headers = $apiHeaders; UseBasicParsing = $true }
    if ($BodyFile) {
        $json = @{ body = [System.IO.File]::ReadAllText($BodyFile) } | ConvertTo-Json -Compress
        $parameters['Body'] = [System.Text.Encoding]::UTF8.GetBytes($json)
        $parameters['ContentType'] = 'application/json; charset=utf-8'
    }
    return Invoke-RestMethod @parameters
}

try {
    # Looks at the first 100 comments; the report comment is posted early.
    $comments = Invoke-GitHubApi GET "repos/$Repo/issues/$PrNumber/comments?per_page=100"
    $existing = @($comments | Where-Object { $_.body -like "*$marker*" } | ForEach-Object { $_.id }) | Select-Object -First 1
    if ($existing) {
        Invoke-GitHubApi PATCH "repos/$Repo/issues/comments/$existing" $bodyFile | Out-Null
    } else {
        Invoke-GitHubApi POST "repos/$Repo/issues/$PrNumber/comments" $bodyFile | Out-Null
    }
}
finally {
    Remove-Item $bodyFile -ErrorAction SilentlyContinue
}
Write-Host "Report published on pull request #$PrNumber."
