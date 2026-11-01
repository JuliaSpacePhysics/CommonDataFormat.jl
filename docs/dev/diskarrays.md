## DiskArrays' model

- Storage is an N-d grid of chunks, each the unit of IO and compression (Zarr, NetCDF/HDF5).
- Backend implements rectangular `readblock!`. [DiskArrays][diskarrays] derives the rest of `AbstractArray` from it, chunk by chunk: indexing, broadcast, reductions, iteration.
- [`read!`][reader] is the `readblock!` primitive, and VVR/CVVR runs are irregular chunks on the record axis.
- Payoff: out-of-core compute on larger-than-memory arrays.

## Why we departed

- Being an `AbstractArray` invited Base's element-wise fallbacks, which hide disk reads.
- Chunk-aware execution pays off little:
  - Only the record dim is split.
  - Uncompressed record ranges are contiguous mmap slices, so chunk boundaries cost nothing.
  - Only compressed blocks, which decompress whole, make chunk alignment matter.
- Our integration had already turned off what DiskArrays adds. It declared `Unchunked()` ([#21][unchunked]) and bypassed DiskArrays for materialization, iteration and reductions ([#61][latency]). What remained was compile-time and maintenance cost ([#83][departure]).

[unchunked]: https://github.com/JuliaSpacePhysics/CommonDataFormat.jl/pull/21
[latency]: https://github.com/JuliaSpacePhysics/CommonDataFormat.jl/pull/61
[departure]: https://github.com/JuliaSpacePhysics/CommonDataFormat.jl/pull/83
[diskarrays]: https://github.com/JuliaIO/DiskArrays.jl
[reader]: ../../src/loading/variable.jl
