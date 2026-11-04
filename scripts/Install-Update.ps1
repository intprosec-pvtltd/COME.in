param([Parameter(Mandatory=$true)][string]$TargetRoot)
$ErrorActionPreference='Stop'
$source=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if(-not(Test-Path $TargetRoot)){New-Item $TargetRoot -ItemType Directory -Force | Out-Null}
$target=(Resolve-Path $TargetRoot).Path
if($source -eq $target){throw 'Extract the update outside the target project before installing.'}
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$backup=Join-Path $target ('comein_code_backup_'+$stamp)
New-Item $backup -ItemType Directory -Force | Out-Null
# Only application source, tests and manifest files are replaced.
$items=@('mobile\lib','mobile\assets','mobile\test','mobile\pubspec.yaml','backend\main.py','backend\v2_api.py','backend\v3_api.py','backend\migrate_v3.py','backend\requirements.txt','backend\requirements-dev.txt','backend\tests')
foreach($item in $items){
    $origin=Join-Path $source $item
    $destination=Join-Path $target $item
    if(Test-Path $destination){
        $saved=Join-Path $backup $item
        New-Item (Split-Path $saved -Parent) -ItemType Directory -Force | Out-Null
        Copy-Item $destination $saved -Recurse -Force
        if(Test-Path $destination -PathType Container){Remove-Item $destination -Recurse -Force}
    }
    New-Item (Split-Path $destination -Parent) -ItemType Directory -Force | Out-Null
    Copy-Item $origin $destination -Recurse -Force
}
foreach($folder in @('scripts','docs')){
    $destFolder=Join-Path $target $folder
    New-Item $destFolder -ItemType Directory -Force | Out-Null
    Copy-Item (Join-Path $source ($folder+'\*')) $destFolder -Recurse -Force
}
Write-Host "Source updated. Previous source is backed up at $backup"
Write-Host 'Your .env, databases, virtual environments and existing Android/iOS build configuration were retained.'
Write-Host 'Next run scripts\Run-Backend.ps1, then scripts\Run-Mobile.ps1 in another PowerShell window.'
