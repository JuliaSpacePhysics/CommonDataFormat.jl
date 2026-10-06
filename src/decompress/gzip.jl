# Decompress the single gzip member at `in_ptr` into at most `max_outlen` bytes at `out_ptr`,
# taking the exact output size from the ISIZE trailer to use libdeflate's faster known-size path.
# Returns the number of bytes written or a `LibDeflateError`.
# LibDeflate 1.x (Julia ≥ 1.12) rewrote the API; 0.4 is kept for Julia 1.10/1.11.
@static if pkgversion(LibDeflate) >= v"1"
    function _unsafe_gzip_decompress!(decompressor::Decompressor, out_ptr, max_outlen, in_ptr::Ptr, len::Integer)
        len < 10 && return LibDeflateErrors.input_too_short
        isize = UInt(ltoh(unsafe_load(Ptr{UInt32}(in_ptr + len - 4))))
        result = unsafe_gzip_decompress!(
            decompressor, WriteableMemory(out_ptr, max_outlen), ReadableMemory(in_ptr, len),
            isize, GzipExtraField[]
        )
        return result isa LibDeflateError ? result : Int(result.written)
    end
else
    # similar to unsafe_gzip_decompress!, but handles the pointer
    function _unsafe_gzip_decompress!(decompressor::Decompressor, out_ptr, max_outlen, in_ptr::Ptr, len::Integer)
        # We need to have at least 2 + 4 + 4 bytes left after header
        nonheader_min_len = 2 + 4 + 4

        hdr_result = unsafe_parse_gzip_header(in_ptr, UInt(len - nonheader_min_len), nothing)
        hdr_result isa LibDeflateError && return hdr_result
        header_len, _ = hdr_result

        # +---+---+---+---+---+---+---+---+
        # |     CRC32     |     ISIZE     | END OF FILE
        # +---+---+---+---+---+---+---+---+
        compressed_len = len - UInt(8) - header_len
        uncompressed_size = ltoh(unsafe_load(Ptr{UInt32}(in_ptr + len - UInt(4))))
        uncompressed_size > max_outlen && return LibDeflateErrors.deflate_insufficient_space
        decomp_result = unsafe_decompress!(
            Base.HasLength(), decompressor, out_ptr, uncompressed_size,
            in_ptr + header_len, compressed_len,
        )
        decomp_result isa LibDeflateError && return decomp_result

        crc_exp = ltoh(unsafe_load(Ptr{UInt32}(in_ptr + len - UInt(8))))
        crc_obs = unsafe_crc32(out_ptr, uncompressed_size % Int)
        crc_exp == crc_obs || return LibDeflateErrors.gzip_bad_crc32

        return Int(uncompressed_size)
    end
end
