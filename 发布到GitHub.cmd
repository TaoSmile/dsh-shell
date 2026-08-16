@echo off
cd /d "%~dp0"
echo pushing to https://github.com/TaoSmile/dsh-shell ...
git push -u origin main
if errorlevel 1 (
  echo.
  echo push failed, see error above. If 'repository not found': create the repo at https://github.com/new first (name: dsh-shell, empty, no README).
  pause
)
