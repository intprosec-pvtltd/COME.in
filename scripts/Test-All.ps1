$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'Initialize-Mobile.ps1')
Push-Location (Join-Path $PSScriptRoot '..\mobile')
try{
    & flutter analyze
    if($LASTEXITCODE -ne 0){throw 'Flutter analyzer reported problems.'}
    & flutter test
    if($LASTEXITCODE -ne 0){throw 'Flutter widget/unit tests failed.'}
    & flutter build apk --debug --dart-define=API_URL=http://10.0.2.2:8000
    if($LASTEXITCODE -ne 0){throw 'Android debug build failed.'}
}finally{Pop-Location}
Push-Location (Join-Path $PSScriptRoot '..\backend')
try{
    $python=Join-Path (Get-Location) '.venv\Scripts\python.exe'
    if(-not(Test-Path $python)){throw 'Run Run-Backend.ps1 first to create the backend environment.'}
    & $python -m pip install -r requirements-dev.txt
    if($LASTEXITCODE -ne 0){throw 'Test dependency installation failed.'}
    & $python -m pytest tests -q
    if($LASTEXITCODE -ne 0){throw 'Backend integration tests failed.'}
}finally{Pop-Location}
