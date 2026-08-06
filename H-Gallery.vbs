Option Explicit

Dim shell, fso, baseDir, launcher, command
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
baseDir = fso.GetParentFolderName(WScript.ScriptFullName)
launcher = baseDir & "\.venv\Scripts\h-gallery.exe"

If Not fso.FileExists(launcher) Then
    MsgBox "H-Gallery non e' installata in questa cartella." & vbCrLf & vbCrLf & _
           "Esegui prima Install.bat.", vbExclamation, "H-Gallery"
    WScript.Quit 1
End If

command = Chr(34) & launcher & Chr(34) & " launcher"
shell.Run command, 0, False
