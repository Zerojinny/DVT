; Select aria2.conf by link speed of the adapter that routes toward the internet
; Uses only iphlpapi.dll (no WMI / PowerShell / WMIC)

Global $sLog = @ScriptDir & "\aria2_select.log"

Func _Log($s)
    Local $h = FileOpen($sLog, 1)
    If $h = -1 Then $h = FileOpen(@TempDir & "\aria2_select.log", 1)
    If $h <> -1 Then
        FileWriteLine($h, @YEAR & "-" & @MON & "-" & @MDAY & " " & @HOUR & ":" & @MIN & ":" & @SEC & "  " & $s)
        FileClose($h)
    EndIf
EndFunc

_Log("Start. ScriptDir=" & @ScriptDir & " Arch=" & @AutoItX64)

Local $iIfIndex = 0
Local $iTry, $aBest

; Wait up to 30 sec for a route to 8.8.8.8 (useful right after PE boot)
For $iTry = 1 To 30
    $aBest = DllCall("iphlpapi.dll", "dword", "GetBestInterface", "ulong", 0x08080808, "dword*", 0)
    If Not @error And $aBest[0] = 0 Then
        $iIfIndex = $aBest[2]
        ExitLoop
    EndIf
    Sleep(1000)
Next

If $iIfIndex = 0 Then
    _Log("No route found")
    Exit 1
EndIf

; MIB_IF_ROW2 = 1352 bytes, InterfaceIndex is at offset 8
Local $tRow = DllStructCreate("byte[1352]")
Local $pRow = DllStructGetPtr($tRow)
DllStructSetData(DllStructCreate("ulong", $pRow + 8), 1, $iIfIndex)

Local $aRet = DllCall("iphlpapi.dll", "dword", "GetIfEntry2", "ptr", $pRow)
If @error Or $aRet[0] <> 0 Then
    _Log("GetIfEntry2 failed")
    Exit 2
EndIf

Local $sAlias = DllStructGetData(DllStructCreate("wchar[257]", $pRow + 28), 1)
Local $sDesc  = DllStructGetData(DllStructCreate("wchar[257]", $pRow + 542), 1)
Local $iTx = DllStructGetData(DllStructCreate("uint64", $pRow + 1192), 1)
Local $iRx = DllStructGetData(DllStructCreate("uint64", $pRow + 1200), 1)

; Use the lower of transmit/receive speed, converted to Mbps
Local $iSpeed = $iTx
If $iRx < $iSpeed Then $iSpeed = $iRx
Local $fMbps = $iSpeed / 1000000

_Log("IfIndex=" & $iIfIndex & " Alias=" & $sAlias & " Desc=" & $sDesc)
_Log("Tx=" & $iTx / 1000000 & " Mbps  Rx=" & $iRx / 1000000 & " Mbps  Used=" & $fMbps & " Mbps")

; Choose the source file by speed
Local $sSrc
If $fMbps >= 1000 Then
    $sSrc = @ScriptDir & "\aria2.conf.1G"
Else
    $sSrc = @ScriptDir & "\aria2.conf.100"
EndIf
Local $sDst = @ScriptDir & "\aria2.conf"

_Log("Src=" & $sSrc & "  exists=" & FileExists($sSrc))
_Log("Dst=" & $sDst & "  exists_before=" & FileExists($sDst))

If Not FileExists($sSrc) Then
    _Log("Source missing")
    Exit 3
EndIf

; Rename (flag 1 = overwrite if aria2.conf already exists)
Local $iOk = FileMove($sSrc, $sDst, 1)
_Log("FileMove result=" & $iOk & " @error=" & @error)

If Not $iOk Or Not FileExists($sDst) Or FileExists($sSrc) Then
    _Log("Verification failed")
    Exit 4
EndIf

_Log("Done")
Exit 0