# Same flow as push_to_github.bat — use this if you prefer PowerShell.
param(
    [string]$RepoUrl = "",
    [string]$Message = "Update"
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error "Git is not on PATH. Install Git for Windows first."
    exit 1
}

if (-not (Test-Path ".git")) {
    Write-Host "Initializing git repo..."
    git init | Out-Null
    git branch -M main
}

if ($RepoUrl) {
    $hasOrigin = $false
    try { git remote get-url origin 2>$null | Out-Null; $hasOrigin = $true } catch {}
    if ($hasOrigin) {
        git remote set-url origin $RepoUrl
    } else {
        git remote add origin $RepoUrl
    }
} elseif (-not (git remote get-url origin 2>$null)) {
    Write-Error "No origin remote. Run once with: .\push_to_github.ps1 -RepoUrl https://github.com/you/repo.git"
    exit 1
}

git add -A
git diff --cached --quiet
if ($LASTEXITCODE -ne 0) {
    git commit -m $Message | Out-Null
    Write-Host "Committed: $Message"
} else {
    Write-Host "No changes to commit."
}

git fetch origin main 2>$null | Out-Null
Write-Host ""
Write-Host "WARNING: Force-updating origin/main to match this folder."
git push --force -u origin main
Write-Host ""
Write-Host "Done. Check GitHub Actions for the build."
