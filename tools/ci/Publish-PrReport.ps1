<#
.SYNOPSIS
Posts the test report and the VI diff report as one comment on a pull request.

.DESCRIPTION
Pull request comments cannot carry uploaded images through the API, so the
diff images are pushed to a branch of their own (pr-assets/pr-<number>, one
commit, replaced on every run) and the comment links to them by commit.

The comment is updated in place on later runs: the comment that carries a
hidden marker and was written by the same GitHub user (github-actions[bot]
in the workflow) is edited, looking through all comments of the pull
request. A marked comment of another user is left alone and a new one is
posted.

Needs GH_TOKEN for gh or the REST API, and push access to the repository.
When GH_TOKEN is set and the checkout has no credentials of its own (the
workflow checks out with persist-credentials: false), the push sends
GH_TOKEN as an HTTP header for that one git call, through the environment,
not the command line. Without GH_TOKEN (a local run) git pushes with the
user's own credentials. Delete the pr-assets branch once the pull request is
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
Import-Module (Join-Path $PSScriptRoot 'LabVIEWCi.psm1') -Force
$marker = '<!-- labview-pr-report -->'
$maxLength = 60000   # GitHub rejects comments longer than 65536 characters
$utf8 = New-Object System.Text.UTF8Encoding $false
$body = New-Object System.Text.StringBuilder
[void]$body.AppendLine($marker)

if ($TestReport -and (Test-Path -LiteralPath $TestReport)) {
    [void]$body.AppendLine([System.IO.File]::ReadAllText($TestReport))
}

function Push-Report([string]$WorkTree, [string]$RefSpec) {
    # A checkout made with persist-credentials: false has no credentials for
    # the push; GH_TOKEN is then sent as the header actions/checkout would
    # have stored, through GIT_CONFIG_* variables of this one call, so it
    # appears neither on a command line nor in a config file. A checkout
    # that still has such a header, or a local run without GH_TOKEN, pushes
    # with what git already has.
    $own = Invoke-NativeCommand 'git' @('-C', $WorkTree, 'config', '--get-regexp', '^http\..*\.extraheader$')
    $useToken = $env:GH_TOKEN -and ($own.ExitCode -ne 0 -or $own.Output.Count -eq 0)
    $names = 'GIT_CONFIG_COUNT', 'GIT_CONFIG_KEY_0', 'GIT_CONFIG_VALUE_0'
    $saved = @{}
    foreach ($n in $names) { $saved[$n] = [Environment]::GetEnvironmentVariable($n, 'Process') }
    try {
        if ($useToken) {
            $server = if ($env:GITHUB_SERVER_URL) { $env:GITHUB_SERVER_URL.TrimEnd('/') } else { 'https://github.com' }
            $basic = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("x-access-token:$env:GH_TOKEN"))
            $env:GIT_CONFIG_COUNT = '1'
            $env:GIT_CONFIG_KEY_0 = "http.$server/.extraheader"
            $env:GIT_CONFIG_VALUE_0 = "AUTHORIZATION: basic $basic"
        }
        Invoke-Git @('-C', $WorkTree, 'push', '--force', '--quiet', 'origin', $RefSpec) | Out-Null
    }
    finally {
        foreach ($n in $names) { [Environment]::SetEnvironmentVariable($n, $saved[$n], 'Process') }
    }
}

