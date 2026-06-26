# Rebuilds the static conference-program PDF from Program.html.
# Run this whenever assets/data/conference-program.csv changes.
#
#   pwsh tools/build-program-pdf.ps1
#
# Output: assets/pdf/SPM2026-conference-program.pdf (one day per page).
#
# It serves the repo over a temporary local HTTP server (so the page's
# CSV fetch works reliably) and prints to PDF with headless Chrome/Edge.

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$out  = Join-Path $root "assets\pdf\SPM2026-conference-program.pdf"

$chromeCandidates = @(
  "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
  "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
  "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
  "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
  "$env:LocalAppData\Google\Chrome\Application\chrome.exe"
)
$chrome = $chromeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $chrome) { throw "No Chrome/Edge found. Install Google Chrome or Microsoft Edge." }

$pdfDir = Split-Path -Parent $out
if (-not (Test-Path $pdfDir)) { New-Item -ItemType Directory -Force $pdfDir | Out-Null }
if (Test-Path $out) { Remove-Item $out -Force }

$port = 8771
$prefix = "http://127.0.0.1:$port/"

$serverScript = Join-Path $env:TEMP "spm-program-pdf-server.js"
$serverOut = Join-Path $env:TEMP "spm-program-pdf-server.out.log"
$serverErr = Join-Path $env:TEMP "spm-program-pdf-server.err.log"
@"
const http = require('http');
const fs = require('fs');
const path = require('path');
const root = process.argv[2];
const port = Number(process.argv[3]);
const types = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css',
  '.js': 'application/javascript',
  '.csv': 'text/csv; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.webp': 'image/webp',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
  '.eot': 'application/vnd.ms-fontobject',
  '.ico': 'image/x-icon',
  '.json': 'application/json',
  '.pdf': 'application/pdf'
};

http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');
  let rel = decodeURIComponent(url.pathname.replace(/^\/+/, '')) || 'index.html';
  const file = path.resolve(root, rel);
  if (!file.startsWith(path.resolve(root))) {
    res.writeHead(403);
    res.end('forbidden');
    return;
  }
  fs.readFile(file, (err, data) => {
    if (err) {
      res.writeHead(404);
      res.end('not found');
      return;
    }
    res.writeHead(200, { 'Content-Type': types[path.extname(file).toLowerCase()] || 'application/octet-stream' });
    res.end(data);
  });
}).listen(port, '127.0.0.1', () => {
  console.log('server ready on ' + port);
});
"@ | Set-Content -Path $serverScript -Encoding UTF8

