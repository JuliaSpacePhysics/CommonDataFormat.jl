module CommonDataFormat

using Dates
using Mmap
using Dictionaries

export CDFDataset, CDFAttribute, CDFVariable, varget, attrget
export Majority, CompressionType, DataType

include("enums.jl")
include("parsing.jl")
include("records/records.jl")
include("attribute.jl")
include("dataset.jl")
include("variable.jl")
include("loading/vvr.jl")
include("loading/attribute.jl")

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
