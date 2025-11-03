# Attribute loading functionality
# Handles loading of ADR (Attribute Descriptor Record) and AEDR (Attribute Entry Descriptor Record) chains

"""
    load_attribute_entries(buffer::Vector{UInt8}, adr, RecordSizeType, cdf_encoding) -> Vector{AttributeEntry}

Load all attribute entries for a given attribute from its AEDRs.
"""
@inline function load_attribute_entries(buffer::Vector{UInt8}, adr, RecordSizeType, cdf_encoding)
    head = max(adr.AgrEDRhead, adr.AzEDRhead)
    offsets = get_offsets(buffer, head, RecordSizeType)
    needs_byte_swap = is_big_endian_encoding(cdf_encoding)
    return map(offsets) do offset
        load_aedr_data(buffer, offset, RecordSizeType, needs_byte_swap)
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
    adrs = filter!(predicate, adrs)
    names = map(adr -> String(adr.Name), adrs)
    aedrs = map(adrs) do adr
        load_attribute_entries(buffer, adr, RecordSizeType, cdf_encoding)
    end
    return Dictionary(names, aedrs)
end

"""
    attrib(cdf::CDFDataset, attribute_name::String)

Retrieve all entries for a named attribute from the CDF file.
"""
function attrib(cdf::CDFDataset, name::String)
    RecordSizeType = recordsize_type(cdf)
    buffer = cdf.buffer
    cdf_encoding = cdf.cdr.encoding
    offsets = get_offsets_lazy(buffer, cdf.gdr.ADRhead, RecordSizeType)
    for offset in offsets
        adr = ADR(buffer, offset, RecordSizeType)
        name == String(adr.Name) && return load_attribute_entries(buffer, adr, RecordSizeType, cdf_encoding)
    end
    error("Attribute '$name' not found in CDF file")
end

"""
    vattrib(cdf::CDFDataset, varnum::Integer)

Get all variable attributes for a specific variable number.
"""
function vattrib(cdf::CDFDataset, varnum::Integer)
    RecordSizeType = recordsize_type(cdf)
    buffer = cdf.buffer
    cdf_encoding = cdf.cdr.encoding
    attributes = Dict{String, Union{String, Vector}}()
    offsets = get_offsets_lazy(buffer, cdf.gdr.ADRhead, RecordSizeType)
    needs_byte_swap = is_big_endian_encoding(cdf_encoding)
    for offset in offsets
        is_global(buffer, offset, RecordSizeType) && continue
        adr = ADR(buffer, offset, RecordSizeType)
        for head in (adr.AgrEDRhead, adr.AzEDRhead)
            head == 0 && continue
            found = _search_aedr_entries(buffer, head, RecordSizeType, needs_byte_swap, varnum)
            isnothing(found) && continue
            name = String(adr.Name)
            attributes[name] = _get_attributes(name, found, cdf)
            break
        end
    end
    return attributes
end

# Handle pointers like LABL_PTR_1
# https://github.com/SciQLop/PyISTP/blob/0a565c39c73dd800934bc379dd7c2e00c28d23d0/pyistp/_impl.py#L16
function _get_attributes(name, value, cdf)
    if occursin("LABL_PTR", name)
        return cdf[value][:]
    end
    return value
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
    offsets = get_offsets_lazy(buffer, cdf.gdr.ADRhead, RecordSizeType)
    name_bytes = codeunits(name)
    needs_byte_swap = is_big_endian_encoding(cdf_encoding)
    for offset in offsets
        is_global(buffer, offset, RecordSizeType) && continue
        adr = ADR(buffer, offset, RecordSizeType)
        adr.Name != name_bytes && continue
        for head in (adr.AgrEDRhead, adr.AzEDRhead)
            head == 0 && continue
            found = _search_aedr_entries(buffer, head, RecordSizeType, needs_byte_swap, varnum)
            isnothing(found) && continue
            return _get_attributes(name, found, cdf)
        end
        return nothing
    end
    return nothing
end

@inline function _search_aedr_entries(source, aedr_head, RecordSizeType, needs_byte_swap, target_varnum)
    aedr_head == 0 && return nothing
    offset = Int(aedr_head)
    _num_offset = 13 + 2 * sizeof(RecordSizeType)
    _next_offset = 5 + sizeof(RecordSizeType)
    while offset != 0
        num = read_be(source, offset + _num_offset, Int32)
        if num == target_varnum
            return load_aedr_data(source, offset, RecordSizeType, needs_byte_swap)
        end
        offset = Int(read_be(source, offset + _next_offset, RecordSizeType))
    end
    return nothing
end

"""
    attribnames(cdf::CDFDataset)

Return a list of attribute names in the CDF file.
"""
function attribnames(cdf::CDFDataset; predicate = is_global)
    names = String[]
    buffer = cdf.buffer
    RecordSizeType = recordsize_type(cdf)
    offsets = get_offsets_lazy(buffer, cdf.gdr.ADRhead, RecordSizeType)
    for offset in offsets
        adr = ADR(buffer, offset, RecordSizeType)
        predicate(adr) && push!(names, String(adr.Name))
    end
    return names
end
