# Runs the browser caption probe: serves the release web build behind the
# cross-origin isolation headers, opens probe.html in a headless Chromium
# browser, and prints the pipeline log (decode -> 16 kHz mono -> whisper worker)
# read back through the DevTools protocol.
#
#   flutter build web --release
#   powershell -ExecutionPolicy Bypass -File .\tool\probe\run_probe.ps1
param(
    [int] $Port = 8124,
    [int] $DebugPort = 9333,
    [string] $Chrome = '',
    [string] $Page = 'probe.html',
    [int] $TimeoutSeconds = 300
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$web = Join-Path $root 'build\web'

if (-not (Test-Path -LiteralPath (Join-Path $web 'index.html'))) {
    throw 'Build the web app first: flutter build web --release'
}

if ([string]::IsNullOrWhiteSpace($Chrome)) {
    $candidates = @(
        'C:\Program Files\Google\Chrome\Application\chrome.exe',
        'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe',
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
        'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
        'C:\Program Files\Microsoft\Edge\Application\msedge.exe'
    )
    $Chrome = $candidates | Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1
}
if ([string]::IsNullOrWhiteSpace($Chrome) -or
    -not (Test-Path -LiteralPath $Chrome)) {
    throw 'No Chromium browser found. Pass -Chrome <path to chrome.exe or msedge.exe>.'
}

$speech = Join-Path $root 'probe_speech.wav'
if (-not (Test-Path -LiteralPath $speech)) {
    Add-Type -AssemblyName System.Speech
    $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
    $synth.SetOutputToWaveFile($speech)
    $synth.Speak(
        'Hello, this is a test of the live caption player. The quick brown ' +
        'fox jumps over the lazy dog. Captions should appear while this ' +
        'sentence is being spoken.'
    )
    $synth.Dispose()
}

Copy-Item -LiteralPath (Join-Path $PSScriptRoot $Page) `
    -Destination (Join-Path $web $Page) -Force
Copy-Item -LiteralPath $speech -Destination (Join-Path $web 'probe.wav') -Force


function Invoke-Cdp(
    [System.Net.WebSockets.ClientWebSocket] $socket,
    [int] $id,
    [string] $expression
) {
    $payload = @{
        id     = $id
        method = 'Runtime.evaluate'
        params = @{ expression = $expression; returnByValue = $true }
    } | ConvertTo-Json -Depth 5 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
    $socket.SendAsync(
        [System.ArraySegment[byte]]::new($bytes),
        [System.Net.WebSockets.WebSocketMessageType]::Text,
        $true,
        [System.Threading.CancellationToken]::None
    ).GetAwaiter().GetResult()

    $buffer = New-Object byte[] 65536
    $builder = New-Object System.Text.StringBuilder
    while ($true) {
        $builder.Clear() | Out-Null
        do {
            $received = $socket.ReceiveAsync(
                [System.ArraySegment[byte]]::new($buffer),
                [System.Threading.CancellationToken]::None
            ).GetAwaiter().GetResult()
            $builder.Append(
                [System.Text.Encoding]::UTF8.GetString($buffer, 0, $received.Count)
            ) | Out-Null
        } while (-not $received.EndOfMessage)

        $message = $builder.ToString() | ConvertFrom-Json
        if ($message.id -eq $id) {
            if ($message.result -and $message.result.result) {
                return [string]$message.result.result.value
            }
            return ''
        }
    }
}

$server = Start-Job -ScriptBlock {
    param($script, $port)
    & $script -Port $port
} -ArgumentList (Join-Path $root 'tool\serve_web.ps1'), $Port

$profile = Join-Path $env:TEMP "caption-probe-$([guid]::NewGuid().ToString('N'))"
$socket = $null
$browser = $null
try {
    $ready = $false
    for ($attempt = 0; $attempt -lt 40; $attempt++) {
        Start-Sleep -Milliseconds 500
        if (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) {
            $ready = $true
            break
        }
    }
    if (-not $ready) { throw "The probe server did not start on port $Port." }

    $url = "http://localhost:$Port/$Page"
    Write-Host "Probing $url with $Chrome"
    $browser = Start-Process -FilePath $Chrome -PassThru -ArgumentList @(
        '--headless=new',
        '--disable-gpu',
        '--no-first-run',
        '--mute-audio',
        '--autoplay-policy=no-user-gesture-required',
        "--remote-debugging-port=$DebugPort",
        "--user-data-dir=$profile",
        $url
    )

    $target = $null
    $connectDeadline = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $connectDeadline -and $target -eq $null) {
        Start-Sleep -Milliseconds 500
        try {
            $targets = Invoke-RestMethod -Uri "http://127.0.0.1:$DebugPort/json" -TimeoutSec 5
            $target = $targets | Where-Object {
                $_.type -eq 'page' -and $_.url -like "*$Page*"
            } | Select-Object -First 1
        }
        catch {
            $target = $null
        }
    }
    if ($target -eq $null) { throw 'The headless browser never opened the probe page.' }

    $socket = [System.Net.WebSockets.ClientWebSocket]::new()
    $socket.ConnectAsync(
        [Uri]$target.webSocketDebuggerUrl,
        [System.Threading.CancellationToken]::None
    ).GetAwaiter().GetResult()

    $messageId = 0
    $output = ''
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $messageId++
        $output = Invoke-Cdp $socket $messageId "document.getElementById('out').textContent"
        Write-Host '...' (($output -split "`n") | Select-Object -Last 1)
        if ($output -match 'DONE|FAILED') { break }
        Start-Sleep -Seconds 3
    }

    Write-Host '--- probe log ---'
    $output
}
finally {
    if ($socket -ne $null) { $socket.Dispose() }
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -in @('msedge.exe', 'chrome.exe') -and
            $_.CommandLine -and $_.CommandLine.Contains($profile)
        } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    if ($browser -ne $null -and -not $browser.HasExited) {
        Stop-Process -Id $browser.Id -Force -ErrorAction SilentlyContinue
    }
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -like 'powershell*' -and
            $_.CommandLine -and $_.CommandLine.Contains('serve_web.ps1')
        } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Stop-Job $server -ErrorAction SilentlyContinue
    Remove-Job $server -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
    Remove-Item -LiteralPath $profile -Recurse -Force -ErrorAction SilentlyContinue
}
