module CommonDataFormat

using Dates

export CDFDataset, CDFAttribute, CDFVariable, varget, attrget
export Majority, CompressionType, DataType

include("enums.jl")
include("parsing.jl")
include("records.jl")
include("variable.jl")
include("attribute.jl")
include("dataset.jl")
include("loading/cdr.jl")
include("loading/gdr.jl")
include("loading/vdr.jl")
include("loading/vxr.jl")
include("loading/vvr.jl")
include("loading/variable.jl")
include("loading/attribute.jl")


"""
    attrget(cdf::CDF, attribute_name::String) -> Vector{Any}

Retrieve a global attribute from the CDF file.
"""
function attrget(cdf::CDFDataset, attribute_name::String)
    if !haskey(cdf.attributes, attribute_name)
        error("Attribute '$attribute_name' not found in CDF file")
    end

    return cdf.attributes[attribute_name].entries
end

end
