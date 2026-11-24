param([string]$ProjectRoot='C:\PG-Platform\pg_platform_mvp')
$ErrorActionPreference='Stop'
$packageRoot=Split-Path $PSScriptRoot -Parent
$manifest=Get-Content (Join-Path $packageRoot 'PHASE2_MERGE_MANIFEST.json') -Raw | ConvertFrom-Json
if(!(Test-Path (Join-Path $ProjectRoot 'mobile\pubspec.yaml'))){throw 'Stay Sync project root not found.'}
$backup=Join-Path (Split-Path $ProjectRoot -Parent) ('StaySync_Phase2_Backup_'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
$pending=@()
foreach($entry in $manifest.files){
    $relative=$entry.path.Replace('/','\')
    $source=Join-Path $packageRoot $relative
    $target=Join-Path $ProjectRoot $relative
    if(!(Test-Path -LiteralPath $source -PathType Leaf)){throw "Missing packaged file: $relative"}
    $sourceHash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
    if($sourceHash -ne $entry.new_sha256){throw "Package integrity failure: $relative"}
    $exists=Test-Path -LiteralPath $target -PathType Leaf
    if($exists){
        $current=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
        if($current -eq $entry.new_sha256){continue}
        if($entry.accepted_sha256 -notcontains $current){throw "Source version mismatch: $relative. No files changed. Preserve your local edits."}
    }elseif(@($entry.accepted_sha256).Count -gt 0){throw "Existing source missing: $relative. No files changed."}
    $pending+= [pscustomobject]@{path=$relative; source=$source; target=$target; exists=$exists}
}
if($pending.Count -eq 0){Write-Host 'Already updated.' -ForegroundColor Green;return}
New-Item -ItemType Directory -Path $backup -Force|Out-Null
$applied=@()
try {
    foreach($entry in $pending){
        if($entry.exists){
            $saved=Join-Path $backup $entry.path
            New-Item -ItemType Directory -Path (Split-Path $saved) -Force|Out-Null
            Copy-Item -LiteralPath $entry.target -Destination $saved -Force
        }
    }
    $pending | Select-Object path,exists | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $backup 'rollback_manifest.json') -Encoding UTF8
    foreach($entry in $pending){
        $applied+= $entry
        New-Item -ItemType Directory -Path (Split-Path $entry.target) -Force|Out-Null
        Copy-Item -LiteralPath $entry.source -Destination $entry.target -Force
        Write-Host "Updated: $($entry.path)" -ForegroundColor Green
    }
}catch{
    foreach($entry in $applied){
        if($entry.exists){Copy-Item -LiteralPath (Join-Path $backup $entry.path) -Destination $entry.target -Force}
        elseif(Test-Path -LiteralPath $entry.target){Remove-Item -LiteralPath $entry.target -Force}
    }
    throw
}
Write-Host "Merge successful. Backup: $backup" -ForegroundColor Green
Write-Host 'No environment files, live database, storage, or hosted backend changed. Run staging QA before deployment.'
