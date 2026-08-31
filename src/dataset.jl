struct CDFDataset{FST}
    filename::String
    cdr::CDR{FST}
    gdr::GDR{FST}
    buffer::Vector{UInt8}
    compression::CompressionType
end

Base.parent(cdf::CDFDataset) = getfield(cdf, :buffer)
GDR(cdf::CDFDataset) = getfield(cdf, :gdr)
filename(cdf::CDFDataset) = getfield(cdf, :filename)
recordsize_type(::CDFDataset{RS}) where {RS} = RS

"""
    CDFDataset(filename)

Load a CDF file and return a CDFDataset object.

# Example
```julia
cdf = CDFDataset("data.cdf")
```
"""
function CDFDataset(filename)
    fname = String(filename)
    # `open(f, name, mode) do` form: routes through varargs splatting (`_apply_iterate`) which `juliac --trim` can't resolve.
    io = open(fname, "r")
    try
        buffer = Mmap.mmap(io)
        magic_bytes = read_be(buffer, 1, UInt32)
        @assert validate_cdf_magic(magic_bytes)
        return is_cdf_v3(magic_bytes) ? CDFDataset{Int64}(fname, buffer) :
            CDFDataset{Int32}(fname, buffer)
    finally
        close(io)
    end
end

function CDFDataset{FST}(fname, buffer) where {FST}
    compression = NoCompression
    if is_compressed(read_be(buffer, 5, UInt32))
        mmapped = buffer
        buffer, compression = decompress_bytes(buffer, FST)
        finalize(mmapped)
    end
    cdr = CDR{FST}(buffer, 8)
    gdr = GDR{FST}(buffer, Int(cdr.gdr_offset))
    return CDFDataset{FST}(fname, cdr, gdr, buffer, compression)
end

Base.close(cdf::CDFDataset) = (finalize(parent(cdf)); nothing)

is_big_endian_encoding(cdf::CDFDataset) = is_big_endian_encoding(cdf.cdr.encoding)

is_compressed(magic_numbers::UInt32) = magic_numbers != 0x0000FFFF
majority(cdf::CDFDataset) = majority(cdf.cdr)

# Convenience accessors for the dataset with lazy loading
@inline function Base.getproperty(cdf::CDFDataset, name::Symbol)
    # Real fields FIRST so internal accesses (`cdf.cdr`, `cdf.gdr`, …) short-circuit and
    # never traverse the lazy `attrib` branches below.
    name in fieldnames(CDFDataset) && return getfield(cdf, name)
    name === :version && return version(getfield(cdf, :cdr))
    name === :majority && return majority(cdf)
    name === :adr && return ADR{recordsize_type(cdf)}(parent(cdf), GDR(cdf).ADRhead)
    name === :attrib && return attrib(cdf)
    name === :vattrib && return attrib(cdf; predicate = !is_global)
    throw(ArgumentError("Unknown property $name"))
end

# Load the (z or r) VDR at a known offset
function _vdr_at(cdf::CDFDataset{FST}, offset::Int) where {FST}
    buffer = parent(cdf)
    record_type = read_be(buffer, offset + 1 + sizeof(FST), Int32)
    @assert record_type in (8, 3)
    return record_type == 8 ? VDR{FST}(buffer, offset) :
        rVDR{FST}(buffer, offset)
end

# Name is the first variable-width field of a VDR; everything before it is fixed size.
vdr_name(buffer, offset, ::Type{FST}) where {FST} = readname(buffer, offset + 45 + 5 * sizeof(FST))
# r-variables are chained first, then z-variables
vdr_heads(cdf::CDFDataset) = (GDR(cdf).rVDRhead, GDR(cdf).zVDRhead)

function find_vdr(cdf::CDFDataset{FST}, var_name::String) where {FST}
    buffer = parent(cdf)
    var_name_bytes = codeunits(var_name)
    for head in vdr_heads(cdf), offset in OffsetsIterator{FST}(buffer, head)
        vdr_name(buffer, offset, FST) == var_name_bytes && return _vdr_at(cdf, offset)
    end
    return nothing
