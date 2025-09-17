# Attribute loading functionality
# Handles loading of ADR (Attribute Descriptor Record) and AEDR (Attribute Entry Descriptor Record) chains

"""
    load_attribute_entries(buffer::Vector{UInt8}, adr, RecordSizeType, cdf_encoding) -> Vector{AttributeEntry}

Load all attribute entries for a given attribute from its AEDRs.
"""
@inline function load_attribute_entries(buffer::Vector{UInt8}, adr, RecordSizeType, cdf_encoding)
    head = max(adr.AgrEDRhead, adr.AzEDRhead)
    offsets = get_offsets(buffer, head, RecordSizeType)
    return map(offsets) do offset
        load_aedr_data(buffer, offset, RecordSizeType, cdf_encoding)
    end
end

"""
    attrib(cdf::CDFDataset)

Load all attributes from the CDF file.
"""
function attrib(cdf::CDFDataset; predicate = is_global)
    RecordSizeType = recordsize_type(cdf)
    buffer = cdf.buffer
    cdf_encoding = cdf.cdr.encoding
    offsets = get_offsets(buffer, cdf.gdr.ADRhead, RecordSizeType)
    adrs = map(of -> ADR(buffer, of, RecordSizeType), offsets)
    adrs = filter(predicate, adrs)
    names = map(adr -> String(adr.Name), adrs)
    aedrs = map(adrs) do adr
        load_attribute_entries(buffer, adr, RecordSizeType, cdf_encoding)
    end
    return Dictionary(names, aedrs)
end

"""
    vattrib(cdf::CDFDataset, varnum::Integer) -> Dict{String, Any}

Get all variable attributes for a specific variable number.
"""
function vattrib(cdf::CDFDataset, varnum::Integer)
    RecordSizeType = recordsize_type(cdf)
    buffer = cdf.buffer
    cdf_encoding = cdf.cdr.encoding
    attributes = Dict{String, Union{String, Vector}}()
    offsets = get_offsets(buffer, cdf.gdr.ADRhead, RecordSizeType)
    for offset in offsets
        adr = ADR(buffer, offset, RecordSizeType)
        is_global(adr) && continue
        @assert min(adr.AgrEDRhead, adr.AzEDRhead) == 0
        head = max(adr.AgrEDRhead, adr.AzEDRhead)
        found = _search_aedr_entries(buffer, head, RecordSizeType, cdf_encoding, varnum)
        isnothing(found) && continue
        name = String(adr.Name)
        attributes[name] = found
    end
    return attributes
end

"""
    vattrib(cdf, varnum, name)

Optimized version that loads only the requested attribute for the given variable number.
Much faster than loading all attributes when only one is needed.
"""
function vattrib(cdf, varnum, name)
    RecordSizeType = recordsize_type(cdf)
    buffer = cdf.buffer
    cdf_encoding = cdf.cdr.encoding

    # Search for the specific attribute by name first
    offsets = get_offsets(buffer, cdf.gdr.ADRhead, RecordSizeType)
    for offset in offsets
        adr = ADR(buffer, offset, RecordSizeType)
        is_global(adr) && continue
        String(adr.Name) != name && continue
        @assert min(adr.AgrEDRhead, adr.AzEDRhead) == 0
        head = max(adr.AgrEDRhead, adr.AzEDRhead)
        return _search_aedr_entries(buffer, head, RecordSizeType, cdf_encoding, varnum)
    end
    return nothing
end

attrib(var::CDFVariable) = vattrib(var.parentdataset, var.vdr.num)

function _search_aedr_entries(source, aedr_head::Int64, RecordSizeType, cdf_encoding::Int32, target_varnum::Integer)
    aedr_head == 0 && return nothing
    offset = aedr_head
    while offset != 0
        num = read_be(source, offset + 29, Int32)
        if num == target_varnum
            return load_aedr_data(source, offset, RecordSizeType, cdf_encoding)
        end
        offset = read_be(source, offset + 13, Int64)
    end
    return nothing
end

"""
    attribnames(cdf::CDFDataset)

Return a list of attribute names in the CDF file.
"""
function attribnames(cdf::CDFDataset; filter = is_global)
    names = String[]
    buffer = cdf.buffer
    RecordSizeType = recordsize_type(cdf)
    offsets = get_offsets(buffer, cdf.gdr.ADRhead, RecordSizeType)
    sizehint!(names, length(offsets))
    for offset in offsets
        adr = ADR(buffer, offset, RecordSizeType)
        filter(adr) && push!(names, String(adr.Name))
    end
    return names
end
