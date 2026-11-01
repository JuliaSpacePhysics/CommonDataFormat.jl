## DiskArrays' model

- Storage is an N-d grid of chunks, each the unit of IO and compression (Zarr, NetCDF/HDF5).
- Backend implements rectangular `readblock!`. [DiskArrays][diskarrays] derives the rest of `AbstractArray` from it, chunk by chunk: indexing, broadcast, reductions, iteration.
- [`read!`][reader] is the `readblock!` primitive, and VVR/CVVR runs are irregular chunks on the record axis.
- Payoff: out-of-core compute on larger-than-memory arrays.

## Why we departed

- Being an `AbstractArray` invited Base's element-wise fallbacks, which hide disk reads.
- CDF files are record-oriented and typically small enough to read whole or slice by time. Chunk-aware execution pays off little.
- Paying for generality: compile latency for each part type, and chunk metadata one had to fake (EmptyDiskVector, the eachchunk override) ([#83][departure]).
- We had already turned off what DiskArrays adds by declaring `Unchunked()` ([#21][unchunked]) and bypassing DiskArrays for materialization, iteration and reductions ([#61][latency]).

[unchunked]: https://github.com/JuliaSpacePhysics/CommonDataFormat.jl/pull/21
[latency]: https://github.com/JuliaSpacePhysics/CommonDataFormat.jl/pull/61
[departure]: https://github.com/JuliaSpacePhysics/CommonDataFormat.jl/pull/83
[diskarrays]: https://github.com/JuliaIO/DiskArrays.jl
[reader]: ../../src/loading/variable.jl
