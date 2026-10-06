# VDR loading functionality

"""
Variable Descriptor Record (VDR) - describes a single r- or z-variable.
"""
struct VDR{FST} <: Record
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
    num::Int32          # Variable number (r- and z-variables are numbered independently)
    cpr_or_spr_offset::FST  # Compression/Sparseness Parameters Record offset
    # blocking_factor::Int32
    # name::S         # Variable name
    zvar::Bool
    num_dims::Int32   # zNumDims; unused for r-variables, whose dims come from the GDR
    pos::Int          # zDimSizes (z) / DimVarys (r)
end

# zNumDims (zVDRs) / DimVarys (rVDRs) start right after the fixed-width name field.
_after_name(offset, ::Type{FieldSizeT}) where {FieldSizeT} = FieldSizeT == Int64 ? offset + 341 : offset + 129

"""
    VDR{FieldSizeT}(buffer, offset)

Load a z- or r-Variable Descriptor Record from the buffer at the specified offset.
"""
@inline function VDR{FieldSizeT}(buffer::Vector{UInt8}, offset) where {FieldSizeT}
    record_type = get_record_type(buffer, offset, FieldSizeT)
    @assert record_type in (8, 3)
    zvar = record_type == 8
    pos = offset + sizeof(FieldSizeT) + 5
    fields, _ = read_be_fields(buffer, pos, VDR{FieldSizeT}, Val(1:13))
    after_name = _after_name(offset, FieldSizeT)
    zvar || return VDR{FieldSizeT}(fields..., false, Int32(0), after_name)
    z_num_dims, pos = read_be_i(buffer, after_name, Int32)
    return VDR{FieldSizeT}(fields..., true, z_num_dims, pos)
end

function record_sizes(vdr::VDR, cdf, ::Val{M}) where {M}
    vdr.zvar || return _rvar_record_sizes(vdr, cdf, Val(M))
    vdr.num_dims == M ||
        throw(DimensionMismatch("variable has $(vdr.num_dims) dimensions, expected $M"))
    return read_be(parent(cdf), vdr.pos, Val(M), Int32)
end

function _rvar_record_sizes(vdr::VDR, cdf, ::Val{M}) where {M}
    gdr = GDR(cdf)
    buf = parent(cdf)
    sizes_pos = gdr.pos + sizeof(Int64) + 3 * sizeof(Int32)
    sizes = zeros(Int32, M)
    count = 0
    for i in 1:Int(gdr.r_num_dims)
        read_be(buf, vdr.pos + (i - 1) * 4, Int32) == 0 && continue
        count += 1
        count <= M && (sizes[count] = read_be(buf, sizes_pos + (i - 1) * 4, Int32))
    end
    count == M || throw(DimensionMismatch("variable has $count dimensions, expected $M"))
    return ntuple(i -> sizes[i], Val(M))
end

function num_record_dims(vdr::VDR, cdf)
    vdr.zvar && return Int(vdr.num_dims)
    n = 0
    for i in 1:Int(GDR(cdf).r_num_dims)
        n += read_be(parent(cdf), vdr.pos + (i - 1) * 4, Int32) != 0
    end
    return n
end


function Base.show(io::IO, vdr::VDR)
    print(io, "VDR: ", CDFDataType(vdr.data_type))
    is_nrv(vdr) && print(io, " [NRV]")
    is_compressed(vdr) && print(io, " [compressed]")
    return
end

# Flags Signed 4-byte integer, big-endian byte ordering. Boolean flags, one per bit, describing some aspect of this variable. The meaning of each bit is as follows...
# 0 The record variance of this variable. Set indicates a TRUE record variance. Clear indicates a FALSE record variance.
# 1 Whether or not a pad value is specified for this variable. Set indicates that a pad value has been specified. Clear indicates that a pad value has not been specified. The PadValue field described below is only present if a pad value has been specified.
# 2 Whether or not a compression method might be applied to this variable data. Set indicates that a compression is chosen by the user and the data might be compressed, depending on the data size and content. If the compressed data becomes larger than its uncompressed data, no compression is applied and the data are stored as uncompressed, even the compression bit is set. The compressed data is stored in Compressed Variable Value Record (CVVR) while uncompressed data go into Variable Value Record (VVR). Clear indicates that a compression will not be used. The CPRorSPRoffset field provides the offset of the Compressed Parameters Record if this compression bit is set and the compression used.

function read_vvrs(vdr::VDR{FieldSizeT}, cdf) where {FieldSizeT}
    entries = Vector{VVREntry}()
    sizehint!(entries, 1)
    collect_vxr_entries!(entries, parent(cdf), Int(vdr.vxr_head), FieldSizeT)
    return entries
end

is_record_varying(vdr) = !is_nrv(vdr)
"""Whether or not the variable is a non-record variable"""
is_nrv(vdr) = (vdr.flags & 0x01) == 0
is_compressed(vdr::VDR) = (vdr.flags & 0x04) != 0
