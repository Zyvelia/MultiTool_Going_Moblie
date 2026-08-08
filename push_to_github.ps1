<#
push_to_github.ps1

One-command push for this project. Handles both the very first push
(repo doesn't exist as a git repo yet, or has no remote configured) and
every push after that (just commits + pushes whatever changed).

USAGE
    First time:
        .\push_to_github.ps1 -RepoUrl "https://github.com/<you>/music-remote.git"

    Every time after that, from inside the folder:
        .\push_to_github.ps1

    (It remembers the remote after the first run, so -RepoUrl is only
    needed once. Pass it again anytime to change/fix the remote.)

REQUIREMENTS
    - Git for Windows installed (winget install --id Git.Git or
      https://git-scm.com/download/win)
    - You've signed in to GitHub at least once via Git Credential
      Manager (which ships with Git for Windows) — the first push will
      pop a browser window to authenticate if you haven't.
#>

param(
    [string]$RepoUrl,
    [string]$Message = "Update"
)

$ErrorActionPreference = "Stop"

function Fail($msg) {
    Write-Host $msg -ForegroundColor Red
    exit 1
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Fail "Git isn't installed or isn't on PATH. Install it first: winget install --id Git.Git -e"
}

# Run from the script's own folder regardless of where it's invoked from.
Set-Location -Path $PSScriptRoot

$isRepo = Test-Path ".git"

if (-not $isRepo) {
    Write-Host "No git repo here yet — initializing…" -ForegroundColor Cyan
    git init | Out-Null
    git branch -M main
}

if ($RepoUrl) {
    $existing = git remote get-url origin 2>$null
    if ($existing) {
        Write-Host "Updating remote 'origin' to $RepoUrl" -ForegroundColor Cyan
        git remote set-url origin $RepoUrl
    } else {
        Write-Host "Adding remote 'origin' -> $RepoUrl" -ForegroundColor Cyan
        git remote add origin $RepoUrl
    }
} elseif (-not (git remote get-url origin 2>$null)) {
    Fail "No remote configured yet. Run this once with -RepoUrl, e.g.:`n  .\push_to_github.ps1 -RepoUrl `"https://github.com/<you>/music-remote.git`""
}

git add -A

# Nothing to commit is not an error — just means no changes since last push.
git diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
    Write-Host "No changes to commit." -ForegroundColor Yellow
} else {
    git commit -m $Message | Out-Null
    Write-Host "Committed: $Message" -ForegroundColor Green
}

Write-Host "Pushing to origin/main…" -ForegroundColor Cyan
git push -u origin main

Write-Host "`nDone. GitHub Actions will start the build automatically — check the Actions tab." -ForegroundColor Green
