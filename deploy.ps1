param(
    [switch]$PublishOnly,
    [switch]$Run,
    [ValidateRange(1, 20)]
    [int]$Runs = 3,
    [ValidateRange(1, 100000000)]
    [int]$Length = 4000000,
    [ValidateRange(1, 100000)]
    [int]$Iterations = 150
)

$ErrorActionPreference = 'Stop'
$projectPath = Join-Path $PSScriptRoot 'ARM64-SIMD.csproj'
$publishPath = Join-Path $PSScriptRoot 'bin/Release/net10.0/linux-arm64/publish'

dotnet publish $projectPath -c Release -r linux-arm64 -p:Platform=AnyCPU --self-contained true
if ($LASTEXITCODE -ne 0) { throw "Publish failed with exit code $LASTEXITCODE." }

if ($PublishOnly) { return }

ssh.exe alfredbr@node0 "mkdir -p ~/arm64_simd"
if ($LASTEXITCODE -ne 0) { throw "Remote directory setup failed with exit code $LASTEXITCODE." }

scp.exe -r "$publishPath/*" alfredbr@node0:~/arm64_simd
if ($LASTEXITCODE -ne 0) { throw "Upload failed with exit code $LASTEXITCODE." }

ssh.exe alfredbr@node0 "chmod +x ~/arm64_simd/ARM64-SIMD"
if ($LASTEXITCODE -ne 0) { throw "Remote permission update failed with exit code $LASTEXITCODE." }

if ($Run) {
    scp.exe (Join-Path $PSScriptRoot 'benchmark-host.sh') alfredbr@node0:~/arm64_simd/benchmark-host.sh
    if ($LASTEXITCODE -ne 0) { throw "Benchmark script upload failed with exit code $LASTEXITCODE." }

    $resultsDirectory = Join-Path $PSScriptRoot 'benchmark-results'
    New-Item -ItemType Directory -Force -Path $resultsDirectory | Out-Null
    $resultsPath = Join-Path $resultsDirectory ("node0-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    ssh.exe alfredbr@node0 "sh ~/arm64_simd/benchmark-host.sh $Runs $Length $Iterations" 2>&1 |
        Tee-Object -FilePath $resultsPath
    $runExitCode = $LASTEXITCODE
    Write-Host "Results saved to $resultsPath"
    if ($runExitCode -ne 0) { throw "Remote benchmark failed with exit code $runExitCode. See $resultsPath." }
}