$diffReport = if ($DiffDir) { Join-Path $DiffDir 'report.md' } else { $null }
if ($diffReport -and (Test-Path -LiteralPath $diffReport)) {
    $diff = [System.IO.File]::ReadAllText($diffReport)
    $summaryFile = Join-Path $DiffDir 'summary.md'
    $summary = if (Test-Path -LiteralPath $summaryFile) { [System.IO.File]::ReadAllText($summaryFile) } else { $null }
    $imageDir = Join-Path $DiffDir 'images'
    $sha = $null

    if (Test-Path -LiteralPath $imageDir) {
        # Commit the full report and its images as a commit without parent,
        # built in a temporary worktree without checkout (its index starts
        # empty) and pushed by its id, so no branch is created locally and
        # the main checkout is left untouched. GitHub renders report.md there
        # with its images, which is the "full diff" page the comment links to.
        $branch = "pr-assets/pr-$PrNumber"
        $tree = Join-Path ([System.IO.Path]::GetTempPath()) ("assets_" + [guid]::NewGuid().ToString('N'))
        Invoke-Git @('-C', $RepoDir, 'worktree', 'prune') | Out-Null
        Invoke-Git @('-C', $RepoDir, 'worktree', 'add', '--detach', '--no-checkout', $tree, 'HEAD') | Out-Null
        try {
            Copy-Item -LiteralPath $imageDir -Destination (Join-Path $tree 'images') -Recurse
            [System.IO.File]::WriteAllText((Join-Path $tree 'report.md'), $diff, $utf8)
            [System.IO.File]::WriteAllText((Join-Path $tree 'README.md'), "Review report of pull request #$PrNumber, see report.md. Safe to delete after the pull request is closed.`n", $utf8)
            Invoke-Git @('-C', $tree, 'add', '--', 'images', 'report.md', 'README.md') | Out-Null
            $treeId = (@(Invoke-Git @('-C', $tree, 'write-tree')) -join '').Trim()
            $sha = (@(Invoke-Git @('-C', $tree, '-c', 'user.name=github-actions[bot]', '-c', 'user.email=41898282+github-actions[bot]@users.noreply.github.com',
                        'commit-tree', $treeId, '-m', "Review report for pull request $PrNumber")) -join '').Trim()
            Push-Report $tree "${sha}:refs/heads/$branch"
        }
        finally {
            try { Invoke-Git @('-C', $RepoDir, 'worktree', 'remove', '--force', $tree) | Out-Null }
            catch { Write-Warning "Could not remove the worktree $tree ($($_.Exception.Message)); 'git worktree prune' cleans it up." }
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
$useGh = [bool](Get-GhPath)
if (-not $useGh) {
    if (-not $env:GH_TOKEN) { throw 'Neither the GitHub CLI (gh) nor GH_TOKEN is available to post the comment.' }
    Write-Host 'gh not found; posting through the REST API.'
}
$apiHeaders = @{ Authorization = "Bearer $env:GH_TOKEN"; Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28' }
$apiRoot = if ($env:GITHUB_API_URL) { $env:GITHUB_API_URL.TrimEnd('/') } else { 'https://api.github.com' }

function Send-Comment([string]$Method, [string]$Path, [string]$BodyFile) {
    # POST or PATCH of a comment body; throws when GitHub refuses it.
    if ($useGh) {
        $run = Invoke-Utf8Command 'gh' @('api', '--method', $Method, $Path, '-F', "body=@$BodyFile", '--silent')
        if ($run.ExitCode -ne 0) { throw "GitHub API $Method $Path failed (gh exit code $($run.ExitCode))." }
        return
    }
    $json = @{ body = [System.IO.File]::ReadAllText($BodyFile) } | ConvertTo-Json -Compress
    Invoke-RestMethod -Method $Method -Uri "$apiRoot/$Path" -Headers $apiHeaders -UseBasicParsing `
        -Body ([System.Text.Encoding]::UTF8.GetBytes($json)) -ContentType 'application/json; charset=utf-8' | Out-Null
}

function Get-PrComment {
    # Every comment of the pull request, all pages, as id, login and body.
    if ($useGh) {
        # --jq prints one compact JSON object per line, also across pages.
        $run = Invoke-Utf8Command 'gh' @('api', '--paginate', "repos/$Repo/issues/$PrNumber/comments?per_page=100", '--jq', '.[] | {id: .id, login: .user.login, body: .body}')
        if ($run.ExitCode -ne 0) { throw "Reading the comments of pull request #$PrNumber failed (gh exit code $($run.ExitCode))." }
        return @($run.Output | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json })
    }
    $all = @()
    for ($page = 1; ; $page++) {
        $result = Invoke-RestMethod -Method Get -Uri "$apiRoot/repos/$Repo/issues/$PrNumber/comments?per_page=100&page=$page" -Headers $apiHeaders -UseBasicParsing
        $items = @($result)
        $all += @($items | ForEach-Object { [pscustomobject]@{ id = $_.id; login = $_.user.login; body = $_.body } })
        if ($items.Count -lt 100) { break }
    }
    return $all
}

function Get-CommentAuthor {
    # The login comments are posted as. The workflow's GITHUB_TOKEN may not
    # read /user; it always posts as github-actions[bot].
    $login = $null
    if ($useGh) {
        $run = Invoke-NativeCommand 'gh' @('api', 'user', '--jq', '.login')
        if ($run.ExitCode -eq 0) { $login = ($run.Output -join '').Trim() }
    } else {
        try { $login = (Invoke-RestMethod -Method Get -Uri "$apiRoot/user" -Headers $apiHeaders -UseBasicParsing).login } catch { $login = $null }
    }
    if ($login) { return $login }
    if ($env:GITHUB_ACTIONS -eq 'true') { return 'github-actions[bot]' }
    throw 'Could not find out which GitHub user posts the report (GET /user failed).'
}

try {
    $author = Get-CommentAuthor
    $existing = @(Get-PrComment | Where-Object { "$($_.body)".Contains($marker) -and $_.login -eq $author } | ForEach-Object { $_.id }) | Select-Object -First 1
    if ($existing) {
        Send-Comment PATCH "repos/$Repo/issues/comments/$existing" $bodyFile
    } else {
        Send-Comment POST "repos/$Repo/issues/$PrNumber/comments" $bodyFile
    }
}
finally {
    Remove-Item -LiteralPath $bodyFile -ErrorAction SilentlyContinue
}
Write-Host "Report published on pull request #$PrNumber."
