param(
    [string]$Runtime = 'linux-arm64',
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release'
)

# Target the project directly: solution builds do not support a single runtime.
# Specify AnyCPU so an inherited Platform environment variable cannot interfere.
dotnet build "$PSScriptRoot/ARM64-SIMD.csproj" -c $Configuration -r $Runtime -p:Platform=AnyCPU
exit $LASTEXITCODE
