# VDR loading functionality

abstract type AbstractVDR{FST} <: Record end

struct rVDR{FST} <: AbstractVDR{FST}
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
    pos::Int
    buffer::Vector{UInt8}
    gdr::GDR{FST}
end

"""
Variable Descriptor Record (VDR) - describes a single variable
"""
struct VDR{FST} <: AbstractVDR{FST}
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
    num_dims::Int32   # Number of dimensions
    pos::Int
    buffer::Vector{UInt8}
    # z_dim_sizes::Tuple{Vararg{Int32}}  # Dimension sizes (z-variables only)
    # dim_varys::Tuple{Vararg{Int32}}    # Dimension variance flags
end

"""
    VDR(io::IO, FieldSizeT)

Load a Variable Descriptor Record from the IO stream at the specified offset.
"""
@inline function VDR(buffer::Vector{UInt8}, offset, ::Type{FieldSizeT}) where {FieldSizeT}
    pos = check_record_type(8, buffer, offset, FieldSizeT)
    fields, pos = read_be_fields(buffer, pos, VDR{FieldSizeT}, Val(1:13))
    # name = readname(buffer, pos)

    pos = FieldSizeT == Int64 ? offset + 340 + 1 : offset + 128 + 1
    z_num_dims, pos = read_be_i(buffer, pos, Int32)
    return VDR{FieldSizeT}(fields..., z_num_dims, pos, buffer)
end

"""
    rVDR(io::IO, FieldSizeT)

Load a Variable Descriptor Record from the IO stream at the specified offset.
"""
@inline function rVDR(buffer::Vector{UInt8}, offset, gdr, ::Type{FieldSizeT}) where {FieldSizeT}
    pos = check_record_type(3, buffer, offset, FieldSizeT)
    fields, pos = read_be_fields(buffer, pos, rVDR{FieldSizeT}, Val(1:13))
    pos = FieldSizeT == Int64 ? offset + 340 + 1 : offset + 128 + 1
    return rVDR{FieldSizeT}(fields..., pos, buffer, gdr)
end


@inline function record_sizes(vdr::rVDR)
    gdr = vdr.gdr
    buffer = vdr.buffer
    dim_varys = collect(read_be(buffer, vdr.pos, gdr.r_num_dims, Int32))
    return r_dim_sizes(gdr, buffer)[dim_varys .!= 0]
end

@inline function record_sizes(vdr::VDR)
    return read_be(vdr.buffer, vdr.pos, vdr.num_dims, Int32)
end

# Static-arity variants for the typed `read!` path: the caller supplies the dimension
# count via `Val`, so tuple lengths stay inferable under `juliac --trim`. They avoid the
# runtime-length tuples (and `collect`/logical indexing for rVDR) of the methods above.
function record_sizes(vdr::VDR, ::Val{M}) where {M}
    vdr.num_dims == M ||
        throw(DimensionMismatch("variable has $(vdr.num_dims) dimensions, expected $M"))
    return read_be(vdr.buffer, vdr.pos, Val(M), Int32)
end

function record_sizes(vdr::rVDR, ::Val{M}) where {M}
    gdr = vdr.gdr
    buf = vdr.buffer
    sizes_pos = gdr.pos + sizeof(Int64) + 3 * sizeof(Int32) # mirrors `r_dim_sizes`
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

num_record_dims(vdr::VDR) = Int(vdr.num_dims)
function num_record_dims(vdr::rVDR)
    n = 0
    for i in 1:Int(vdr.gdr.r_num_dims)
        n += read_be(vdr.buffer, vdr.pos + (i - 1) * 4, Int32) != 0
    end
    return n
end


function Base.size(vdr::AbstractVDR)
    records = vdr.max_rec + 1
    dims = (record_sizes(vdr)..., records)
    return Int.(dims)
end

function Base.show(io::IO, vdr::AbstractVDR)
    print(io, "VDR: ", Base.dims2string(size(vdr)), " (", CDFDataType(vdr.data_type), ")")
    is_nrv(vdr) && print(io, " [NRV]")
    is_compressed(vdr) && print(io, " [compressed]")
    return
end

# Flags Signed 4-byte integer, big-endian byte ordering. Boolean flags, one per bit, describing some aspect of this variable. The meaning of each bit is as follows...
# 0 The record variance of this variable. Set indicates a TRUE record variance. Clear indicates a FALSE record variance.
# 1 Whether or not a pad value is specified for this variable. Set indicates that a pad value has been specified. Clear indicates that a pad value has not been specified. The PadValue field described below is only present if a pad value has been specified.
# 2 Whether or not a compression method might be applied to this variable data. Set indicates that a compression is chosen by the user and the data might be compressed, depending on the data size and content. If the compressed data becomes larger than its uncompressed data, no compression is applied and the data are stored as uncompressed, even the compression bit is set. The compressed data is stored in Compressed Variable Value Record (CVVR) while uncompressed data go into Variable Value Record (VVR). Clear indicates that a compression will not be used. The CPRorSPRoffset field provides the offset of the Compressed Parameters Record if this compression bit is set and the compression used.

function read_vvrs(vdr::AbstractVDR{FieldSizeT}) where {FieldSizeT}
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
has_pad_value(vdr::AbstractVDR) = (vdr.flags & 0x02) != 0
is_compressed(vdr::AbstractVDR) = (vdr.flags & 0x04) != 0

# sRecords: 0 = none, 1 = pad sparse, 2 = previous-record sparse
sparse_type(vdr::AbstractVDR) = Int(vdr.s_records)

# PadValue trails zDimSizes+DimVarys (zVDR) / DimVarys (rVDR), both starting at vdr.pos
_pad_value_pos(vdr::VDR) = vdr.pos + 8 * Int(vdr.num_dims)
_pad_value_pos(vdr::rVDR) = vdr.pos + 4 * Int(vdr.gdr.r_num_dims)

# Returned in file encoding: virtual records are filled before the final byte swap
# in `readblock!`, which fixes pad and physical data together.
function pad_value(vdr::AbstractVDR, ::Type{T}, needs_byte_swap) where {T}
    if has_pad_value(vdr)
        buf = vdr.buffer
        return GC.@preserve buf unsafe_load(convert(Ptr{T}, pointer(buf, _pad_value_pos(vdr))))
    end
    return _file_encode(default_pad(T), needs_byte_swap)
end

_file_encode(x, needs_byte_swap) = needs_byte_swap ? hton(x) : x
_file_encode(x::StaticString, needs_byte_swap) = x # excluded from byte swap

# NASA CDF library default pad values (≠ ISTP FILLVAL)
default_pad(::Type{Int8}) = Int8(-127)
default_pad(::Type{Int16}) = Int16(-32767)
default_pad(::Type{Int32}) = Int32(-2147483647)
default_pad(::Type{Int64}) = Int64(-9223372036854775807)
default_pad(::Type{UInt8}) = UInt8(254)
default_pad(::Type{UInt16}) = UInt16(65534)
default_pad(::Type{UInt32}) = UInt32(4294967294)
default_pad(::Type{Float32}) = Float32(-1.0e30)
default_pad(::Type{Float64}) = -1.0e30
default_pad(::Type{Epoch}) = Epoch(-1.0e30)
default_pad(::Type{Epoch16}) = Epoch16(-1.0e30, -1.0e30)
default_pad(::Type{TT2000}) = TT2000(Int64(-9223372036854775807))
default_pad(::Type{StaticString{N, UInt8}}) where {N} = StaticString{N, UInt8}(ntuple(_ -> UInt8(' '), Val(N)))
