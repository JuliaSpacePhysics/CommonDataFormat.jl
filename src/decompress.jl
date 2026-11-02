include("decompress/rle.jl")


function decompress_bytes(buffer, ::Type{RecordSizeType}) where {RecordSizeType}
    ccr = CCR(buffer, 8, RecordSizeType)
    cpr = CPR(buffer, Int(ccr.cpr_offset), RecordSizeType)
    compression = CompressionType(cpr.compression_type)
    n = Int(ccr.uncompressed_size)
    new_buffer = Vector{UInt8}(undef, 8 + n)
    copyto!(new_buffer, 1, buffer, 1, 4)
    write_be(new_buffer, 5, 0x0000FFFF)  # the uncompressed marker replaces the CCR magic
    GC.@preserve new_buffer decompress_bytes!(pointer(new_buffer, 9), buffer, ccr.data_offset, n, ccr.data_length, compression)
    return new_buffer, compression
end

function decompress_bytes!(dest::Ptr{UInt8}, src::AbstractVector{UInt8}, soffs, n_out, n_in, compression::CompressionType)
    checkbounds(src, soffs:(soffs + n_in - 1))
    if compression == NoCompression
        n_in == n_out || throw(ArgumentError("Uncompressed payload size mismatch (expected $n_out, got $n_in)"))
        GC.@preserve src unsafe_copyto!(dest, pointer(src, soffs), n_out)
    elseif compression == GzipCompression
        GC.@preserve src gzip_decompress!(dest, n_out, pointer(src, soffs), n_in)
    elseif compression == RLECompression
        out = _rle_decompress(view(src, soffs:(soffs + n_in - 1)), n_out)
        GC.@preserve out unsafe_copyto!(dest, pointer(out), n_out)
    else
        throw(ArgumentError("unsupported compression: $compression"))
    end
    return
end
