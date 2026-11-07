@echo off
cd /d "%~dp0"
"%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /codepage:65001 /optimize+ /target:winexe /win32icon:Messag8.ico /resource:logo.png,logo.png /out:"..\Messag8.exe" /r:System.Windows.Forms.dll /r:System.Drawing.dll Messag8.cs
pause
