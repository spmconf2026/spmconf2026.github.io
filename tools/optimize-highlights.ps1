<#
  Converts JPG/PNG photos in assets/img/highlights/ to WebP, shrinking them to a
  sensible web size. The originals are large camera files (several MB each), which
  makes the front page unusable on a slow connection.

  Run it after dropping new photos in, then run build-gallery.ps1:
      pwsh tools/optimize-highlights.ps1
      pwsh tools/build-gallery.ps1

  Photos listed in $KeepFullRes carry detail worth zooming into, so they get a
  second copy at original resolution in highlights/full/. The gallery always uses
  the small version; only the lightbox loads the full one, and only when opened.

  Requires ffmpeg on PATH. Originals are left on disk; delete them yourself once
  you are happy with the result.
#>

param(
    [int]$MaxEdge = 2048,
    [int]$Quality = 82,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Basenames (without extension) to re-encode at full resolution.
$KeepFullRes = @(
    '0_Dinner_0',
    '1_Dinner_HandsDown',
    '2_Closing',
    'Dinner_1',
    'Dinner_HandsUp'
)

if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    throw 'ffmpeg not found on PATH. Install it (choco install ffmpeg) and re-run.'
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$imgDir = Join-Path $repoRoot 'assets/img/highlights'
$fullDir = Join-Path $imgDir 'full'

$sources = Get-ChildItem -Path $imgDir -File |
           Where-Object { @('.jpg', '.jpeg', '.png') -contains $_.Extension.ToLower() } |
           Sort-Object Name

if ($sources.Count -eq 0) {
    Write-Host 'Nothing to convert.'
    return
}

# Long edge capped at $MaxEdge without upscaling; -2 keeps the aspect ratio and
# an even dimension.
$scale = "scale='if(gt(iw,ih),min($MaxEdge,iw),-2)':'if(gt(iw,ih),-2,min($MaxEdge,ih))'"

$totalBefore = 0
$totalAfter = 0

foreach ($src in $sources) {
    $base = [IO.Path]::GetFileNameWithoutExtension($src.Name)
    $dest = Join-Path $imgDir "$base.webp"
    $full = $KeepFullRes -contains $base

    if ((Test-Path $dest) -and -not $Force) {
        Write-Host "skip   $($src.Name) (webp exists; use -Force to redo)"
        continue
    }

    # Small copy for the carousel - every photo gets one, including the full-res
    # ones, so the front page never downloads a multi-megabyte file to show a
    # 630px-tall slide.
    & ffmpeg -hide_banner -loglevel error -y -i $src.FullName -vf $scale `
        -c:v libwebp -quality $Quality -preset photo $dest
    if ($LASTEXITCODE -ne 0) { throw "ffmpeg failed on $($src.Name)" }

    $after = (Get-Item $dest).Length

    if ($full) {
        New-Item -ItemType Directory -Force $fullDir | Out-Null
        $destFull = Join-Path $fullDir "$base.webp"
        & ffmpeg -hide_banner -loglevel error -y -i $src.FullName `
            -c:v libwebp -quality $Quality -preset photo $destFull
        if ($LASTEXITCODE -ne 0) { throw "ffmpeg failed on $($src.Name) (full-res)" }
        $after += (Get-Item $destFull).Length
    }

    $before = $src.Length
    $totalBefore += $before
    $totalAfter += $after

    $tag = if ($full) { "max $MaxEdge px + full-res copy" } else { "max $MaxEdge px" }
    '{0,-26} {1,7:N2} MB -> {2,6:N2} MB  ({3})' -f $src.Name, ($before / 1MB), ($after / 1MB), $tag
}

if ($totalBefore -gt 0) {
    ''
    'Total: {0:N1} MB -> {1:N1} MB ({2:N0}% smaller)' -f ($totalBefore / 1MB), ($totalAfter / 1MB),
        ((1 - $totalAfter / $totalBefore) * 100)
    ''
    'Originals are still on disk. Once the gallery looks right, remove the JPGs and run:'
    '    pwsh tools/build-gallery.ps1'
}
