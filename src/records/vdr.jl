# VDR loading functionality

"""
Variable Descriptor Record (VDR) - describes a single variable
Can be either r-variable (record variant) or z-variable (zero variant)

See also: [zVDR](@ref)
"""
struct VDR{DT, S} <: Record
    header::Header
    vdr_next::Int64     # Offset to next VDR in chain
    data_type::DT    # CDF data type
    max_rec::Int32       # Maximum record number (-1 if none)
    vxr_head::Int64     # Variable indeX Record head
    vxr_tail::Int64     # Variable indeX Record tail
    flags::UInt32        # Variable flags
    s_records::UInt32    # Sparse records flag
    rfu_b::UInt32        # Reserved field B
    rfu_c::UInt32        # Reserved field C
    rfu_f::UInt32        # Reserved field F
    num_elems::UInt32    # Number of elements (for strings)
    num::UInt32          # Variable number
    cpr_or_spr_offset::UInt64  # Compression/Sparseness Parameters Record offset
    blocking_factor::UInt32
    name::S         # Variable name
end

"""
z-Variable Descriptor Record (zVDR)
"""
struct zVDR{DT, S}
    header::Header
    vdr_next::Int64     # Offset to next VDR in chain
    data_type::DT    # CDF data type
    max_rec::Int32       # Maximum record number (-1 if none)
    vxr_head::Int64     # Variable indeX Record head
    vxr_tail::Int64     # Variable indeX Record tail
    flags::UInt32        # Variable flags
    s_records::UInt32    # Sparse records flag
    rfu_b::UInt32        # Reserved field B
    rfu_c::UInt32        # Reserved field C
    rfu_f::UInt32        # Reserved field F
    num_elems::UInt32    # Number of elements (for strings)
    num::UInt32          # Variable number
    cpr_or_spr_offset::UInt64  # Compression/Sparseness Parameters Record offset
    blocking_factor::UInt32
    name::S         # Variable name
    z_num_dims::Int32   # Number of dimensions (z-variables only)
    z_dim_sizes::Tuple{Vararg{Int32}}  # Dimension sizes (z-variables only)
    dim_varys::Tuple{Vararg{Int32}}    # Dimension variance flags
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

    fields = read_be(io, 7, UInt32)
    cpr_or_spr_offset = UInt64(read_be(io, RecordSizeType))
    blocking_factor = read_uint32_be(io)
    name = readname(io)
    return VDR(
        header, vdr_next, data_type, max_rec, vxr_head, vxr_tail,
        fields..., cpr_or_spr_offset, blocking_factor, name
    )
end

@inline function VDR(buffer::Vector{UInt8}, offset, RecordSizeType)
    pos = offset + 1
    header = Header(buffer, pos, RecordSizeType)
    @assert header.record_type in (3, 8)
    pos += sizeof(RecordSizeType) + 4

    # Read VDR fields (common to both r and z variables)
    vdr_next, pos = read_be_i(buffer, pos, Int64)
    data_type, pos = read_be_i(buffer, pos, UInt32)
    max_rec, pos = read_be_i(buffer, pos, Int32)
    vxr_head, pos = read_be_i(buffer, pos, Int64)
    vxr_tail, pos = read_be_i(buffer, pos, Int64)
    fields, pos = read_be_i(buffer, pos, 7, UInt32)
    cpr_or_spr_offset, pos = read_be_i(buffer, pos, UInt64)
    blocking_factor, pos = read_be_i(buffer, pos, UInt32)
    name = readname(buffer, pos)
    return VDR(
        header, vdr_next, data_type, max_rec, vxr_head, vxr_tail,
        fields..., cpr_or_spr_offset, blocking_factor, name
    )
end


@inline function zVDR(io::IO, args...)
    vdr = VDR(io, args...)
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

@inline function zVDR(buf::Vector{UInt8}, offset, RecordSizeType)
    vdr = VDR(buf, offset, RecordSizeType)
    pos = offset + 340 + 1
    z_num_dims, pos = read_be_i(buf, pos, Int32)

    # Read dimension sizes
    z_dim_sizes, pos = read_be_i(buf, pos, z_num_dims, Int32)
    dim_varys = read_be(buf, pos, z_num_dims, Int32)
    return zVDR(vdr..., z_num_dims, z_dim_sizes, dim_varys)
end
