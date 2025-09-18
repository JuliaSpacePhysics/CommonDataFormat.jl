struct CCR <: Record
    header::Header
    cpr_offset::UInt64
    uncompressed_size::UInt64 # uSize Size of the CDF in its uncompressed form. This byte count does NOT include the 8-byte magic numbers, and 16-byte checksum if it exists.
    rfu_a::UInt32
    data_offset::Int
    data_length::Int
end

@inline function CCR(buffer::Vector{UInt8}, offset, RecordSizeType)
    pos = offset + 1
    header = Header(buffer, pos, RecordSizeType)
    @assert header.record_type == 10 "Invalid CCR record type"
    pos += sizeof(RecordSizeType) + 4
    cpr_offset, pos = read_be_i(buffer, pos, RecordSizeType)
    uncompressed_size, pos = read_be_i(buffer, pos, RecordSizeType)
    rfu_a, data_offset = read_be_i(buffer, pos, UInt32)
    record_end = offset + header.record_size
    data_length = record_end - data_offset
    @assert data_length >= 0 "Invalid CCR data length"
    return CCR(header, UInt64(cpr_offset), UInt64(uncompressed_size), UInt32(rfu_a), data_offset, data_length)
end

@inline function data_view(ccr::CCR, buffer::Vector{UInt8})
    start = ccr.data_offset
    stop = start + ccr.data_length
    return view(buffer, (start):(stop))
end
