# Rebuilds the static conference-program PDF from ProgramDraft.html.
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
  "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
  "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
  "$env:LocalAppData\Google\Chrome\Application\chrome.exe",
  "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
  "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
)
$chrome = $chromeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $chrome) { throw "No Chrome/Edge found. Install Google Chrome or Microsoft Edge." }

$pdfDir = Split-Path -Parent $out
if (-not (Test-Path $pdfDir)) { New-Item -ItemType Directory -Force $pdfDir | Out-Null }
if (Test-Path $out) { Remove-Item $out -Force }

$port = 8771
$prefix = "http://localhost:$port/"

# --- Start a minimal static file server in a background job ---
$server = Start-Job -ScriptBlock {
  param($root, $prefix)
  $mime = @{
    ".html"="text/html"; ".css"="text/css"; ".js"="application/javascript";
    ".csv"="text/csv"; ".png"="image/png"; ".jpg"="image/jpeg"; ".jpeg"="image/jpeg";
    ".gif"="image/gif"; ".svg"="image/svg+xml"; ".woff"="font/woff"; ".woff2"="font/woff2";
    ".ttf"="font/ttf"; ".eot"="application/vnd.ms-fontobject"; ".ico"="image/x-icon";
    ".json"="application/json"; ".pdf"="application/pdf"
  }
  $listener = [System.Net.HttpListener]::new()
  $listener.Prefixes.Add($prefix)
  $listener.Start()
  while ($listener.IsListening) {
    try { $ctx = $listener.GetContext() } catch { break }
    try {
      $rel = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath.TrimStart('/'))
      if ([string]::IsNullOrWhiteSpace($rel)) { $rel = "index.html" }
      $path = Join-Path $root $rel
      if (Test-Path $path -PathType Leaf) {
        $bytes = [System.IO.File]::ReadAllBytes($path)
        $ext = [System.IO.Path]::GetExtension($path).ToLower()
        if ($mime.ContainsKey($ext)) { $ctx.Response.ContentType = $mime[$ext] }
        $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
      } else {
        $ctx.Response.StatusCode = 404
      }
    } catch {} finally { $ctx.Response.OutputStream.Close() }
  }
} -ArgumentList $root, $prefix

try {
  Start-Sleep -Milliseconds 800
  $url = "$prefix" + "ProgramDraft.html?view=pdf"
  $profile = Join-Path $env:TEMP "spm-pdf-profile"

  & $chrome --headless=new --disable-gpu --no-first-run --no-default-browser-check `
    "--user-data-dir=$profile" --virtual-time-budget=12000 `
    --run-all-compositor-stages-before-draw `
    --no-pdf-header-footer "--print-to-pdf=$out" $url 2>&1 | Out-Null
} finally {
  Stop-Job $server -ErrorAction SilentlyContinue
  Remove-Job $server -Force -ErrorAction SilentlyContinue
}

if (Test-Path $out) {
  Write-Host ("PDF written: {0} ({1:N0} bytes)" -f $out, (Get-Item $out).Length)
} else {
  throw "PDF generation failed."
}
