module CommonDataFormat

using Dates, UnixTimes
using Mmap
using Dictionaries
using DiskArrays
using StaticStrings
using Base.Threads
using CodecZlib: GzipDecompressor, transcode
using LibDeflate
using LibDeflate: GzipDecompressResult

export CDFDataset, CDFVariable
export Majority, CompressionType, DataType
export Epoch, Epoch16, TT2000
export CDF_EPOCH, CDF_EPOCH16, CDF_TIME_TT2000, CDF_CHAR, CDF_UCHAR

include("epochs.jl")
include("enums.jl")
include("parsing.jl")
include("decompress.jl")
include("records/records.jl")
include("variable.jl")
include("dataset.jl")
include("loading/attribute.jl")
include("loading/variable.jl")

end
