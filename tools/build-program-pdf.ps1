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
$legacyOutputs = @(
  (Join-Path $root "SPM2026-program.pdf"),
  (Join-Path $root "SPM2026-program-4pages.pdf"),
  (Join-Path $root "Program-pdf-tight.html"),
  (Join-Path $root "SPM2026-program-4pages-page1.png")
)

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
foreach ($legacyOutput in $legacyOutputs) {
  Remove-Item $legacyOutput -Force -ErrorAction SilentlyContinue
}

$port = 8771
$prefix = "http://127.0.0.1:$port/"

do {
  $includeChairsAnswer = (Read-Host "Include session chairs in the PDF? [Y/n]").Trim().ToLowerInvariant()
} until ($includeChairsAnswer -in @("", "y", "yes", "n", "no"))

$includeChairs = $includeChairsAnswer -notin @("n", "no")
$chairsQueryValue = if ($includeChairs) { "1" } else { "0" }
$programPdfUrl = "$prefix" + "Program.html?view=pdf&chairs=$chairsQueryValue"

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
      $response = Invoke-WebRequest -Uri $programPdfUrl -UseBasicParsing -TimeoutSec 2
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

  $url = $programPdfUrl
  $profile = Join-Path $env:TEMP ("spm-pdf-profile-" + [guid]::NewGuid().ToString("N"))
  $debugPort = Get-Random -Minimum 30000 -Maximum 45000

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
  Invoke-Cdp "Page.navigate" @{ url = $url } | Out-Null
  $readyExpression = "(() => { const sponsors = document.querySelector('.program-sponsors'); return document.readyState === 'complete' && document.body.classList.contains('program-pdf-mode') && document.querySelectorAll('.program-pdf-day').length >= 4 && (!sponsors || getComputedStyle(sponsors).display === 'none'); })()"
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
    $diagnosticExpression = "(() => { const sponsors = document.querySelector('.program-sponsors'); const status = document.querySelector('#program-status'); return JSON.stringify({ url: location.href, readyState: document.readyState, bodyClass: document.body.className, pdfDays: document.querySelectorAll('.program-pdf-day').length, sponsorsDisplay: sponsors ? getComputedStyle(sponsors).display : null, status: status ? status.textContent.trim() : null, cards: document.querySelectorAll('.program-card,.program-session-card').length }); })()"
    $diagnostic = Invoke-Cdp "Runtime.evaluate" @{ expression = $diagnosticExpression; returnByValue = $true }
    throw "Program page did not finish rendering for PDF. State: $($diagnostic.result.value)"
  }

  $tightPrintCss = @"
@media print {
  @page { size: A4; margin: 8mm; }
  html, body { width: 210mm !important; min-height: auto !important; }
  body.program-pdf-mode { zoom: 0.88; }
  body.program-pdf-mode .program-pdf-day {
    min-height: auto !important;
    height: auto !important;
    break-before: page;
    page-break-before: always;
    padding-bottom: 0 !important;
  }
  body.program-pdf-mode .program-pdf-day:first-child {
    break-before: auto;
    page-break-before: auto;
  }
  body.program-pdf-mode .program-pdf-day-body {
    display: block !important;
  }
  body.program-pdf-mode .program-card,
  body.program-pdf-mode .program-session-card {
    margin-bottom: 6px !important;
  }
  body.program-pdf-mode .program-pdf-day-header {
    margin-bottom: 7px !important;
    padding-bottom: 6px !important;
  }
  body.program-pdf-mode .program-details,
  body.program-pdf-mode .program-session-details {
    padding-top: 7px !important;
    padding-bottom: 7px !important;
  }
  body.program-pdf-mode .program-time {
    padding-top: 7px !important;
    padding-bottom: 7px !important;
  }
}
"@
  $tightPrintCssJson = $tightPrintCss | ConvertTo-Json -Compress
  Invoke-Cdp "Runtime.evaluate" @{
    expression = "(() => { const id = 'program-pdf-tight-print'; const old = document.getElementById(id); if (old) old.remove(); const style = document.createElement('style'); style.id = id; style.textContent = $tightPrintCssJson; document.head.appendChild(style); return true; })()"
    returnByValue = $true
  } | Out-Null

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
  foreach ($legacyOutput in $legacyOutputs) {
    Remove-Item $legacyOutput -Force -ErrorAction SilentlyContinue
  }
  if ($profile) {
    Remove-Item $profile -Recurse -Force -ErrorAction SilentlyContinue
  }
}

if (Test-Path $out) {
  $pdfSize = (Get-Item $out).Length
  if ($pdfSize -lt 100000) {
    throw "PDF generation produced an unexpectedly small file ($pdfSize bytes)."
  }
  $pdfInfo = Get-Command pdfinfo -ErrorAction SilentlyContinue
  if (-not $pdfInfo) {
    $pdfInfo = Get-Command "C:\texlive\2026\bin\windows\pdfinfo.exe" -ErrorAction SilentlyContinue
  }
  if ($pdfInfo) {
    $infoText = & $pdfInfo.Source $out
    $pagesLine = $infoText | Select-String -Pattern '^Pages:\s+(\d+)'
    if ($pagesLine -and [int]$pagesLine.Matches[0].Groups[1].Value -ne 4) {
      throw "PDF generation produced $($pagesLine.Matches[0].Groups[1].Value) pages; expected 4."
    }
  }
  Write-Host ("PDF written: {0} ({1:N0} bytes)" -f $out, $pdfSize)
} else {
  throw "PDF generation failed."
}
