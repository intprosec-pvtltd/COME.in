param([string]$MobilePath = (Join-Path $PSScriptRoot '..\mobile'))
$ErrorActionPreference='Stop'
$androidNamespace='http://schemas.android.com/apk/res/android'
$manifest=Join-Path $MobilePath 'android\app\src\main\AndroidManifest.xml'
if(Test-Path $manifest){
    Copy-Item $manifest ($manifest+'.comein-backup') -Force
    [xml]$xml=Get-Content $manifest -Raw
    foreach($permission in @('android.permission.INTERNET','android.permission.CAMERA')){
        $exists=$false
        foreach($node in $xml.manifest.SelectNodes('uses-permission')){if($node.GetAttribute('name',$androidNamespace)-eq $permission){$exists=$true}}
        if(-not $exists){$node=$xml.CreateElement('uses-permission');$node.SetAttribute('name',$androidNamespace,$permission);[void]$xml.manifest.AppendChild($node)}
    }
    $xml.manifest.application.SetAttribute('label',$androidNamespace,'COME.in')
    $xml.Save($manifest)
    # Permit the emulator development server in debug only. Release stays HTTPS-first.
    $debug=Join-Path $MobilePath 'android\app\src\debug\AndroidManifest.xml'
    if(Test-Path $debug){
        [xml]$d=Get-Content $debug -Raw
        $appNode=$d.manifest.SelectSingleNode('application')
        if($null -eq $appNode){$appNode=$d.CreateElement('application');[void]$d.manifest.AppendChild($appNode)}
        $appNode.SetAttribute('usesCleartextTraffic',$androidNamespace,'true');$d.Save($debug)
    }
}
$plist=Join-Path $MobilePath 'ios\Runner\Info.plist'
if(Test-Path $plist){
    Copy-Item $plist ($plist+'.comein-backup') -Force
    [xml]$p=Get-Content $plist -Raw
    $values=@{NSCameraUsageDescription='Capture photos for your PG community and maintenance requests.';NSPhotoLibraryUsageDescription='Select photos to share with your PG or attach to maintenance requests.';NSLocalNetworkUsageDescription='Connect to your configured PG management server on the local network.';CFBundleDisplayName='COME.in'}
    foreach($key in $values.Keys){
        $keyNode=@($p.plist.dict.SelectNodes('key')) | Where-Object {$_.InnerText -eq $key} | Select-Object -First 1
        if($null -ne $keyNode){$keyNode.NextSibling.InnerText=$values[$key]}else{$k=$p.CreateElement('key');$k.InnerText=$key;$v=$p.CreateElement('string');$v.InnerText=$values[$key];[void]$p.plist.dict.AppendChild($k);[void]$p.plist.dict.AppendChild($v)}
    }
    $p.Save($plist)
}
