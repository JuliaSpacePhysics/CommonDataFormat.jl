struct CDFDataset{CT, RS}
    filename::String
    cdr::CDR
    gdr::GDR
end

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
        magic_bytes = read_be(io, UInt32)
        @assert validate_cdf_magic(magic_bytes)

        # Read compression info
        compression_bytes = read_be(io, UInt32)
        compression = CompressionType(compression_bytes)
        RecordSizeType = is_cdf_v3(magic_bytes) ? UInt64 : UInt32
        # Parse CDF header
        cdr = CDR(io, 8, RecordSizeType)
        gdr = GDR(io, cdr.gdr_offset, RecordSizeType)
        return CDFDataset{compression, RecordSizeType}(filename, cdr, gdr)
    end
end

# Convenience accessors for the dataset with lazy loading
function Base.getproperty(cdf::CDFDataset{CT}, name::Symbol) where {CT}
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
    else
        return getfield(cdf, name)
    end
end

# Direct variable access via indexing
function Base.getindex(cdf::CDFDataset, var_name::String)
    return open(cdf.filename, "r") do io
        RecordSizeType = recordsize_type(cdf)
        gdr = cdf.gdr

        vdr = nothing
        for current_offset in (gdr.rVDRhead, gdr.zVDRhead)
            while current_offset != 0
                _vdr = zVDR(io, current_offset, RecordSizeType)
                if _vdr.name == var_name
                    vdr = _vdr
                    break
                end
                current_offset = _vdr.vdr_next
            end
            !isnothing(vdr) && break
        end

        isnothing(vdr) && throw(KeyError(var_name))

        # Calculate number of records
        data = load_variable_data(io, vdr, RecordSizeType, gdr.r_dim_sizes, cdf.cdr.encoding)

        # Create and return CDFVariable
        return CDFVariable(var_name, data, vdr)
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

# CommonDataModel.jl Interface
function attribnames(cdf::CDFDataset)
    return open(cdf.filename, "r") do io
        gdr = cdf.gdr
        adr = ADR(io, gdr.ADRhead, recordsize_type(cdf))
        return adr.attrib_names
    end
end