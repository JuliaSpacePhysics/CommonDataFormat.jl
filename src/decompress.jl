include("decompress/rle.jl")
include("decompress/gzip.jl")


function decompress_bytes(buffer, RecordSizeType)
    ccr = CCR(buffer, 8, RecordSizeType)
    cpr = CPR(buffer, Int(ccr.cpr_offset), RecordSizeType)
    compression = CompressionType(cpr.compression_type)
    payload = data_view(ccr, buffer)
    expected = Int(ccr.uncompressed_size)
    decompressed = decompress_bytes(payload, compression; expected_bytes = expected)
    new_size = 8 + length(decompressed)
    new_buffer = Vector{UInt8}(undef, new_size)
    copyto!(new_buffer, 1, buffer, 1, 4)
    new_buffer[5] = 0x00
    new_buffer[6] = 0x00
    new_buffer[7] = 0xFF
    new_buffer[8] = 0xFF
    copyto!(new_buffer, 9, decompressed, 1, length(decompressed))
    return new_buffer, compression
end

function decompress_bytes(data, compression::CompressionType; expected_bytes::Union{Nothing, Int} = nothing)
    compression == NoCompression && return data
    @assert compression in (GzipCompression, RLECompression)
    result = if compression == GzipCompression
        transcode(GzipDecompressor, Vector{UInt8}(data))
    else
        isnothing(expected_bytes) && throw(ArgumentError("RLE decompression requires expected size"))
        _rle_decompress(data, expected_bytes)
    end
    if !isnothing(expected_bytes) && length(result) != expected_bytes
        throw(ArgumentError("Decompressed payload size mismatch (expected $(expected_bytes), got $(length(result)))"))
    end
    return result
end

function decompress_bytes!(decompressor, dest, doffs, src::AbstractVector{UInt8}, soffs, N, n_in, compression::CompressionType)
    if compression == NoCompression
        _copy_to!(dest, doffs, src, soffs, N)
        return
    end
    @assert compression in (GzipCompression, RLECompression)
    n_out = N * sizeof(eltype(dest))
    out_ptr = pointer(dest, doffs)
    in_ptr = pointer(src, soffs)
    return if compression == GzipCompression
        out = _unsafe_gzip_decompress!(decompressor, out_ptr, n_out, in_ptr, n_in)
        @assert !(out isa LibDeflateError) out
    elseif compression == RLECompression
    end
end