$serverArgs = @(
  "`"$serverScript`"",
  "`"$root`"",
  "$port"
)
$server = Start-Process -FilePath "node" -ArgumentList $serverArgs -PassThru -WindowStyle Hidden `
  -RedirectStandardOutput $serverOut -RedirectStandardError $serverErr
$chromeProcess = $null
$socket = $null

function Receive-CdpMessage {
  param([System.Net.WebSockets.ClientWebSocket]$Socket)
  $buffer = [byte[]]::new(1048576)
  $segments = New-Object System.Collections.Generic.List[byte[]]
  do {
    $segment = [ArraySegment[byte]]::new($buffer)
    $result = $Socket.ReceiveAsync($segment, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
    if ($result.Count -gt 0) {
      $chunk = [byte[]]::new($result.Count)
      [Array]::Copy($buffer, 0, $chunk, 0, $result.Count)
      $segments.Add($chunk)
    }
  } until ($result.EndOfMessage)

  $total = ($segments | ForEach-Object { $_.Length } | Measure-Object -Sum).Sum
  $messageBytes = [byte[]]::new($total)
  $offset = 0
  foreach ($chunk in $segments) {
    [Array]::Copy($chunk, 0, $messageBytes, $offset, $chunk.Length)
    $offset += $chunk.Length
  }
  return [Text.Encoding]::UTF8.GetString($messageBytes)
}

try {
  $ready = $false
  for ($i = 0; $i -lt 40; $i++) {
    if ($server.HasExited) { break }
    try {
      $response = Invoke-WebRequest -Uri ($prefix + "Program.html?view=pdf") -UseBasicParsing -TimeoutSec 2
      if ($response.StatusCode -eq 200) {
        $ready = $true
        break
      }
    } catch {
      Start-Sleep -Milliseconds 250
    }
  }
  if (-not $ready) {
    $nodeError = if (Test-Path $serverErr) { Get-Content $serverErr -Raw } else { "" }
    throw "Temporary PDF server did not start. $nodeError"
  }

  $url = "$prefix" + "Program.html?view=pdf"
  $profile = Join-Path $env:TEMP ("spm-pdf-profile-" + [guid]::NewGuid().ToString("N"))
  $debugPort = 9223

  $chromeArgs = @(
    "--headless=new",
    "--disable-gpu",
    "--no-first-run",
    "--no-default-browser-check",
    "--remote-debugging-port=$debugPort",
    "--user-data-dir=$profile",
    $url
  )
  $chromeProcess = Start-Process -FilePath $chrome -ArgumentList $chromeArgs -PassThru -WindowStyle Hidden

  $tabs = $null
  for ($i = 0; $i -lt 80; $i++) {
    if ($chromeProcess.HasExited) { break }
    try {
      $tabs = Invoke-RestMethod -Uri "http://127.0.0.1:$debugPort/json/list" -TimeoutSec 2
      if ($tabs) { break }
    } catch {
      Start-Sleep -Milliseconds 250
    }
  }
  if (-not $tabs) {
    throw "Chrome DevTools endpoint did not start."
  }

  $tab = $tabs | Where-Object { $_.url -like "*Program.html?view=pdf*" } | Select-Object -First 1
  if (-not $tab) { $tab = $tabs | Select-Object -First 1 }
  if (-not $tab.webSocketDebuggerUrl) {
    throw "Chrome DevTools page target was not available."
  }

  $socket = [System.Net.WebSockets.ClientWebSocket]::new()
  $socket.ConnectAsync([Uri]$tab.webSocketDebuggerUrl, [Threading.CancellationToken]::None).GetAwaiter().GetResult() | Out-Null
  $script:messageId = 0

  function Invoke-Cdp {
    param(
      [string]$Method,
      [hashtable]$Params = @{}
    )
    $script:messageId += 1
    $payload = @{ id = $script:messageId; method = $Method; params = $Params } | ConvertTo-Json -Depth 20 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($payload)
    $socket.SendAsync([ArraySegment[byte]]::new($bytes), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None).GetAwaiter().GetResult() | Out-Null
    do {
      $message = Receive-CdpMessage -Socket $socket | ConvertFrom-Json
    } until ($message.id -eq $script:messageId)
    if ($message.error) {
      throw "$Method failed: $($message.error.message)"
    }
    return $message.result
  }

  Invoke-Cdp "Page.enable" | Out-Null
  $readyExpression = "document.querySelectorAll('.program-pdf-day').length >= 4 && document.querySelector('.program-sponsors') && getComputedStyle(document.querySelector('.program-sponsors')).display === 'none'"
  $isReady = $false
  for ($i = 0; $i -lt 80; $i++) {
    $result = Invoke-Cdp "Runtime.evaluate" @{ expression = $readyExpression; returnByValue = $true }
    if ($result.result.value -eq $true) {
      $isReady = $true
      break
    }
    Start-Sleep -Milliseconds 250
  }
  if (-not $isReady) {
    throw "Program page did not finish rendering for PDF."
  }

  $pdf = Invoke-Cdp "Page.printToPDF" @{
    printBackground = $true
    preferCSSPageSize = $true
    paperWidth = 8.27
    paperHeight = 11.69
    marginTop = 0
    marginRight = 0
    marginBottom = 0
    marginLeft = 0
  }
  [IO.File]::WriteAllBytes($out, [Convert]::FromBase64String($pdf.data))
} finally {
  if ($socket) {
    $socket.Dispose()
  }
  if ($chromeProcess -and -not $chromeProcess.HasExited) {
    Stop-Process -Id $chromeProcess.Id -Force -ErrorAction SilentlyContinue
  }
  if ($server -and -not $server.HasExited) {
    Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue
  }
  Remove-Item $serverScript -Force -ErrorAction SilentlyContinue
  Remove-Item $serverOut -Force -ErrorAction SilentlyContinue
  Remove-Item $serverErr -Force -ErrorAction SilentlyContinue
  if ($profile) {
    Remove-Item $profile -Recurse -Force -ErrorAction SilentlyContinue
  }
}

if (Test-Path $out) {
  $pdfSize = (Get-Item $out).Length
  if ($pdfSize -lt 100000) {
    throw "PDF generation produced an unexpectedly small file ($pdfSize bytes)."
  }
  Write-Host ("PDF written: {0} ({1:N0} bytes)" -f $out, $pdfSize)
} else {
  throw "PDF generation failed."
}
