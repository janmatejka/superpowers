@echo off
rem Test-seam shim (Ruling A). Start-Process ShellExecutes a bare .ps1 on
rem Windows instead of running it, so pointing -ClaudeCommand/-TerminalCommand
rem directly at argv-probe.ps1 can leave the probe's output file never
rem written. A .cmd IS handled by CreateProcess directly (Start-Process needs
rem no special casing for it), so this forwards through to pwsh instead.
rem ASCII only in this file: non-ASCII bytes in a REM comment (an em dash was
rem measured to do this) can be misdecoded by cmd.exe's active codepage and
rem break parsing of unrelated lines below it.
rem %* is the whole remaining command line verbatim, quotes and all, so this
rem must NOT be rewritten as %1 %2 %3 ... that would re-split an argument
rem already spanning multiple words and defeat the very thing the probe
rem exists to prove.
pwsh -NoProfile -File "%~dp0argv-probe.ps1" %*
exit /b %ERRORLEVEL%
