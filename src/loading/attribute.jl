# Attribute loading functionality
# Handles loading of ADR (Attribute Descriptor Record) and AEDR (Attribute Entry Descriptor Record) chains

# Load all attribute entries for a given attribute from its AEDRs.
@inline function load_attribute_entries(buffer::Vector{UInt8}, adr, ::Type{RecordSizeType}, needs_byte_swap) where {RecordSizeType}
    head = max(adr.AgrEDRhead, adr.AzEDRhead)
    offsets = OffsetsIterator{RecordSizeType}(buffer, head)
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
    needs_byte_swap = is_big_endian_encoding(cdf)
    result = Dict{String, Vector}()
    for offset in OffsetsIterator(cdf)
        adr = ADR{RecordSizeType}(buffer, offset)
        predicate(adr) || continue
        result[String(adr.Name)] = load_attribute_entries(buffer, adr, RecordSizeType, needs_byte_swap)
    end
    return result
end

"""
    attrib(cdf::CDFDataset, attribute_name::String)

Retrieve all entries for a named attribute from the CDF file.
"""
function attrib(cdf::CDFDataset{FST}, name::String) where {FST}
    buffer = cdf.buffer
    needs_byte_swap = is_big_endian_encoding(cdf)
    offsets = OffsetsIterator(cdf)
    name_bytes = codeunits(name)
    for offset in offsets
        adr = ADR{FST}(buffer, offset)
        name_bytes == adr.Name && return load_attribute_entries(buffer, adr, FST, needs_byte_swap)
    end
    error("Attribute '$name' not found in CDF file")
end

# Lazy dict-like view of variable attributes; use Dict{String,Union{String,Vector}}(x) to materialize.
struct LazyVAttrib{CDF, N} <: AbstractDict{String, Union{String, Vector}}
    cdf::CDF
    varnum::N
end

function Base.iterate(la::LazyVAttrib, offset::Int = Int(la.cdf.gdr.ADRhead))
    offset == 0 && return nothing
    RecordSizeType = recordsize_type(la.cdf)
    buffer = la.cdf.buffer
    needs_byte_swap = is_big_endian_encoding(la.cdf)
    while offset != 0
        # cheap scope check before parsing the full ADR (avoids Name string allocation for globals)
        if is_global(buffer, offset, RecordSizeType)
            offset = Int(read_be(buffer, offset + 1 + sizeof(RecordSizeType) + 4, RecordSizeType))
            continue
        end
        adr = ADR{RecordSizeType}(buffer, offset)
        next_offset = Int(adr.ADRnext)
        for head in (adr.AgrEDRhead, adr.AzEDRhead)
            head == 0 && continue
            found = _search_aedr_entries(buffer, head, RecordSizeType, needs_byte_swap, la.varnum)
            isnothing(found) && continue
            name = String(adr.Name)
            return (name => _get_attributes(name, found, la.cdf), next_offset)
        end
        offset = next_offset
    end
    return nothing
end

Base.IteratorSize(::Type{<:LazyVAttrib}) = Base.SizeUnknown()
Base.length(la::LazyVAttrib) = count(_ -> true, la)

function Base.getindex(la::LazyVAttrib, name::AbstractString)
    at = get(la, name, nothing)
    isnothing(at) && throw(KeyError(name))
    return at
end

function Base.get(la::LazyVAttrib, name::AbstractString, default = nothing)
    cdf = la.cdf
    varnum = la.varnum
    RecordSizeType = recordsize_type(cdf)
    buffer = cdf.buffer
    name_bytes = codeunits(name)
    needs_byte_swap = is_big_endian_encoding(cdf)
    for offset in OffsetsIterator(cdf)
        is_global(buffer, offset, RecordSizeType) && continue
        adr = ADR{RecordSizeType}(buffer, offset)
        adr.Name != name_bytes && continue
        for head in (adr.AgrEDRhead, adr.AzEDRhead)
            head == 0 && continue
            found = _search_aedr_entries(buffer, head, RecordSizeType, needs_byte_swap, varnum)
            isnothing(found) && continue
            return _get_attributes(name, found, cdf)
        end
        return default
    end
    return default
end

Base.get(la::LazyVAttrib, name, default = nothing) = default

Base.haskey(la::LazyVAttrib, name::AbstractString) = !isnothing(get(la, name, nothing))
Base.haskey(la::LazyVAttrib, name) = false

# Handle pointers like LABL_PTR_1
# https://github.com/SciQLop/PyISTP/blob/0a565c39c73dd800934bc379dd7c2e00c28d23d0/pyistp/_impl.py#L16
function _get_attributes(name, value, cdf)
    if occursin("LABL_PTR", name)
        return cdf[value][:]
    end
    return value
end

@inline function _search_aedr_entries(source, aedr_head, ::Type{RecordSizeType}, needs_byte_swap, target_varnum) where {RecordSizeType}
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
function attribnames(cdf::CDFDataset{FST}; predicate = is_global) where {FST}
    names = String[]
    buffer = cdf.buffer
    for offset in OffsetsIterator(cdf)
        adr = ADR{FST}(buffer, offset)
        predicate(adr) && push!(names, String(adr.Name))
    end
    return names
end
