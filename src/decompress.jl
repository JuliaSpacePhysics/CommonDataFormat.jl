include("decompress/rle.jl")


function decompress_bytes(buffer, ::Type{RecordSizeType}) where {RecordSizeType}
    ccr = CCR(buffer, 8, RecordSizeType)
    cpr = CPR(buffer, Int(ccr.cpr_offset), RecordSizeType)
    compression = CompressionType(cpr.compression_type)
    n = Int(ccr.uncompressed_size)
    new_buffer = Vector{UInt8}(undef, 8 + n)
    copyto!(new_buffer, 1, buffer, 1, 4)
    write_be(new_buffer, 5, 0x0000FFFF)  # the uncompressed marker replaces the CCR magic
    decompress_bytes!(new_buffer, 9, buffer, ccr.data_offset, n, ccr.data_length, compression)
    return new_buffer, compression
end

function decompress_bytes!(dest, doffs, src::AbstractVector{UInt8}, soffs, N, n_in, compression::CompressionType)
    n_out = N * sizeof(eltype(dest))
    if compression == NoCompression
        n_in == n_out || throw(ArgumentError("Uncompressed payload size mismatch (expected $n_out, got $n_in)"))
        _copy_to!(dest, doffs, src, soffs, N)
    elseif compression == GzipCompression
        checkbounds(src, soffs:(soffs + n_in - 1))
        GC.@preserve dest src gzip_decompress!(Ptr{UInt8}(pointer(dest, doffs)), n_out, pointer(src, soffs), n_in)
    elseif compression == RLECompression
        out = _rle_decompress(view(src, soffs:(soffs + n_in - 1)), n_out)
        _copy_to!(dest, doffs, out, 1, N)
    else
        throw(ArgumentError("unsupported compression: $compression"))
    end
    return
end
