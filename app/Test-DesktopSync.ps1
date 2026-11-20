$ErrorActionPreference = 'Stop'
Add-Type -Path (Join-Path $PSScriptRoot 'DesktopSync.cs')
$server = New-Object WaterBuddySync(('a' * 64),47832)
$server.Publish('{"version":1,"entries":[]}')
function Request([string]$Method,[string]$Origin,[string]$Token) {
    $request = [Net.HttpWebRequest]::Create('http://127.0.0.1:47832/v1/drinks')
    $request.Proxy = $null; $request.Method = $Method
    $request.Headers.Add('Origin',$Origin)
    if ($Token) { $request.Headers.Add('Authorization','Bearer '+$Token) }
    try { $response = $request.GetResponse() } catch [Net.WebException] { $response = $_.Exception.Response }
    if ($null -eq $response) { throw 'No bridge response' }
    $status = [int]$response.StatusCode
    $response.Close()
    return $status
}
try {
    if ((Request 'GET' 'https://water-buddy-reminder.vercel.app' ('a'*64)) -ne 200) { throw 'Authorized read failed' }
    if ((Request 'GET' 'https://water-buddy-reminder.vercel.app' '') -ne 401) { throw 'Missing token allowed' }
    if ((Request 'GET' 'https://untrusted.example' ('a'*64)) -ne 403) { throw 'Foreign origin allowed' }
    if ((Request 'OPTIONS' 'https://water-buddy-reminder.vercel.app' '') -ne 204) { throw 'Preflight failed' }
    if ((Request 'POST' 'https://water-buddy-reminder.vercel.app' ('a'*64)) -ne 404) { throw 'Write request allowed' }
    'PASS: authenticated local read, denied missing credentials, origin isolation, preflight and read-only bridge.'
} finally { $server.Dispose() }

