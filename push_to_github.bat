@echo off
setlocal enabledelayedexpansion

REM push_to_github.bat
REM
REM One-command push for this project. Handles both the very first push
REM (repo doesn't exist as a git repo yet, or has no remote configured)
REM and every push after that (just commits + pushes whatever changed).
REM
REM USAGE
REM     First time:
REM         push_to_github.bat https://github.com/<you>/multi-tool-remote.git
REM
REM     Every time after that, from inside the folder:
REM         push_to_github.bat
REM
REM     (It remembers the remote after the first run, so the URL is only
REM     needed once. Pass it again anytime to change/fix the remote.)
REM
REM     Optional second argument overrides the commit message, e.g.:
REM         push_to_github.bat "" "fix background audio"
REM
REM REQUIREMENTS
REM     - Git for Windows installed (winget install --id Git.Git -e or
REM       https://git-scm.com/download/win)
REM     - You've signed in to GitHub at least once via Git Credential
REM       Manager (ships with Git for Windows) — the first push will pop
REM       a browser window to authenticate if you haven't.

set "REPO_URL=%~1"
set "MSG=%~2"
if "%MSG%"=="" set "MSG=Update"

where git >nul 2>nul
if errorlevel 1 (
    echo Git isn't installed or isn't on PATH. Install it first: winget install --id Git.Git -e
    exit /b 1
)

REM Run from this script's own folder regardless of where it's invoked from.
cd /d "%~dp0"

if not exist ".git" (
    echo No git repo here yet - initializing...
    git init >nul
    git branch -M main
)

if not "%REPO_URL%"=="" (
    git remote get-url origin >nul 2>nul
    if errorlevel 1 (
        echo Adding remote 'origin' -^> %REPO_URL%
        git remote add origin "%REPO_URL%"
    ) else (
        echo Updating remote 'origin' to %REPO_URL%
        git remote set-url origin "%REPO_URL%"
    )
) else (
    git remote get-url origin >nul 2>nul
    if errorlevel 1 (
        echo No remote configured yet. Run this once with a URL, e.g.:
        echo   push_to_github.bat https://github.com/<you>/multi-tool-remote.git
        exit /b 1
    )
)

git add -A

git diff --cached --quiet
if errorlevel 1 (
    git commit -m "%MSG%" >nul
    echo Committed: %MSG%
) else (
    echo No changes to commit.
)

echo Pushing to origin/main...
git push -u origin main
if errorlevel 1 (
    echo Push failed - see the error above.
    exit /b 1
)

echo.
echo Done. GitHub Actions will start the build automatically - check the Actions tab.
