include("decompress/rle.jl")


function decompress_bytes(buffer, ::Type{RecordSizeType}) where {RecordSizeType}
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
    compression in (GzipCompression, RLECompression) ||
        throw(ArgumentError("unsupported compression: $compression"))
    result = if compression == GzipCompression
        input = convert(Vector{UInt8}, data)
        output = UInt8[]
        # Sizes `output` from the member's ISIZE trailer, so no output-size guess is needed.
        out = gzip_isize_decompress!(Decompressor(), output, input, GzipExtraField[])
        out isa LibDeflateError && throw(ArgumentError("gzip decompression failed: $out"))
        output
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
    elseif compression == GzipCompression
        n_out = N * sizeof(eltype(dest))
        fields = GzipExtraField[]
        GC.@preserve dest src begin
            out = unsafe_gzip_decompress!(
                decompressor,
                WriteableMemory(pointer(dest, doffs), n_out),
                ReadableMemory(pointer(src, soffs), n_in),
                UInt(n_out),
                fields,
            )
            out isa LibDeflateError && throw(ArgumentError("gzip decompression failed: $out"))
        end
    elseif compression == RLECompression
        n_out = N * sizeof(eltype(dest))
        out = _rle_decompress(view(src, soffs:(soffs + n_in - 1)), n_out)
        _copy_to!(dest, doffs, out, 1, N)
    else
        throw(ArgumentError("unsupported variable compression: $compression"))
    end
    return
end
