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
    goto :fail
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
        goto :fail
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

REM This project intentionally uses the local copy as the source of truth.
REM If origin/main is ahead, DO NOT merge it into this copy. Merging can create
REM conflicts in generated/build integration files and can overwrite the fixes
REM already present here.
REM
REM We fetch only so Git knows the current remote state, then force-update
REM origin/main to exactly match this local main branch.
git fetch origin main >nul 2>nul

echo.
echo WARNING: This will force-update origin/main to match this local copy.
echo Any commits currently on GitHub/main that are not in this copy will no
echo longer be part of origin/main.
echo.

echo Pushing local main to origin/main (force)...
git push --force -u origin main
if errorlevel 1 (
    echo.
    echo Force push failed - see the error above. Common causes: not signed
    echo in to GitHub or branch protection preventing force pushes.
    goto :fail
)

echo.
echo Done. GitHub Actions will start the build automatically - check the Actions tab.
pause
exit /b 0

:fail
echo.
echo Something went wrong - see above.
pause
exit /b 1
