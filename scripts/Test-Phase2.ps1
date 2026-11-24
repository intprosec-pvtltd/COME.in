param([string]$ApiUrl='https://come-in.onrender.com',[switch]$BackendOnly,[switch]$MobileOnly)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if(!$MobileOnly){
    Push-Location (Join-Path $root 'backend')
    try {
        $python=Join-Path (Get-Location) '.venv\Scripts\python.exe'
        if(!(Test-Path $python)){throw 'Create the backend .venv and install requirements-dev.txt first.'}
        # Test against temporary SQLite, never the production database. Restore process environment afterward.
        $scratch=Join-Path $env:TEMP ('StaySync_QA_'+[guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $scratch|Out-Null
        $envNames=@('DATABASE_URL','SECRET_KEY','PHONE_OTP_SECRET','DEMO_SEED','PUSH_ENABLED','TRIAL_ENFORCEMENT_ENABLED','COMEIN_PRIVATE_STORAGE','COMEIN_CHAT_STORAGE','STAYSYNC_SUBSCRIPTION_DB','STAYSYNC_SUBSCRIPTION_MEDIA_DIR','ALLOW_LEGACY_EMAIL_REGISTRATION','TWILIO_ACCOUNT_SID','TWILIO_AUTH_TOKEN','TWILIO_FROM_NUMBER','TWILIO_MESSAGING_SERVICE_SID')
        $saved=@{};foreach($name in $envNames){$saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
        try {
            $env:SECRET_KEY='isolated-local-qa-secret-never-use-in-production'
            $env:PHONE_OTP_SECRET='isolated-local-qa-otp-secret-never-use-in-production'
            $env:DEMO_SEED='false';$env:PUSH_ENABLED='0';$env:TRIAL_ENFORCEMENT_ENABLED='false'
            $env:ALLOW_LEGACY_EMAIL_REGISTRATION='false'
            $env:TWILIO_ACCOUNT_SID='';$env:TWILIO_AUTH_TOKEN='';$env:TWILIO_FROM_NUMBER='';$env:TWILIO_MESSAGING_SERVICE_SID=''
            $files=@(Get-ChildItem -File -Filter 'test_*.py')+@(Get-ChildItem '.\tests' -File -Filter 'test_*.py')
            foreach($file in $files){
                $dir=Join-Path $scratch $file.BaseName;New-Item -ItemType Directory -Path $dir -Force|Out-Null
                $env:DATABASE_URL='sqlite:///'+((Join-Path $dir 'test.db').Replace('\','/'))
                $env:COMEIN_PRIVATE_STORAGE=Join-Path $dir 'private';$env:COMEIN_CHAT_STORAGE=Join-Path $dir 'chat'
                $env:STAYSYNC_SUBSCRIPTION_DB=Join-Path $dir 'billing.db';$env:STAYSYNC_SUBSCRIPTION_MEDIA_DIR=Join-Path $dir 'billing'
                & $python -m pytest -q $file.FullName
                if($LASTEXITCODE -ne 0){throw "Backend test failed: $($file.Name)"}
            }
        } finally {foreach($name in $envNames){[Environment]::SetEnvironmentVariable($name,$saved[$name],'Process')}}
        Write-Host "Backend QA complete. Isolated test files: $scratch"
    }finally{Pop-Location}
}
if(!$BackendOnly){
    Push-Location (Join-Path $root 'mobile')
    try {
        & flutter pub get;if($LASTEXITCODE -ne 0){throw 'Flutter dependency setup failed.'}
        & flutter analyze;if($LASTEXITCODE -ne 0){throw 'Flutter analysis failed.'}
        & flutter test;if($LASTEXITCODE -ne 0){throw 'Flutter tests failed.'}
        & flutter build apk --debug "--dart-define=API_URL=$ApiUrl";if($LASTEXITCODE -ne 0){throw 'APK build failed.'}
        Write-Host 'Debug APK built. Device testing still required.' -ForegroundColor Green
    }finally{Pop-Location}
}
