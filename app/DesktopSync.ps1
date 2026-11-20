function Publish-DesktopSync {
    if ($null -eq $script:syncBridge) { return }
    $entries = @($script:data.Entries | ForEach-Object {
        @{ id = [string]$_.Id; at = ([DateTimeOffset]([datetime]$_.Time)).ToUnixTimeMilliseconds(); amount = [int]$_.Ml }
    })
    $script:syncBridge.Publish((@{ version = 1; source = $script:syncSource; entries = $entries } | ConvertTo-Json -Depth 5 -Compress))
}
function Start-DesktopSync {
    if ($SmokeTest) { return }
    try {
        $identityPath = Join-Path $PSScriptRoot 'sync-identity.json'
        if (Test-Path -LiteralPath $identityPath) {
            $identity = Get-Content -LiteralPath $identityPath -Raw | ConvertFrom-Json
        } else {
            $random = New-Object byte[] 32
            $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
            try { $rng.GetBytes($random) } finally { $rng.Dispose() }
            $identity = @{ token = ([BitConverter]::ToString($random)).Replace('-', '').ToLowerInvariant(); source = [guid]::NewGuid().ToString() }
            $identity | ConvertTo-Json | Set-Content -LiteralPath $identityPath -Encoding UTF8
        }
        if ($identity.token -notmatch '^[a-f0-9]{64}$' -or $identity.source -notmatch '^[a-f0-9-]{36}$') { throw 'Invalid sync identity' }
        $script:syncToken = $identity.token
        $script:syncSource = $identity.source
        Add-Type -Path (Join-Path $PSScriptRoot 'DesktopSync.cs')
        $script:syncBridge = New-Object WaterBuddySync($script:syncToken, 47831)
        Publish-DesktopSync
    } catch { $script:syncError = 'Desktop sync could not start. Restart Water Buddy and try again.' }
}
function Open-WebDashboard {
    if ($null -eq $script:syncBridge) {
        [Windows.Forms.MessageBox]::Show($script:syncError, 'Water Buddy sync') | Out-Null
        return
    }
    Start-Process ('https://water-buddy-reminder.vercel.app/#desktop-sync=' + $script:syncToken)
}
