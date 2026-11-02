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

function load_cvvr_data!(dest::Ptr{UInt8}, src::Vector{UInt8}, offset, n, ::Type{RecordSizeType}, compression::CompressionType) where {RecordSizeType}
    cvvr = CVVR(src, offset, RecordSizeType)
    decompress_bytes!(dest, src, cvvr.data_offset, n, cvvr.cSize, compression)
    return
end

# Whole gzip CVVRs, given as `(dest, offset, nbytes)`, decoded in lockstep.
function load_cvvr_group!(src::Vector{UInt8}, jobs::NTuple{N,Tuple{Ptr{UInt8},Int,Int}}, ::Type{RecordSizeType}) where {N, RecordSizeType}
    members = map(jobs) do (dest, offset, n)
        c = CVVR(src, offset, RecordSizeType)
        checkbounds(src, c.data_offset:(c.data_offset + c.cSize - 1))
        (dest, n, pointer(src, c.data_offset), Int(c.cSize))
    end
    GC.@preserve src gzip_decompress!(members)
    return
end
