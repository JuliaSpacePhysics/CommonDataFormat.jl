# Load all attribute entries for a given attribute from its AEDRs: rEntries, then zEntries.
# Writers may chain AEDRs out of entry-number order, so each chain is ordered by entry number.
@inline function load_attribute_entries(buffer::Vector{UInt8}, adr, ::Type{RecordSizeType}, needs_byte_swap) where {RecordSizeType}
    function load(head)
        offsets = OffsetsIterator{RecordSizeType}(buffer, head)
        entries = map(offset -> load_aedr_data(buffer, offset, RecordSizeType, needs_byte_swap), offsets)
        nums = Iterators.map(offset -> aedr_num(buffer, offset, RecordSizeType), offsets)
        length(entries) < 2 || issorted(nums) || permute!(entries, sortperm(collect(nums)))
        return entries
    end
    adr.AzEDRhead == 0 && return load(adr.AgrEDRhead)
    adr.AgrEDRhead == 0 && return load(adr.AzEDRhead)
    return vcat(load(adr.AgrEDRhead), load(adr.AzEDRhead))
end

"""
    attrib(cdf::CDFDataset)

Global attributes, each read on access.
"""
attrib(cdf::CDFDataset) = LazyAttrib(cdf)
attrib(cdf::CDFDataset, name::String) = attrib(cdf)[name]

# Lazy dict-like view of the global attributes (`varnum === nothing`) or of variable `varnum`'s.
# r- and z-variables are numbered independently, so `zvar` selects the entry chain `varnum` indexes.
struct LazyAttrib{CDF, N, V} <: AbstractDict{String, V}
    cdf::CDF
    varnum::N
    zvar::Bool
end

LazyAttrib(cdf) = LazyAttrib{typeof(cdf), Nothing, Vector}(cdf, nothing, false)
LazyAttrib(cdf, varnum::Integer, zvar::Bool) = LazyAttrib{typeof(cdf), typeof(varnum), Union{String, Vector}}(cdf, varnum, zvar)

@inline _in_scope(la::LazyAttrib, buffer, offset, ::Type{RecordSizeType}) where {RecordSizeType} = is_global(buffer, offset, RecordSizeType) == isnothing(la.varnum)

# Offset of variable `varnum`'s entry for this attribute, if it has one.
function _entry_offset(buffer, adr, varnum, zvar, ::Type{RecordSizeType}) where {RecordSizeType}
    for offset in OffsetsIterator{RecordSizeType}(buffer, zvar ? adr.AzEDRhead : adr.AgrEDRhead)
        aedr_num(buffer, offset, RecordSizeType) == varnum && return offset
    end
    return nothing
end

# A global attribute holds all its entries; a variable attribute may have no entry for `varnum`.
@inline function _entries(la::LazyAttrib, buffer, adr, ::Type{RecordSizeType}, needs_byte_swap) where {RecordSizeType}
    isnothing(la.varnum) && return load_attribute_entries(buffer, adr, RecordSizeType, needs_byte_swap)
    offset = _entry_offset(buffer, adr, la.varnum, la.zvar, RecordSizeType)
    return isnothing(offset) ? nothing : load_aedr_data(buffer, offset, RecordSizeType, needs_byte_swap)
end

# The variable's FILLVAL as stored, if its type has the size of the variable's and it fills one `esz`-byte element.
function fillval_bytes(vdr, cdf::CDFDataset{FST}, esz) where {FST}
    buffer = parent(cdf)
    for adr_offset in OffsetsIterator(cdf)
        !is_global(buffer, adr_offset, FST) && name_equals(buffer, _adr_name_pos(adr_offset, FST), "FILLVAL", FST) || continue
        offset = _entry_offset(buffer, ADR{FST}(buffer, adr_offset), vdr.num, vdr.zvar, FST)
        isnothing(offset) && return nothing
        datatype, NumElems, pos = aedr_value(buffer, offset, FST)
        type_size(datatype) == type_size(vdr.data_type) && NumElems * type_size(datatype) == esz || return nothing
        return buffer[pos:(pos + esz - 1)]
    end
    return nothing
end

# First in-scope ADR from `offset` (named `name`, if given) with entries or nothing
@inline function _find_adr(la::LazyAttrib, offset::Int, name = nothing)
    RecordSizeType = recordsize_type(la.cdf)
    buffer = la.cdf.buffer
    needs_byte_swap = is_big_endian_encoding(la.cdf)
    while offset != 0
        if _in_scope(la, buffer, offset, RecordSizeType) &&
                (isnothing(name) || name_equals(buffer, _adr_name_pos(offset, RecordSizeType), name, RecordSizeType))
            adr = ADR{RecordSizeType}(buffer, offset)
            found = _entries(la, buffer, adr, RecordSizeType, needs_byte_swap)
            isnothing(found) || return (adr, found)
            isnothing(name) || return nothing # names are unique
        end
        offset = next_record_offset(buffer, offset, RecordSizeType)
    end
    return nothing
end

function Base.iterate(la::LazyAttrib, offset::Int = Int(la.cdf.gdr.ADRhead))
    r = _find_adr(la, offset)
    isnothing(r) && return nothing
    adr, found = r
    return (Pair{String, valtype(la)}(adr_name(la.cdf.buffer, adr), found), Int(adr.ADRnext))
end

Base.IteratorSize(::Type{<:LazyAttrib{<:Any, <:Integer}}) = Base.SizeUnknown()
function Base.length(la::LazyAttrib)
    isnothing(la.varnum) || return count(Returns(true), la)
    buffer, RecordSizeType = la.cdf.buffer, recordsize_type(la.cdf)
    return count(offset -> is_global(buffer, offset, RecordSizeType), OffsetsIterator(la.cdf))
end

function Base.getindex(la::LazyAttrib, name::AbstractString)
    at = get(la, name, nothing)
    isnothing(at) && throw(KeyError(name))
    return at
end

function Base.get(la::LazyAttrib, name::AbstractString, default = nothing)
    r = _find_adr(la, Int(la.cdf.gdr.ADRhead), String(name))
    return isnothing(r) ? default : r[2]
end

Base.get(la::LazyAttrib, name, default = nothing) = default

Base.haskey(la::LazyAttrib, name::AbstractString) = !isnothing(get(la, name, nothing))
Base.haskey(la::LazyAttrib, name) = false

function attribnames(cdf::CDFDataset{FST}; predicate = is_global) where {FST}
    names = String[]
    buffer = cdf.buffer
    for offset in OffsetsIterator(cdf)
        adr = ADR{FST}(buffer, offset)
        predicate(adr) && push!(names, adr_name(buffer, adr))
    end
    return names
end
