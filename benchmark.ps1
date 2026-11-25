param(
    [ValidatePattern('^[a-zA-Z0-9.-]+$')]
    [string[]]$Nodes = @('node0', 'node3'),
    [ValidatePattern('^[a-zA-Z0-9_-]+$')]
    [string]$UserName = 'alfredbr',
    [ValidateRange(1,20)][int]$Runs = 3,
    [ValidateRange(1,100000000)][int]$Length = 4000000,
    [ValidateRange(1,100000)][int]$Iterations = 150
)
$ErrorActionPreference = 'Stop'
$resultsDirectory = Join-Path $PSScriptRoot 'benchmark-results'
New-Item -ItemType Directory -Force -Path $resultsDirectory | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$published = @{}
$failedNodes = @()
foreach ($node in $Nodes) {
    try {
        $destination = "${UserName}@${node}"
        $architecture = (& ssh.exe -o BatchMode=yes -o ConnectTimeout=15 $destination 'uname -m' | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) { throw "Cannot inspect $node." }
        $runtime = switch ($architecture) {
            'aarch64' { 'linux-arm64' }
            'x86_64' { 'linux-x64' }
            default { throw "Unsupported architecture: $architecture" }
        }
        if (-not $published.ContainsKey($runtime)) {
            dotnet publish (Join-Path $PSScriptRoot 'ARM64-SIMD.csproj') -c Release -r $runtime -p:Platform=AnyCPU --self-contained true
            if ($LASTEXITCODE -ne 0) { throw "Publish failed for $runtime." }
            $published[$runtime] = Join-Path $PSScriptRoot "bin/Release/net11.0/$runtime/publish"
        }
        & ssh.exe -o BatchMode=yes -o ConnectTimeout=15 $destination 'mkdir -p ~/arm64_simd'
        if ($LASTEXITCODE -ne 0) { throw 'Remote directory setup failed.' }
        & scp.exe -o BatchMode=yes -r "$($published[$runtime])/*" "${destination}:~/arm64_simd/"
        if ($LASTEXITCODE -ne 0) { throw 'Deployment upload failed.' }
        & scp.exe -o BatchMode=yes (Join-Path $PSScriptRoot 'benchmark-host.sh') "${destination}:~/arm64_simd/benchmark-host.sh"
        if ($LASTEXITCODE -ne 0) { throw 'Benchmark harness upload failed.' }
        & ssh.exe -o BatchMode=yes $destination 'chmod +x ~/arm64_simd/ARM64-SIMD'
        if ($LASTEXITCODE -ne 0) { throw 'Remote permission update failed.' }
        $rawPath = Join-Path $resultsDirectory "$node-$stamp.txt"
        & ssh.exe -o BatchMode=yes $destination "sh ~/arm64_simd/benchmark-host.sh $Runs $Length $Iterations" 2>&1 | Tee-Object -FilePath $rawPath
        $runExitCode = $LASTEXITCODE
        if ($runExitCode -ne 0) { throw "Benchmark failed (exit $runExitCode). Output: $rawPath" }
        $raw = Get-Content -LiteralPath $rawPath -Raw
        $pattern = '(?m)^(?<mode>Scalar \(1 thread\)|Parallel \(per core\)|Parallel \+ SIMD|GPU \(ILGPU\))\s+(?<ms>[\d,]+\.\d+) ms\s+\|\s+throughput (?<throughput>[\d,]+\.\d+) M it/s\s+\|\s+checksum (?<checksum>[\d.]+)'
        $measurements = @([regex]::Matches($raw, $pattern) | ForEach-Object {
            [pscustomobject]@{ Mode=$_.Groups['mode'].Value; Milliseconds=[double]::Parse($_.Groups['ms'].Value, [cultureinfo]::InvariantCulture); Checksum=$_.Groups['checksum'].Value }
        })
        if ($measurements.Count -ne 4 * $Runs) { throw "Expected $($Runs * 4) measurements; found $($measurements.Count). See $rawPath" }
        $groups = @(foreach ($mode in @('Scalar (1 thread)', 'Parallel (per core)', 'Parallel + SIMD', 'GPU (ILGPU)')) { $measurements | Where-Object Mode -EQ $mode | Group-Object Mode })
        $baseline = ($groups[0].Group.Milliseconds | Measure-Object -Average).Average
        $report = @("# $node Benchmark Results", '', "Captured: $(Get-Date -Format o)", '', "Deployment: $destination`:~/arm64_simd; Release, self-contained .NET 11, $runtime.", '', "Workload: $Length floats x $Iterations iterations; $Runs runs; one warmup per mode.", '', '| Mode | Run times (ms) | Mean time (ms) | Throughput (M iter/s) | Speedup |', '|---|---|---:|---:|---:|')
        foreach ($group in $groups) {
            if ($group.Count -ne $Runs) { throw "Incomplete measurements for $($group.Name)." }
            $mean = ($group.Group.Milliseconds | Measure-Object -Average).Average
            $times = ($group.Group | ForEach-Object { $_.Milliseconds.ToString('N1', [cultureinfo]::InvariantCulture) }) -join ', '
            $report += [string]::Format([cultureinfo]::InvariantCulture, '| {0} | {1} | {2:N1} | {3:N1} | {4:F2}x |', $group.Name, $times, $mean, ($Length * [double]$Iterations / $mean / 1000), ($baseline / $mean))
        }
        $checksums = @($measurements.Checksum | Select-Object -Unique)
        $report += @('', "Checksums observed: $($checksums -join ', '). All matched: $($checksums.Count -eq 1).", '', 'Throughput is computed from mean elapsed time. Speedup is relative to the scalar mean.', '', "[Raw host details and benchmark output]($node-$stamp.txt)", '', '## Captured output', '', '```text', $raw.TrimEnd(), '```')
        $markdownPath = Join-Path $resultsDirectory "$node-$stamp.md"
        $report | Set-Content -LiteralPath $markdownPath -Encoding utf8
        Write-Host "Markdown report saved to $markdownPath"
    } catch {
        $failedNodes += $node
        $failurePath = Join-Path $resultsDirectory "$node-$stamp-error.txt"
        $_ | Out-String | Set-Content -LiteralPath $failurePath
        Write-Warning "$node failed: $_ (saved to $failurePath)"
    }
}
if ($failedNodes.Count -gt 0) { throw "Benchmark failed for: $($failedNodes -join ', ')" }
