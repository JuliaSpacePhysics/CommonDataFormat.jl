struct CCR <: Record
    cpr_offset::UInt64
    uncompressed_size::UInt64 # uSize Size of the CDF in its uncompressed form. This byte count does NOT include the 8-byte magic numbers, and 16-byte checksum if it exists.
    rfu_a::RInt32
    data_offset::Int
    data_length::Int
end

@inline function CCR(buffer::Vector{UInt8}, offset, ::Type{RecordSizeType}) where {RecordSizeType}
    record_end = offset + record_size(buffer, offset, RecordSizeType)
    pos = check_record_type(10, buffer, offset, RecordSizeType)
    cpr_offset, pos = read_be_i(buffer, pos, RecordSizeType)
    uncompressed_size, pos = read_be_i(buffer, pos, RecordSizeType)
    rfu_a, data_offset = read_be_i(buffer, pos, RInt32)
    data_length = record_end - data_offset + 1
    @assert data_length > 0 "Invalid CCR data length"
    return CCR(UInt64(cpr_offset), UInt64(uncompressed_size), rfu_a, data_offset, data_length)
end
