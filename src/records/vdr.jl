# VDR loading functionality

"""
Variable Descriptor Record (VDR) - describes a single variable
Can be either r-variable (record variant) or z-variable (zero variant)

See also: [zVDR](@ref)
"""
struct VDR{DT} <: Record
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
    name::String         # Variable name
end

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
