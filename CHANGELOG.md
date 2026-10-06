# Changelog

## [Unreleased]

### Changed

- **Breaking**: `CDF_CHAR`/`CDF_UCHAR` variables have eltype `String` (trailing null padding stripped); `StaticString` is removed. Avoids a recompile for each new string width ([#79]).

### Fixed

- Sparse and unwritten records read as the pad value, or the previous physical record for previous-record sparse variables, instead of uninitialized memory (e.g. THEMIS `th?_fgm_*_quality`).

## [0.3.0] - 2026-10-02

### Changed

- **Breaking**: `Date`, `DateTime` and `Timestamp` promote to the CDF epoch type (`TT2000`, `Epoch16`, `Epoch`) instead of the epoch promoting to `DateTime`, so mixed comparisons and differences are exact: to the nanosecond, and across leap seconds for `TT2000` ([#74]).
- **Breaking**: `DateTime(::Epoch16)` floors to the millisecond instead of rounding ([#74]).

### Added

- `Timestamp{P}(x)` conversions (Durations.jl) for all CDF epochs
- String constructors keep every fractional digit: nanoseconds for `TT2000`, picoseconds for `Epoch16` ([#74]).
- Comparison between different CDF epoch types, `Epoch16` ordering and `Epoch16 ± Period`, `Date`/`Time` and day-based accessors ([#74]).

### Fixed

- `FILLVAL` display: `TT2000` uses the ISTP fill value (`typemin(Int64)`) rather than `9999`, and `Epoch16` fill no longer throws ([#74]).

## [0.2.0] - 2026-06-11

### Changed

- **Breaking**: Renamed exported enum `DataType` to `CDFDataType` ([#46]) as the old name collided with `Base.DataType`.

[Unreleased]: https://github.com/JuliaSpacePhysics/CommonDataFormat.jl/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/JuliaSpacePhysics/CommonDataFormat.jl/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/JuliaSpacePhysics/CommonDataFormat.jl/releases/tag/v0.2.0

[#79]: https://github.com/JuliaSpacePhysics/CommonDataFormat.jl/pull/79
[#74]: https://github.com/JuliaSpacePhysics/CommonDataFormat.jl/pull/74
[#46]: https://github.com/JuliaSpacePhysics/CommonDataFormat.jl/pull/46
