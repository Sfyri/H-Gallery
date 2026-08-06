Option Explicit

Dim shell, fso, baseDir, launcher, command
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
baseDir = fso.GetParentFolderName(WScript.ScriptFullName)
launcher = baseDir & "\.venv\Scripts\h-gallery.exe"

If Not fso.FileExists(launcher) Then
    WScript.Quit 1
End If

command = Chr(34) & launcher & Chr(34) & " stop"
shell.Run command, 0, True
