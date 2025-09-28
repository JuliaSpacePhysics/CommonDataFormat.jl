# VDR loading functionality

"""
Variable Descriptor Record (VDR) - describes a single variable
Can be either r-variable (record variant) or z-variable (zero variant)
"""
struct VDR{FST} <: Record
    # header::Header
    vdr_next::FST     # Offset to next VDR in chain
    data_type::Int32    # CDF data type
    max_rec::Int32       # Maximum record number (-1 if none)
    vxr_head::FST     # Variable indeX Record head
    vxr_tail::FST     # Variable indeX Record tail
    flags::Int32        # Variable flags
    s_records::Int32    # Sparse records flag
    rfu_b::RInt32        # Reserved field B
    rfu_c::RInt32        # Reserved field C
    rfu_f::RInt32        # Reserved field F
    num_elems::Int32    # Number of elements (for strings)
    num::Int32          # Variable number
    cpr_or_spr_offset::FST  # Compression/Sparseness Parameters Record offset
    # blocking_factor::Int32
    # name::S         # Variable name
    z_num_dims::Int32   # Number of dimensions (z-variables only)
    buffer::Vector{UInt8}
    pos::Int
    # z_dim_sizes::Tuple{Vararg{Int32}}  # Dimension sizes (z-variables only)
    # dim_varys::Tuple{Vararg{Int32}}    # Dimension variance flags
end

"""
    VDR(io::IO, FieldSizeT)

Load a Variable Descriptor Record from the IO stream at the specified offset.
"""
@inline function VDR(buffer::Vector{UInt8}, offset, ::Type{FieldSizeT}) where {FieldSizeT}
    pos = check_record_type((3, 8), buffer, offset, FieldSizeT)
    fields, pos = read_be_fields(buffer, pos, VDR{FieldSizeT}, Val(1:13))
    # name = readname(buffer, pos)

    pos = FieldSizeT == Int64 ? offset + 340 + 1 : offset + 128 + 1
    z_num_dims, pos = read_be_i(buffer, pos, Int32)
    return VDR(fields..., z_num_dims, buffer, pos)
end

@inline function record_sizes(vdr::VDR)
    return read_be(vdr.buffer, vdr.pos, vdr.z_num_dims, Int32)
end

function Base.size(vdr::VDR)
    records = vdr.max_rec + 1
    dims = (record_sizes(vdr)..., records)
    return Int.(dims)
end

function Base.show(io::IO, vdr::VDR)
    print(io, "VDR: ", Base.dims2string(size(vdr)), " (", DataType(vdr.data_type), ")")
    is_nrv(vdr) && print(io, " [NRV]")
    is_compressed(vdr) && print(io, " [compressed]")
    return
end

# Flags Signed 4-byte integer, big-endian byte ordering. Boolean flags, one per bit, describing some aspect of this variable. The meaning of each bit is as follows...
# 0 The record variance of this variable. Set indicates a TRUE record variance. Clear indicates a FALSE record variance.
# 1 Whether or not a pad value is specified for this variable. Set indicates that a pad value has been specified. Clear indicates that a pad value has not been specified. The PadValue field described below is only present if a pad value has been specified.
# 2 Whether or not a compression method might be applied to this variable data. Set indicates that a compression is chosen by the user and the data might be compressed, depending on the data size and content. If the compressed data becomes larger than its uncompressed data, no compression is applied and the data are stored as uncompressed, even the compression bit is set. The compressed data is stored in Compressed Variable Value Record (CVVR) while uncompressed data go into Variable Value Record (VVR). Clear indicates that a compression will not be used. The CPRorSPRoffset field provides the offset of the Compressed Parameters Record if this compression bit is set and the compression used.

function read_vvrs(vdr::VDR{FieldSizeT}) where {FieldSizeT}
    vxr_head = vdr.vxr_head
    entries = Vector{VVREntry}()
    src = vdr.buffer
    sizehint!(entries, 1)
    vvr_type = collect_vxr_entries!(entries, src, Int(vxr_head), FieldSizeT)
    vvr_type = @something vvr_type VVR_
    return entries, vvr_type
end

is_record_varying(vdr) = !is_nrv(vdr)
"""Whether or not the variable is a non-record variable"""
is_nrv(vdr) = (vdr.flags & 0x01) == 0
is_compressed(vdr::VDR) = (vdr.flags & 0x04) != 0
