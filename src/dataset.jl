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

        # Read compression info
        compression_bytes = read_be(buffer, 5, UInt32)
        compression = CompressionType(compression_bytes)
        RecordSizeType = is_cdf_v3(magic_bytes) ? UInt64 : UInt32
        # Parse CDF header
        cdr = CDR(buffer, 9, RecordSizeType)
        gdr = GDR(buffer, cdr.gdr_offset + 1, RecordSizeType)
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
        return open(cdf.filename, "r") do io
            return ADR(io, cdf.gdr.ADRhead, recordsize_type(cdf))
        end
    elseif name === :attrib
        return attrib(cdf)
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
    # 20% faster than using buffer `mmap`
    return open(filename(cdf), "r") do io
        RecordSizeType = recordsize_type(cdf)
        gdr = cdf.gdr
        vdr = find_vdr(cdf, var_name)
        isnothing(vdr) && throw(KeyError(var_name))
        data = load_variable_data(io, vdr, RecordSizeType, gdr.r_dim_sizes, cdf.cdr.encoding)
        return CDFVariable(var_name, data, vdr, cdf)
    end
end

Base.length(cdf::CDFDataset) = length(keys(cdf))

function Base.keys(cdf::CDFDataset)
    return open(cdf.filename, "r") do io
        RecordSizeType = recordsize_type(cdf)
        gdr = cdf.gdr
        varnames = Vector{String}(undef, gdr.NrVars + gdr.NzVars)
        i = 1
        for current_offset in (gdr.rVDRhead, gdr.zVDRhead)
            while current_offset != 0
                vdr = VDR(io, current_offset, RecordSizeType)
                varnames[i] = vdr.name
                i += 1
                current_offset = vdr.vdr_next
            end
        end
        return varnames
    end
end

Base.haskey(cdf::CDFDataset, var_name::String) = var_name in keys(cdf)
