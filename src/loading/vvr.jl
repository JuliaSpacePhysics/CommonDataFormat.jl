# Variable data loading functionality
# Handles VVR (Variable Value Record) parsing and data extraction

"""
    is_big_endian_encoding(encoding)

Determine if a CDF encoding uses big-endian byte order based on CDF specification encoding values.
"""
function is_big_endian_encoding(encoding)
    # Big-endian encodings: network(1), SUN(2), NeXT(12), PPC(9), SGi(5), IBMRS(7), ARM_BIG(19)
    return encoding in (1, 2, 5, 7, 9, 12, 19)
end

function VVR(io::IO, offset, RecordSizeType, data)
    seek(io, offset)
    header = Header(io, RecordSizeType)
    @assert header.record_type == 7 "Invalid VVR record type"
    return VVR(header, data)
end

function VVR(io::IO, offset, RecordSizeType)
    seek(io, offset)
    header = Header(io, RecordSizeType)
    @assert header.record_type == 7 "Invalid VVR record type"
    data_bytes = header.record_size - sizeof(RecordSizeType) - sizeof(Int32)
    data_size = div(data_bytes, sizeof(T))
    data = Vector{T}(undef, data_size)
    read!(io, data)
    return VVR(header, data)
end

"""
    load_vvr(io::IO, offset, RecordSizeType, T)

Load a Variable Value Record from the IO stream at the specified offset.
Applies byte swapping only when necessary based on CDF encoding.
"""
function load_vvr!(io::IO, data, offset, RecordSizeType, btye_swap::Bool)
    vvr = VVR(io, offset, RecordSizeType, data)
    # Read all available data in this VVR
    read!(io, data)
    btye_swap && map!(ntoh, data, data)
    return vvr
end

function Base.size(vdr::zVDR, gdr_r_dim_sizes)
    records = vdr.max_rec + 1
    dims = if vdr.z_num_dims > 0
        # Z-variable: use its own dimensions
        (vdr.z_dim_sizes..., records)
    else
        # R-variable: use GDR dimensions
        (gdr_r_dim_sizes..., records)
    end
    return Int.(dims)
end

"""
    load_variable_data(io::IO, vdr, RecordSizeType, gdr_r_dim_sizes::Vector{UInt32}, cdf_encoding) -> Array

Load actual data for a variable by following VXR->VVR chain.
"""
function load_variable_data(io::IO, vdr, RecordSizeType, gdr_r_dim_sizes::Vector{UInt32}, cdf_encoding)
    if vdr.vxr_head == 0 || vdr.max_rec < 0
        return nothing
    end
    # Load the VXR chain
    dims = Base.size(vdr, gdr_r_dim_sizes)
    T = julia_type(vdr.data_type)
    data = Vector{T}(undef, prod(dims))
    _load_variable_data!(data, io, vdr.vxr_head, RecordSizeType, cdf_encoding)
    return reshape_vdr_data(data, vdr, dims)
end

function _load_variable_data!(data::Array{T}, io::IO, offset, RecordSizeType, cdf_encoding) where {T}
    btye_swap = is_big_endian_encoding(cdf_encoding) && T <: Number
    while offset != 0
        vxr = VXR(io, offset, RecordSizeType)
        # Load data from each VVR pointed to by this VXR
        # At the lowest levels, the offsets in VXRs point to VVR
        for i in 1:vxr.n_used_entries
            first_rec = vxr.first[i]
            last_rec = vxr.last[i]
            vvr_offset = vxr.offset[i]
            # Check for invalid last_rec (0xffffffff indicates no valid record range)
            if last_rec == typemax(UInt32) || first_rec > last_rec
                # For sparse records with sentinel values, look for VVR immediately after VXR
                if vvr_offset == typemax(UInt64) || vvr_offset > 0x7fffffffffffffff
                    # Try to find VVR right after the current VXR record
                    vvr_offset = offset + vxr.header.record_size
                end
            end
            load_vvr!(io, data, vvr_offset, RecordSizeType, btye_swap)
        end
        offset = vxr.vxr_next
    end
    return data
end

"""
    reshape_vdr_data(raw_data, vdr::VDR, dims) -> Array

Convert raw byte data to a properly typed and shaped Julia array.
"""
function reshape_vdr_data(raw_data, vdr, dims)
    # Determine array dimensions

    # For string variables, add string length dimension
    if vdr.data_type in [51, 52] && vdr.num_elems > 1  # CDF_CHAR or CDF_UCHAR with length > 1
        push!(dims, Int(vdr.num_elems))
    end

    # Calculate expected number of elements
    expected_elements = prod(dims)
    actual_elements = length(raw_data)

    if actual_elements < expected_elements
        # Pad with zeros if needed
        padded_data = similar(raw_data, expected_elements)
        padded_data[1:length(raw_data)] .= raw_data
        raw_data = padded_data
    elseif actual_elements > expected_elements
        # Truncate if too much data
        raw_data = raw_data[1:expected_elements]
    end

    # Reshape to final dimensions
    return reshape(raw_data, dims...)
end
