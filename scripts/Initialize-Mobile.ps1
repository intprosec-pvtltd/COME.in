param([string]$MobilePath = (Join-Path $PSScriptRoot '..\mobile'))
$ErrorActionPreference = 'Stop'
$MobilePath = (Resolve-Path $MobilePath).Path
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) { throw 'Flutter is not on PATH. Install/configure Flutter first.' }
$needed = @('android','ios') | Where-Object { -not (Test-Path (Join-Path $MobilePath $_)) }
if ($needed.Count -gt 0) {
    $tempProject = Join-Path ([System.IO.Path]::GetTempPath()) ('comein_native_' + [Guid]::NewGuid().ToString('N'))
    try {
        & flutter create --platforms=android,ios --org com.intprosec --project-name pg_resident $tempProject
        if ($LASTEXITCODE -ne 0) { throw 'Flutter could not generate native project shells.' }
        foreach ($platform in $needed) { Copy-Item (Join-Path $tempProject $platform) (Join-Path $MobilePath $platform) -Recurse }
    } finally { if (Test-Path $tempProject) { Remove-Item $tempProject -Recurse -Force } }
}
& (Join-Path $PSScriptRoot 'Configure-Native.ps1') -MobilePath $MobilePath
Push-Location $MobilePath
try {
    & flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed.' }
    & dart run flutter_launcher_icons
    if ($LASTEXITCODE -ne 0) { throw 'Launcher icon generation failed.' }
} finally { Pop-Location }
Write-Host 'Native setup complete. Existing Android/iOS build configuration was retained.'
