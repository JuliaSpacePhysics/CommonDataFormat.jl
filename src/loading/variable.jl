function variable(cdf::CDFDataset, name)
    source = parent(cdf)
    RecordSizeType = recordsize_type(cdf)
    gdr = cdf.gdr
    vdr = find_vdr(cdf, name)
    isnothing(vdr) && throw(KeyError(name))
    data_type = vdr.data_type
    T = data_type in [51, 52] ? StaticString{Int(vdr.num_elems)} : julia_type(data_type)
    dims = Base.size(vdr, gdr.r_dim_sizes)
    btye_swap = is_big_endian_encoding(cdf.cdr.encoding)
    data = load_variable_data(source, vdr.vxr_head, T, dims, RecordSizeType, btye_swap)
    return CDFVariable(name, data, vdr, cdf)
end


"""
    load_variable_data(source, offset, ::Type{T}, dims, RecordSizeType, btye_swap::Bool)

Load actual data for a variable by following VXR->VVR chain.
"""
function load_variable_data(source, offset, ::Type{T}, dims, RecordSizeType, btye_swap::Bool) where {T}
    # Load the VXR chain
    data = Vector{T}(undef, prod(dims))
    while offset != 0
        vxr = VXR(source, offset, RecordSizeType)
        # Load data from each VVR pointed to by this VXR
        # At the lowest levels, the offsets in VXRs point to VVR
        for i in eachindex(vxr.first, vxr.last, vxr.offset)
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
            load_vvr_data!(data, source, vvr_offset, RecordSizeType, btye_swap)
        end
        offset = vxr.vxr_next
    end
    return reshape(data, dims)
end
