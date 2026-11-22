@echo off
setlocal

set DIRNAME=%~dp0
if "%DIRNAME%"=="" set DIRNAME=.
set APP_HOME=%DIRNAME%

set "HVIGOR_WRAPPER_JS=%APP_HOME%hvigor\hvigor-wrapper.js"

if "%NODE_EXE%"=="" (
  set "NODE_EXE=node"
)

"%NODE_EXE%" "%HVIGOR_WRAPPER_JS%" %*
exit /b %ERRORLEVEL%
