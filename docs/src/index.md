```@meta
CurrentModule = CommonDataFormat
```

# CommonDataFormat.jl

A Julia package for reading [Common Data Format (CDF)](https://cdf.gsfc.nasa.gov/) files, widely used in space physics for storing multidimensional data arrays and metadata. See [CDFDatasets.jl](https://github.com/JuliaSpacePhysics/CDFDatasets.jl) for a high-level interface.

## Installation

```julia
using Pkg
Pkg.add("CommonDataFormat")
```

## Quick Start

```@example cdf
using CommonDataFormat

# Load a CDF file
omni_file = joinpath(pkgdir(CommonDataFormat), "data/omni_coho1hr_merged_mag_plasma_20240901_v01.cdf")
ds = CDFDataset(omni_file)
```

## API Reference

```@index
```

```@autodocs
Modules = [CommonDataFormat]
```
