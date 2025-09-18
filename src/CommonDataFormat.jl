module CommonDataFormat

using Dates, UnixTimes
using Mmap
using Dictionaries
using StaticStrings
using Base.Threads
using CodecZlib: GzipDecompressor, transcode
using LibDeflate
using LibDeflate: GzipDecompressResult

export CDFDataset, CDFVariable
export Majority, CompressionType, DataType
export Epoch, Epoch16, TT2000

include("epochs.jl")
include("enums.jl")
include("parsing.jl")
include("decompress.jl")
include("records/records.jl")
include("variable.jl")
include("dataset.jl")
include("loading/attribute.jl")
include("loading/variable.jl")

"""
    attrib(cdf::CDFDataset, attribute_name::String)

Retrieve all entries for a named attribute from the CDF file.
"""
function attrib(cdf::CDFDataset, name::String)
    RecordSizeType = recordsize_type(cdf)
    buffer = cdf.buffer
    cdf_encoding = cdf.cdr.encoding
    offsets = get_offsets(buffer, cdf.gdr.ADRhead, RecordSizeType)
    for offset in offsets
        adr = ADR(buffer, offset, RecordSizeType)
        name == String(adr.Name) && return load_attribute_entries(buffer, adr, RecordSizeType, cdf_encoding)
    end
    error("Attribute '$name' not found in CDF file")
end

end
