param([switch]$Demo)
$ErrorActionPreference='Stop'
$backend=Join-Path $PSScriptRoot '..\backend'
Push-Location $backend
try{
    if(-not(Test-Path '.venv\Scripts\python.exe')){& py -3.11 -m venv .venv;if($LASTEXITCODE -ne 0){throw 'Python 3.11 virtual environment creation failed.'}}
    $python=Join-Path (Get-Location) '.venv\Scripts\python.exe'
    & $python -m pip install -r requirements.txt
    if($LASTEXITCODE -ne 0){throw 'Backend dependency installation failed.'}
    if(-not(Test-Path '.env')){
        $secretBytes=New-Object byte[] 48
        $rng=[System.Security.Cryptography.RandomNumberGenerator]::Create()
        $rng.GetBytes($secretBytes);$rng.Dispose()
        $secret=[Convert]::ToBase64String($secretBytes)
        $seed=if($Demo){'true'}else{'false'}
        @("DATABASE_URL=sqlite:///./pg_dev.db","SECRET_KEY=$secret","CORS_ORIGINS=http://localhost:5173","DEMO_SEED=$seed") | Set-Content '.env' -Encoding ASCII
    }
    if(Test-Path 'pg_dev.db'){Copy-Item 'pg_dev.db' ('pg_dev_before_v3_'+(Get-Date -Format 'yyyyMMdd_HHmmss')+'.db')}
    & $python migrate_v3.py
    if($LASTEXITCODE -ne 0){throw 'Migration failed. Restore your backup before retrying.'}
    & $python -m uvicorn main:app --host 0.0.0.0 --port 8000
}finally{Pop-Location}
