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
        buffer, compression = decompress_bytes(buffer, FieldSizeType)
    end
    cdr = CDR(buffer, 8, FieldSizeType)
    gdr = GDR(buffer, Int(cdr.gdr_offset), FieldSizeType)
    return CDFDataset{FieldSizeType}(fname, cdr, gdr, buffer, compression)
end

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

function find_vdr(cdf::CDFDataset, var_name::String)
    gdr = GDR(cdf)
    RecordSizeType = recordsize_type(cdf)
    buffer = cdf.buffer
    var_name_bytes = codeunits(var_name)
    vdr_name_offset = 45 + 5 * sizeof(RecordSizeType)
    for current_offset in (gdr.rVDRhead, gdr.zVDRhead)
        while current_offset != 0
            if readname(buffer, current_offset + vdr_name_offset) == var_name_bytes
                record_type = read_be(buffer, current_offset + 1 + sizeof(RecordSizeType), Int32)
                @assert record_type in (8, 3)
                if record_type == 8
                    return VDR(buffer, current_offset, RecordSizeType)
                else
                    return rVDR(buffer, current_offset, gdr, RecordSizeType)
                end
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

Base.length(cdf::CDFDataset) = length(keys(cdf))

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

Base.haskey(cdf::CDFDataset, var_name::String) = var_name in keys(cdf)

Base.iterate(cdf::CDFDataset, state = 1) = state > length(cdf) ? nothing : (cdf[keys(cdf)[state]], state + 1)

function Base.show(io::IO, m::MIME"text/plain", cdf::CDFDataset)
    println(io, typeof(cdf))
    println(io, "path: ", cdf.filename)
    println(io, "variables:")
    for key in keys(cdf)
        var = cdf[key]
        print(io, "  ", key, " : ", size(var), " ")
        printstyled(io, variable_type(var); bold = true)
        print(io, " ", DataType(var.vdr.data_type))
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
