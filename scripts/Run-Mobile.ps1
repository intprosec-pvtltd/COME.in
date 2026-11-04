param([string]$ApiUrl='http://10.0.2.2:8000',[string]$Device='')
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'Initialize-Mobile.ps1')
Push-Location (Join-Path $PSScriptRoot '..\mobile')
try{
    $arguments=@('run',"--dart-define=API_URL=$ApiUrl")
    if($Device){$arguments+=@('-d',$Device)}
    & flutter @arguments
    if($LASTEXITCODE -ne 0){throw 'Flutter run failed. Read the error output above.'}
}finally{Pop-Location}
