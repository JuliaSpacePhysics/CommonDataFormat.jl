"""
    VXR(io::IO, offset, RecordSizeType)

Load a Variable Index Record from the IO stream at the specified offset.
"""
function VXR(io::IO, offset, RecordSizeType)
    seek(io, offset)

    # Read header
    header = Header(io, RecordSizeType)
    @assert header.record_type == 6 "Invalid VXR record type"
    # Read VXR fields
    vxr_next = UInt64(read_be(io, RecordSizeType))
    n_entries = read_uint32_be(io)
    n_used_entries = read_uint32_be(io)

    # Read arrays
    first = map(i -> read_uint32_be(io), 1:n_used_entries)
    last = map(i -> read_uint32_be(io), 1:n_used_entries)
    offset_array = map(i -> UInt64(read_be(io, RecordSizeType)), 1:n_used_entries)

    return VXR(header, vxr_next, n_entries, n_used_entries, first, last, offset_array)
end
