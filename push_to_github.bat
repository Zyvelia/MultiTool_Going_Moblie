@echo off
setlocal enabledelayedexpansion

REM push_to_github.bat
REM
REM Commits local changes and force-updates origin/main to match this copy.
REM If Git cannot read HEAD, this rewrites the branch pointer only.
REM Project files are not reset or deleted.

set "REPO_URL=%~1"
set "MSG=%~2"
if "%MSG%"=="" set "MSG=Update"

where git >nul 2>nul
if errorlevel 1 (
    echo Git isn't installed or isn't on PATH. Install it first: winget install --id Git.Git -e
    goto :fail
)

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
        echo   push_to_github.bat https://github.com/^<you^>/multi-tool-remote.git
        goto :fail
    )
)

call :ensure_head
if errorlevel 1 goto :fail

git add -A
if errorlevel 1 (
    echo git add failed. Nothing was committed or pushed.
    goto :fail
)

git diff --cached --quiet
set "DIFF=!errorlevel!"
if "!DIFF!"=="0" (
    echo No changes to commit.
) else if "!DIFF!"=="1" (
    git commit -m "%MSG%"
    if errorlevel 1 (
        echo.
        echo The commit failed, so nothing was saved and nothing will be pushed.
        goto :fail
    )
    echo Committed: %MSG%
) else (
    echo Could not compare the staged files with HEAD. Nothing was pushed.
    goto :fail
)

git fetch origin main >nul 2>nul

echo.
echo WARNING: This will force-update origin/main to match this local copy.
echo Any commits currently on GitHub/main that are not in this copy will no
echo longer be part of origin/main.
echo.

echo Pushing local main to origin/main ^(force^)...
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

:ensure_head
call :head_is_commit
if not errorlevel 1 exit /b 0

git symbolic-ref -q HEAD >nul 2>nul
if not errorlevel 1 (
    git show-ref --verify --quiet refs/heads/main >nul 2>nul
    if "!errorlevel!"=="1" exit /b 0
)

echo.
echo Git could not read HEAD. Repairing the branch pointer.
echo Files in this folder are left as they are.
echo.

if not exist ".git\HEAD" (
    echo .git is not a normal repository folder, so HEAD was not rewritten.
    exit /b 1
)

git rev-parse --is-inside-work-tree >nul 2>nul
if errorlevel 1 (
    > ".git\HEAD" echo ref: refs/heads/main
)

call :head_is_commit
if not errorlevel 1 exit /b 0

call :ref_is_commit refs/heads/main
if not errorlevel 1 (
    git symbolic-ref HEAD refs/heads/main
    exit /b !errorlevel!
)

echo Local main is not a commit. Fetching origin/main...
git fetch origin main

call :ref_is_commit refs/heads/main
if not errorlevel 1 (
    git symbolic-ref HEAD refs/heads/main
    exit /b !errorlevel!
)

call :ref_is_commit refs/remotes/origin/main
if errorlevel 1 (
    echo Could not repair HEAD. origin/main is not a commit in this clone.
    exit /b 1
)

git update-ref refs/heads/main refs/remotes/origin/main
if errorlevel 1 exit /b 1
git symbolic-ref HEAD refs/heads/main
if errorlevel 1 exit /b 1

call :head_is_commit
if errorlevel 1 (
    echo HEAD is still not a commit after repair.
    exit /b 1
)
echo HEAD now points at origin/main.
exit /b 0

:head_is_commit
set "HEADTYPE="
for /f "delims=" %%T in ('git cat-file -t HEAD 2^>nul') do set "HEADTYPE=%%T"
if /i "!HEADTYPE!"=="commit" exit /b 0
exit /b 1

:ref_is_commit
set "REFTYPE="
for /f "delims=" %%T in ('git cat-file -t "%~1" 2^>nul') do set "REFTYPE=%%T"
if /i "!REFTYPE!"=="commit" exit /b 0
exit /b 1