struct CVVR <: Record
    cSize::Int64
    data_offset::Int
end

@inline function CVVR(buffer::Vector{UInt8}, offset, RecordSizeType; check = false)
    pos = offset + 1 + sizeof(RecordSizeType)
    record_type, pos = read_be_i(buffer, pos, Int32)
    check && @assert record_type == 13 "Invalid CVVR record type"
    pos += sizeof(Int32)
    cSize, pos = read_be_i(buffer, pos, RecordSizeType)
    return CVVR(Int64(cSize), pos)
end

function load_cvvr_data!(data::Vector{T}, pos, src::Vector{UInt8}, offset, N, RecordSizeType, compression::CompressionType; decompressor = Decompressor()) where {T}
    cvvr = CVVR(src, offset, RecordSizeType)
    decompress_bytes!(decompressor, data, pos, src, cvvr.data_offset, N, cvvr.cSize, compression)
    return
end