end

function Base.getindex(cdf::CDFDataset, name::String)
    vdr = find_vdr(cdf, name)
    isnothing(vdr) && throw(KeyError(name))
    return _variable(cdf, name, vdr)
end

# Branch over dimension count so each leaf builds dims tuple at compile time statically
function _variable(cdf, name, vdr)
    M = num_record_dims(vdr, cdf)
    return Base.Cartesian.@nif 12 d -> (M == d - 1) d -> (
        d == 12 ? throw(ArgumentError("variable has $M dimensions; the CDF format allows at most 10")) :
        _variable(cdf, name, vdr, Val(d - 1))
    )
end

function _variable(cdf, name, vdr, ::Val{M}) where {M}
    dims = (map(Int, record_sizes(vdr, cdf, Val(M)))..., Int(vdr.max_rec) + 1)
    code = Int(vdr.data_type)
    if code == CDF_CHAR || code == CDF_UCHAR # eltype depends on runtime num_elems
        T = StaticString{Int(vdr.num_elems),UInt8}
        return CDFVariable{T,M + 1,typeof(vdr),typeof(cdf)}(name, vdr, cdf, dims)
    end
    # Branch to static constructor per element type
    return Base.Cartesian.@nif(
        16,
        d -> code == CODE_TYPE_PAIRS[d][1],
        d -> _construct(cdf, name, vdr, dims, CODE_TYPE_PAIRS[d][2]),
        d -> throw(ArgumentError("unsupported CDF data type $code"))
    )
end

@inline _construct(cdf, name, vdr, dims::NTuple{N,Int}, ::Type{T}) where {N,T} =
    CDFVariable{T,N,typeof(vdr),typeof(cdf)}(name, vdr, cdf, dims)

Base.length(cdf::CDFDataset) = Int(GDR(cdf).NrVars + GDR(cdf).NzVars)

function Base.keys(cdf::CDFDataset{FST}) where {FST}
    buffer = parent(cdf)
    varnames = Vector{String}(undef, length(cdf))
    i = 1
    for head in vdr_heads(cdf), offset in OffsetsIterator{FST}(buffer, head)
        varnames[i] = String(vdr_name(buffer, offset, FST))
        i += 1
    end
    return varnames
end

Base.haskey(cdf::CDFDataset, var_name::String) = !isnothing(find_vdr(cdf, var_name))

# Walk the rVDR then zVDR chain directly; state = (offset, still_in_r_chain)
function Base.iterate(cdf::CDFDataset{FST}, state = (Int(GDR(cdf).rVDRhead), true)) where {FST}
    offset, in_rchain = state
    if offset == 0
        in_rchain || return nothing
        offset, in_rchain = Int(GDR(cdf).zVDRhead), false
        offset == 0 && return nothing
    end
    buffer = parent(cdf)
    var = _variable(cdf, String(vdr_name(buffer, offset, FST)), _vdr_at(cdf, offset))
    return (var, (next_record_offset(buffer, offset, FST), in_rchain))
end

function Base.show(io::IO, m::MIME"text/plain", cdf::CDFDataset)
    println(io, typeof(cdf))
    println(io, "path: ", cdf.filename)
    println(io, "variables:")
    for var in cdf
        print(io, "  ", var.name, " : ", size(var), " ")
        printstyled(io, variable_type(var); bold = true)
        print(io, " ", CDFDataType(var.vdr.data_type))
        !isempty(var) && print(io, " [", first(_record(var, 1)), " … ", last(_record(var, size(var)[end])), "]")
        println(io)
    end
    println(io, cdf.cdr)
    print(io, "attributes: ")
    show(io, m, cdf.attrib)
    return
end

OffsetsIterator(cdf::CDFDataset) =
    OffsetsIterator{recordsize_type(cdf)}(cdf.buffer, cdf.gdr.ADRhead)
