# VDR loading functionality

"""
Variable Descriptor Record (VDR) - describes a single variable
Can be either r-variable (record variant) or z-variable (zero variant)

See also: [zVDR](@ref)
"""
struct VDR{S} <: Record
    header::Header
    vdr_next::Int64     # Offset to next VDR in chain
    data_type::Int32    # CDF data type
    max_rec::Int32       # Maximum record number (-1 if none)
    vxr_head::Int64     # Variable indeX Record head
    vxr_tail::Int64     # Variable indeX Record tail
    flags::Int32        # Variable flags
    s_records::Int32    # Sparse records flag
    rfu_b::Int32        # Reserved field B
    rfu_c::Int32        # Reserved field C
    rfu_f::Int32        # Reserved field F
    num_elems::Int32    # Number of elements (for strings)
    num::Int32          # Variable number
    cpr_or_spr_offset::UInt64  # Compression/Sparseness Parameters Record offset
    blocking_factor::Int32
    name::S         # Variable name
end

"""
z-Variable Descriptor Record (zVDR)
"""
struct zVDR{S}
    header::Header
    vdr_next::Int64     # Offset to next VDR in chain
    data_type::Int32    # CDF data type
    max_rec::Int32       # Maximum record number (-1 if none)
    vxr_head::Int64     # Variable indeX Record head
    vxr_tail::Int64     # Variable indeX Record tail
    flags::Int32        # Variable flags
    s_records::Int32    # Sparse records flag
    rfu_b::Int32        # Reserved field B
    rfu_c::Int32        # Reserved field C
    rfu_f::Int32        # Reserved field F
    num_elems::Int32    # Number of elements (for strings)
    num::Int32          # Variable number
    cpr_or_spr_offset::UInt64  # Compression/Sparseness Parameters Record offset
    blocking_factor::Int32
    name::S         # Variable name
    z_num_dims::Int32   # Number of dimensions (z-variables only)
    z_dim_sizes::Tuple{Vararg{Int32}}  # Dimension sizes (z-variables only)
    dim_varys::Tuple{Vararg{Int32}}    # Dimension variance flags
end

"""
    VDR(io::IO, RecordSizeType) -> VDR

Load a Variable Descriptor Record from the IO stream at the specified offset.
"""
@inline function VDR(buffer::Vector{UInt8}, offset, RecordSizeType)
    pos = offset + 1
    header = Header(buffer, pos, RecordSizeType)
    @assert header.record_type in (3, 8)
    pos += sizeof(RecordSizeType) + 4

    # Read VDR fields (common to both r and z variables)
    fields, pos = @read_be_fields(buffer, pos, fieldtypes(VDR)[2:(end - 1)]...)
    name = readname(buffer, pos)
    return VDR(header, fields..., name)
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

function Base.size(vdr::zVDR)
    records = vdr.max_rec + 1
    dims = (vdr.z_dim_sizes..., records)
    return Int.(dims)
end
