[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidatePattern('^[a-zA-Z0-9.-]+$')]
    [string]$Node,
    [ValidatePattern('^[a-zA-Z0-9_-]+$')]
    [string]$UserName = 'alfredbr'
)
$ErrorActionPreference = 'Stop'
$destination = "${UserName}@${Node}"
$remotePath = '~/arm64_simd'

& ssh.exe -o BatchMode=yes -o ConnectTimeout=15 $destination "test -d $remotePath"
switch ($LASTEXITCODE) {
    0 { }
    1 { Write-Host "No deployment found at ${destination}:$remotePath."; return }
    default { throw "Cannot reach $destination (ssh exit code $LASTEXITCODE)." }
}

if ($PSCmdlet.ShouldProcess("${destination}:$remotePath", 'Remove deployment')) {
    & ssh.exe -o BatchMode=yes -o ConnectTimeout=15 $destination "rm -rf $remotePath"
    if ($LASTEXITCODE -ne 0) { throw "Removal failed with exit code $LASTEXITCODE." }
    Write-Host "Removed ${destination}:$remotePath."
}
