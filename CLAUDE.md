# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A .NET 11 console benchmark that runs the same logistic-map workload (`x = 3.96 * (x * (1 - x))`, repeated `iterations` times per element) four ways: scalar, `Parallel.For` scalar, parallel + `Vector<float>` SIMD, and GPU via ILGPU (CUDA preferred). It targets both Windows x64 and Linux ARM64 (NEON). There is no test project; correctness is checked by comparing the checksum each variant prints.

## Commands

Always target the `.csproj` (not the `.slnx`) and pass `-p:Platform=AnyCPU`, because a shell environment that sets `Platform=x64` breaks runtime-specific builds.

```powershell
dotnet build ARM64-SIMD.csproj -p:Platform=AnyCPU                      # local Debug build
dotnet run --project ARM64-SIMD.csproj -c Release -p:Platform=AnyCPU -- --length=4000000 --iterations=150 --warmup=1
./build.ps1                       # Release, linux-arm64 (-Configuration / -Runtime to override)
./deploy.ps1 -PublishOnly         # self-contained linux-arm64 publish, no upload
./deploy.ps1 node3 [-Run -Runs 3 -Length N -Iterations N]   # publish linux-arm64 + scp to alfredbr@<node>:~/arm64_simd (default node0), optionally benchmark
./benchmark.ps1 -Nodes node0,node3 -Runs 3            # detect arch per host via ssh, publish, deploy, run benchmark-host.sh
./Clean.ps1 node3 [-WhatIf]                           # rm -rf ~/arm64_simd on that host
```

Performance numbers are only meaningful in Release. Remote benchmark output (raw + Markdown report) lands in `benchmark-results/`.

## Architecture

- `Program.cs` holds everything on the CPU side, as top-level statements plus internal types: `DemoConfig` (CLI parsing for `--length`, `--iterations`, `--warmup`), `DataFactory` (deterministic `sin`-based data in (0,1)), `Benchmark.Run` (warmup at `iterations/10`, then a `Stopwatch`-timed run), and `Workloads`. Every workload has the signature `Func<float[], int, double>` and returns the sum of the final values (the checksum).
- `Gpu/GpuBenchmark.cs`: `TryCreate` picks a non-CPU ILGPU device (CUDA first). It returns null with a status message when no device is found, so the GPU row is simply skipped. `Execute` follows the same workload signature so it can go through `Benchmark.Run`.
- `Gpu/GpuKernels.cs`: the ILGPU kernel. It reads `Workloads.LogisticMultiplier`, so the constant has a single source.

## Invariants to preserve

- **Keep the operation order identical** in `LogisticStep`, `IterateSimd`, and `GpuKernels.Logistic`: compute `value * (1 - value)` first, then multiply by the constant. Any reordering, or letting the JIT fuse into FMA differently, changes rounding and the checksums stop matching across variants. Checksums may differ *between* machines (x64 vs ARM64 values differ in the README); they must match *between variants on the same machine*.
- `ParallelSimd` must keep chunked `Partitioner.Create` ranges (chunk ≈ vectors / (ProcessorCount*4)). Per-vector tasks made SIMD slower than parallel scalar. Tail elements that do not fill a whole vector go through the scalar path.
- Per-thread `double` sums are combined under a `lock`, because `Interlocked.Add` has no `double` overload.
- Don't hard-code the SIMD width; code relies on `Vector<float>.Count` (4 on NEON, 8 on AVX2, 16 on AVX-512).

## Other docs

`README.md` (results tables, troubleshooting), `GPU.md` (CUDA/ILGPU setup), `MATH.md`, `RESULTS.md`, and `PROMPT.md` (the original generation prompt; its "no external packages" rule is outdated now that ILGPU is used).
