struct CVVR <: Record
    cSize::Int64
    data_offset::Int
end

@inline function CVVR(buffer::Vector{UInt8}, offset, ::Type{RecordSizeType}; check = false) where {RecordSizeType}
    pos = offset + 1 + sizeof(RecordSizeType)
    record_type, pos = read_be_i(buffer, pos, Int32)
    check && @assert record_type == 13 "Invalid CVVR record type"
    pos += sizeof(Int32)
    cSize, pos = read_be_i(buffer, pos, RecordSizeType)
    return CVVR(Int64(cSize), pos)
end

function load_cvvr_data!(data, pos, src::Vector{UInt8}, offset, N, ::Type{RecordSizeType}, compression::CompressionType) where {RecordSizeType}
    cvvr = CVVR(src, offset, RecordSizeType)
    decompress_bytes!(data, pos, src, cvvr.data_offset, N, cvvr.cSize, compression)
    return
end

# Whole gzip CVVRs, given as `(dest_pos, offset, nbytes)`, decoded in lockstep.
function load_cvvr_group!(dest::Vector{UInt8}, src::Vector{UInt8}, jobs::NTuple{N,NTuple{3,Int}}, ::Type{RecordSizeType}) where {N, RecordSizeType}
    members = map(jobs) do (pos, offset, n)
        c = CVVR(src, offset, RecordSizeType)
        checkbounds(src, c.data_offset:(c.data_offset + c.cSize - 1))
        checkbounds(dest, pos:(pos + n - 1))
        (pointer(dest, pos), n, pointer(src, c.data_offset), Int(c.cSize))
    end
    GC.@preserve dest src gzip_decompress!(members)
    return
end
