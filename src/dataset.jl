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
        return is_cdf_v3(magic_bytes) ? _load_dataset(fname, buffer, Int64) :
            _load_dataset(fname, buffer, Int32)
    finally
        close(io)
    end
end

function _load_dataset(fname, buffer, ::Type{FieldSizeType}) where {FieldSizeType}
    compression = NoCompression
    if is_compressed(read_be(buffer, 5, UInt32))
        mmapped = buffer
        buffer, compression = decompress_bytes(buffer, FieldSizeType)
        finalize(mmapped)
    end
    cdr = CDR(buffer, 8, FieldSizeType)
    gdr = GDR(buffer, Int(cdr.gdr_offset), FieldSizeType)
    return CDFDataset{FieldSizeType}(fname, cdr, gdr, buffer, compression)
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
    name === :adr && return ADR(parent(cdf), GDR(cdf).ADRhead, recordsize_type(cdf))
    name === :attrib && return attrib(cdf)
    name === :vattrib && return attrib(cdf; predicate = !is_global)
    throw(ArgumentError("Unknown property $name"))
end

# Load the (z or r) VDR at a known offset
function _vdr_at(cdf::CDFDataset, offset::Int)
    buffer = parent(cdf)
    RecordSizeType = recordsize_type(cdf)
    record_type = read_be(buffer, offset + 1 + sizeof(RecordSizeType), Int32)
    @assert record_type in (8, 3)
    return record_type == 8 ? VDR(buffer, offset, RecordSizeType) :
        rVDR(buffer, offset, GDR(cdf), RecordSizeType)
end

function find_vdr(cdf::CDFDataset, var_name::String)
    gdr = GDR(cdf)
    RecordSizeType = recordsize_type(cdf)
    buffer = cdf.buffer
    var_name_bytes = codeunits(var_name)
    vdr_name_offset = 45 + 5 * sizeof(RecordSizeType)
    for current_offset in (gdr.rVDRhead, gdr.zVDRhead)
        while current_offset != 0
            if readname(buffer, current_offset + vdr_name_offset) == var_name_bytes
                return _vdr_at(cdf, Int(current_offset))
            end
            current_offset = read_be(buffer, current_offset + 5 + sizeof(RecordSizeType), RecordSizeType)
        end
    end
    return nothing
end

# Direct variable access via indexing
function Base.getindex(cdf::CDFDataset, var_name::String)
    return variable(cdf, var_name)
end

Base.length(cdf::CDFDataset) = Int(GDR(cdf).NrVars + GDR(cdf).NzVars)

function Base.keys(cdf::CDFDataset)
    RecordSizeType = recordsize_type(cdf)
    gdr = cdf.gdr
    source = parent(cdf)
    varnames = Vector{String}(undef, gdr.NrVars + gdr.NzVars)
    i = 1
    vdr_name_offset = 45 + 5 * sizeof(RecordSizeType)
    for current_offset in (gdr.rVDRhead, gdr.zVDRhead)
        while current_offset != 0
            vdr_next = read_be(source, current_offset + 5 + sizeof(RecordSizeType), RecordSizeType)
            varnames[i] = String(readname(source, current_offset + vdr_name_offset))
            i += 1
            current_offset = vdr_next
        end
    end
    return varnames
end

Base.haskey(cdf::CDFDataset, var_name::String) = !isnothing(find_vdr(cdf, var_name))

# Walk the rVDR then zVDR chain directly; state = (offset, still_in_r_chain)
function Base.iterate(cdf::CDFDataset, state = (Int(GDR(cdf).rVDRhead), true))
    offset, in_rchain = state
    if offset == 0
        in_rchain || return nothing
        offset, in_rchain = Int(GDR(cdf).zVDRhead), false
        offset == 0 && return nothing
    end
    RecordSizeType = recordsize_type(cdf)
    buffer = parent(cdf)
    name = String(readname(buffer, offset + 45 + 5 * sizeof(RecordSizeType)))
    var = _variable(cdf, name, _vdr_at(cdf, offset))
    next_offset = Int(read_be(buffer, offset + 5 + sizeof(RecordSizeType), RecordSizeType))
    return (var, (next_offset, in_rchain))
end

function Base.show(io::IO, m::MIME"text/plain", cdf::CDFDataset)
    println(io, typeof(cdf))
    println(io, "path: ", cdf.filename)
    println(io, "variables:")
    for var in cdf
        print(io, "  ", var.name, " : ", size(var), " ")
        printstyled(io, variable_type(var); bold = true)
        print(io, " ", CDFDataType(var.vdr.data_type))
        !isempty(var) && print(io, " [", var[1], " … ", var[end], "]")
        println(io)
    end
    println(io, cdf.cdr)
    print(io, "attributes: ")
    show(io, m, cdf.attrib)
    return
end

OffsetsIterator(cdf::CDFDataset) =
    OffsetsIterator{recordsize_type(cdf)}(cdf.buffer, cdf.gdr.ADRhead)
