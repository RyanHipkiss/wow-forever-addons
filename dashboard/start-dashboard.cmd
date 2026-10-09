@echo off
cd /d "%~dp0"
start "" http://localhost:4747
node server.js %*
