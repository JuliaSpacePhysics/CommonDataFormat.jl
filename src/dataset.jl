struct CDFDataset{CT, RS}
    filename::String
    cdr::CDR
    gdr::GDR
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

        RecordSizeType = is_cdf_v3(magic_bytes) ? Int64 : Int32
        compression_flag = read_be(buffer, 5, UInt32)
        compression = NoCompression
        if compression_flag != 0x0000FFFF
            buffer, compression = decompress_bytes(buffer, RecordSizeType)
        end
        # Parse CDF header
        cdr = CDR(buffer, 9, RecordSizeType)
        gdr = GDR(buffer, cdr.gdr_offset, RecordSizeType)
        return CDFDataset{compression, RecordSizeType}(filename, cdr, gdr, buffer)
    end
end

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
    for current_offset in (gdr.rVDRhead, gdr.zVDRhead)
        while current_offset != 0
            vdr = zVDR(buffer, current_offset, RecordSizeType)
            if String(vdr.name) == var_name
                return vdr
            end
            current_offset = vdr.vdr_next
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
    for current_offset in (gdr.rVDRhead, gdr.zVDRhead)
        while current_offset != 0
            vdr = VDR(source, current_offset, RecordSizeType)
            varnames[i] = String(vdr.name)
            i += 1
            current_offset = vdr.vdr_next
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
