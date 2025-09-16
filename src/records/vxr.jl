"""
Variable Index Record (VXR) - contains pointers to variable data records
"""
struct VXR
    header::Header
    vxr_next::Int64        # Next VXR in chain
    n_entries::Int32       # Number of entries
    n_used_entries::Int32  # Number of used entries
    first::Tuple{Vararg{UInt32}}   # First record numbers , Unused entries in this array contain 0xFFFFFFFF.
    last::Tuple{Vararg{UInt32}}    # Last record numbers, Unused entries in this array contain 0xFFFFFFFF.
    offset::Tuple{Vararg{UInt64}}  # Offsets to VVR/CVVR records
end


"""
    VXR(source, offset, RecordSizeType)

Load a Variable Index Record from the source at the specified offset.
"""
function VXR end

function VXR(source::Vector{UInt8}, offset, RecordSizeType)
    pos = offset + 1
    header = Header(source, pos, RecordSizeType)
    @assert header.record_type == 6 "Invalid VXR record type"
    pos += sizeof(RecordSizeType) + 4
    # Read VXR fields
    vxr_next, pos = read_be_i(source, pos, RecordSizeType)
    n_entries, pos = read_be_i(source, pos, Int32)
    n_used_entries, pos = read_be_i(source, pos, Int32)
    first, pos = read_be_i(source, pos, n_used_entries, UInt32)
    last, pos = read_be_i(source, pos, n_used_entries, UInt32)
    offset = read_be(source, pos, n_used_entries, RecordSizeType)
    return VXR(header, vxr_next, n_entries, n_used_entries, first, last, offset)
end

@inline function VXR(io::IO, offset, RecordSizeType)
    seek(io, offset)
    # Read header
    header = Header(io, RecordSizeType)
    @assert header.record_type == 6 "Invalid VXR record type"
    source = read(io, header.record_size - sizeof(RecordSizeType) - 4)
    pos = 1
    vxr_next, pos = read_be_i(source, pos, Int64)
    n_entries, pos = read_be_i(source, pos, Int32)
    n_used_entries, pos = read_be_i(source, pos, Int32)
    first, pos = read_be_i(source, pos, n_used_entries, UInt32)
    last, pos = read_be_i(source, pos, n_used_entries, UInt32)
    offset = read_be(source, pos, n_used_entries, RecordSizeType)
    return VXR(header, vxr_next, n_entries, n_used_entries, first, last, offset)
end
