# GDR and VDR loading functionality
# Handles loading of Global Descriptor Record and Variable Descriptor Records

# Read variable name (null-terminated string, up to 256 chars)
function readname(io::IO)
    name_bytes = read(io, 256)
    null_pos = findfirst(==(0x00), name_bytes)
    return @views String(name_bytes[1:(isnothing(null_pos) ? 256 : null_pos - 1)])
end

"""
    VDR(io::IO, RecordSizeType) -> VDR

Load a Variable Descriptor Record from the IO stream at the specified offset.
"""
@inline function VDR(io::IO, RecordSizeType)
    header = Header(io, RecordSizeType)
    @assert header.record_type in (3, 8)

    # Read VDR fields (common to both r and z variables)
    vdr_next = Int64(read_be(io, RecordSizeType))
    data_type = DataType(read_uint32_be(io))
    max_rec = read_be(io, Int32)
    vxr_head = Int64(read_be(io, RecordSizeType))
    vxr_tail = Int64(read_be(io, RecordSizeType))

    flags, s_records, rfu_b, rfu_c, rfu_f, num_elems, num = read_be(io, 7, UInt32)
    cpr_or_spr_offset = UInt64(read_be(io, RecordSizeType))
    blocking_factor = read_uint32_be(io)
    name = readname(io)
    return VDR(
        header, vdr_next, data_type, max_rec, vxr_head, vxr_tail,
        flags, s_records, rfu_b, rfu_c, rfu_f, num_elems, num,
        cpr_or_spr_offset, blocking_factor, name
    )
end

function load_zVDR(io::IO, offset, RecordSizeType)
    vdr = VDR(io, offset, RecordSizeType)
    z_num_dims = read_uint32_be(io)

    # Read dimension sizes
    z_dim_sizes = Vector{UInt32}(undef, z_num_dims)
    dim_varys = Vector{UInt32}(undef, z_num_dims)
    for i in eachindex(z_dim_sizes)
        z_dim_sizes[i] = read_uint32_be(io)
    end
    # Read dimension variance flags
    for i in eachindex(dim_varys)
        dim_varys[i] = read_uint32_be(io)
    end

    return zVDR(vdr..., z_num_dims, z_dim_sizes, dim_varys)
end
