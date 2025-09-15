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
        # Parse CDF header to extract version, majority, and compression
        cdr = load_cdr(io, 8, RecordSizeType)
        gdr = load_gdr(io, cdr.gdr_offset, RecordSizeType)
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
                _vdr = load_zVDR(io, current_offset, RecordSizeType)
                if _vdr.name == var_name
                    vdr = _vdr
                    break
                end
                current_offset = _vdr.vdr_next
            end
            !isnothing(vdr) && break
        end

        isnothing(vdr) && throw(KeyError(var_name))

        # Determine dimensions based on variable type
        dimensions = if vdr.z_num_dims > 0
            # Z-variable - use its own dimensions
            collect(Int, vdr.z_dim_sizes)
        else
            # R-variable - use GDR dimensions (if any)
            if length(gdr.r_dim_sizes) > 0
                collect(Int, gdr.r_dim_sizes)
            else
                [1]  # Scalar
            end
        end

        # Calculate number of records
        num_records = vdr.max_rec >= 0 ? vdr.max_rec + 1 : 0

        data = load_variable_data(io, vdr, RecordSizeType, gdr.r_dim_sizes, cdf.cdr.encoding)

        # Create and return CDFVariable
        return CDFVariable(
            var_name,
            data,
            DataType(vdr.data_type),
            dimensions,
            num_records,
        )
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
                vdr = load_vdr(io, current_offset, RecordSizeType)
                varnames[i] = vdr.name
                i += 1
                current_offset = vdr.vdr_next
            end
        end
        return varnames
    end
end

Base.haskey(cdf::CDFDataset, var_name::String) = var_name in keys(cdf)
