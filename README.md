# CommonDataFormat.jl

[![Build Status](https://github.com/JuliaSpacePhysics/CommonDataFormat.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/JuliaSpacePhysics/CommonDataFormat.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/JuliaSpacePhysics/CommonDataFormat.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/JuliaSpacePhysics/CommonDataFormat.jl)

A Julia package for reading [Common Data Format (CDF)](https://cdf.gsfc.nasa.gov/) files, widely used in space physics for storing multidimensional data arrays and metadata. See [CDFDatasets.jl](https://github.com/JuliaSpacePhysics/CDFDatasets.jl) for a high-level interface.

**Installation**: at the Julia REPL, run `using Pkg; Pkg.add("CommonDataFormat")`

**Documentation**: [![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://juliaspacephysics.github.io/CommonDataFormat.jl/dev/)

## Features

- **Pure Julia implementation** - No external dependencies on CDF libraries
- **Efficient data access** - Memory-mapped access for data and attributes, super fast decompression using [`LibDeflate`](https://github.com/jakobnissen/LibDeflate.jl)
- **[DiskArrays.jl](https://github.com/JuliaIO/DiskArrays.jl) integration** - Lazy representation of data on hard disk with AbstractDiskArray interface

## Quick Start

```julia
using CommonDataFormat

# Load a CDF file
cdf = CDFDataset("data.cdf")

# Access basic information
println("CDF version: ", cdf.version)
println("Data majority: ", cdf.majority)
println("Compression: ", cdf.compression)

# List all variables
println("Variables: ", keys(cdf))

# Access a variable
var = cdf["temperature"]
```

## Elsewhere

- [CDFpp](https://github.com/SciQLop/CDFpp): A modern C++ header only cdf library with Python bindings
- [cdflib](https://github.com/MAVENSDC/cdflib): A python module for reading and writing NASA's Common Data Format (cdf) files

## Reference

- [CDF Internal Format Description](https://spdf.gsfc.nasa.gov/pub/software/cdf/doc/cdfifd.pdf)