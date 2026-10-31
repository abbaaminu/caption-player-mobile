# Serves build\web with the cross-origin isolation headers that the Whisper
# WebAssembly worker needs. `flutter run -d chrome` does not send those headers,
# so web captions stay switched off there. Build first, then run this script:
#
#   flutter build web --release
#   .\tool\serve_web.ps1
#
# No admin rights, Node, or Python are required.
param(
    [int] $Port = 8080,
    [string] $Root
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Join-Path (Split-Path -Parent $PSScriptRoot) 'build\web'
}
if (-not (Test-Path -LiteralPath $Root)) {
    throw "No web build found at '$Root'. Run 'flutter build web --release' first."
}
$Root = (Resolve-Path -LiteralPath $Root).Path

$mime = @{
    '.html' = 'text/html; charset=utf-8'
    '.js'   = 'text/javascript; charset=utf-8'
    '.mjs'  = 'text/javascript; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'
    '.wasm' = 'application/wasm'
    '.css'  = 'text/css; charset=utf-8'
    '.png'  = 'image/png'
    '.jpg'  = 'image/jpeg'
    '.jpeg' = 'image/jpeg'
    '.svg'  = 'image/svg+xml'
    '.ico'  = 'image/x-icon'
    '.ttf'  = 'font/ttf'
    '.otf'  = 'font/otf'
    '.woff' = 'font/woff'
    '.woff2' = 'font/woff2'
    '.map'  = 'application/json; charset=utf-8'
    '.bin'  = 'application/octet-stream'
    '.txt'  = 'text/plain; charset=utf-8'
}

$listener = New-Object System.Net.Sockets.TcpListener(
    [System.Net.IPAddress]::Loopback, $Port
)
$listener.Start()
Write-Host "Serving '$Root' on http://localhost:$Port/"
Write-Host 'Cross-Origin-Opener-Policy and Cross-Origin-Embedder-Policy are set.'
Write-Host 'Press Ctrl+C to stop.'

try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $stream = $client.GetStream()
            $reader = New-Object System.IO.StreamReader(
                $stream, [System.Text.Encoding]::ASCII, $false, 1024, $true
            )
            $requestLine = $reader.ReadLine()
            while ($true) {
                $headerLine = $reader.ReadLine()
                if ([string]::IsNullOrEmpty($headerLine)) { break }
            }
            if ([string]::IsNullOrWhiteSpace($requestLine)) { continue }

            $parts = $requestLine.Split(' ')
            $target = if ($parts.Length -ge 2) { $parts[1] } else { '/' }
            $target = $target.Split('?')[0]
            $target = [System.Uri]::UnescapeDataString($target)
            if ($target -eq '' -or $target -eq '/') { $target = '/index.html' }
            if (-not $target.StartsWith('/')) { $target = '/' + $target }

            $file = [System.IO.Path]::GetFullPath(
                (Join-Path $Root $target.TrimStart('/'))
            )
            if (-not $file.StartsWith($Root)) {
                $status = '403 Forbidden'
                $body = [byte[]]::new(0)
                $type = 'text/plain; charset=utf-8'
            }
            elseif (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
                $status = '404 Not Found'
                $body = [System.Text.Encoding]::UTF8.GetBytes('Not found')
                $type = 'text/plain; charset=utf-8'
            }
            else {
                $status = '200 OK'
                $body = [System.IO.File]::ReadAllBytes($file)
                $extension = [System.IO.Path]::GetExtension($file).ToLowerInvariant()
                $type = if ($mime.ContainsKey($extension)) {
                    $mime[$extension]
                }
                else {
                    'application/octet-stream'
                }
            }

            $head = @(
                "HTTP/1.1 $status",
                "Content-Type: $type",
                "Content-Length: $($body.Length)",
                'Cross-Origin-Opener-Policy: same-origin',
                'Cross-Origin-Embedder-Policy: require-corp',
                'Cross-Origin-Resource-Policy: cross-origin',
                'Cache-Control: no-store',
                'Connection: close',
                '',
                ''
            ) -join "`r`n"

            $headBytes = [System.Text.Encoding]::ASCII.GetBytes($head)
            $stream.Write($headBytes, 0, $headBytes.Length)
            if ($body.Length -gt 0) {
                $stream.Write($body, 0, $body.Length)
            }
            $stream.Flush()
        }
        catch {
            Write-Warning "Request failed: $($_.Exception.Message)"
        }
        finally {
            $client.Close()
        }
    }
}
finally {
    $listener.Stop()
}
