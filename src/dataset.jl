struct CDFDataset{CT, FST}
    filename::String
    cdr::CDR{FST}
    gdr::GDR{FST}
    buffer::Vector{UInt8}
end

Base.parent(cdf::CDFDataset) = getfield(cdf, :buffer)
GDR(cdf::CDFDataset) = getfield(cdf, :gdr)
filename(cdf::CDFDataset) = getfield(cdf, :filename)
recordsize_type(::CDFDataset{CT, RS}) where {CT, RS} = RS

"""
    CDFDataset(filename)

Load a CDF file and return a CDFDataset object.

# Example
```julia
cdf = CDFDataset("data.cdf")
```
"""
function CDFDataset(filename)
    return open(filename, "r") do io
        buffer = Mmap.mmap(io)
        magic_bytes = read_be(buffer, 1, UInt32)
        @assert validate_cdf_magic(magic_bytes)

        FieldSizeType = is_cdf_v3(magic_bytes) ? Int64 : Int32
        compression = NoCompression
        if is_compressed(read_be(buffer, 5, UInt32))
            buffer, compression = decompress_bytes(buffer, FieldSizeType)
        end
        # Parse CDF header
        cdr = CDR(buffer, 8, FieldSizeType)
        gdr = GDR(buffer, Int(cdr.gdr_offset), FieldSizeType)
        return CDFDataset{compression, FieldSizeType}(filename, cdr, gdr, buffer)
    end
end

is_compressed(magic_numbers::UInt32) = magic_numbers != 0x0000FFFF

# Convenience accessors for the dataset with lazy loading
function Base.getproperty(cdf::CDFDataset{CT}, name::Symbol) where {CT}
    name in fieldnames(CDFDataset) && return getfield(cdf, name)
    if name === :version
        return version(cdf.cdr)
    elseif name === :majority
        return Majority(cdf.cdr)
    elseif name === :compression
        return CT
    elseif name === :adr
        return ADR(parent(cdf), GDR(cdf).ADRhead, recordsize_type(cdf))
    elseif name === :attrib
        return attrib(cdf)
    elseif name === :vattrib
        return attrib(cdf; predicate = !is_global)
    else
        throw(ArgumentError("Unknown property $name"))
    end
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
                return VDR(buffer, current_offset, RecordSizeType)
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

function Base.show(io::IO, ::MIME"text/plain", cdf::CDFDataset)
    println(io, typeof(cdf), ":", cdf.filename)
    println(io, "variables")
    for var in keys(cdf)
        println(io, "  $var")
    end
    println(io, cdf.cdr)
    return
end
