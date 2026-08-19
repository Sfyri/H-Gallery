Option Explicit

Dim shell, fso, baseDir, pythonw, python, command
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
baseDir = fso.GetParentFolderName(WScript.ScriptFullName)
pythonw = baseDir & "\.venv\Scripts\pythonw.exe"
python = baseDir & "\.venv\Scripts\python.exe"

If Not fso.FileExists(python) Then
    WScript.Quit 1
End If

shell.CurrentDirectory = baseDir
If fso.FileExists(pythonw) Then
    command = Chr(34) & pythonw & Chr(34) & " -m h_gallery_cli stop"
Else
    command = Chr(34) & python & Chr(34) & " -m h_gallery_cli stop"
End If
shell.Run command, 0, True
