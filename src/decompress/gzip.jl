# similar to unsafe_gzip_decompress!, but handles the pointer
function _unsafe_gzip_decompress!(
        decompressor::Decompressor,
        out_ptr,
        max_outlen,
        in_ptr::Ptr,
        len::Integer,
        extra_data = nothing,
    )::Union{LibDeflateError, GzipDecompressResult}
    # We need to have at least 2 + 4 + 4 bytes left after header
    nonheader_min_len = 2 + 4 + 4

    # First decompress header
    hdr_result = unsafe_parse_gzip_header(in_ptr, UInt(len - nonheader_min_len), extra_data)
    hdr_result isa LibDeflateError && return hdr_result
    header_len, header = hdr_result

    # Skip to end to check crc32 and data len
    # +---+---+---+---+---+---+---+---+
    # |     CRC32     |     ISIZE     | END OF FILE
    # +---+---+---+---+---+---+---+---+

    compressed_len = len - UInt(8) - header_len
    uncompressed_size = ltoh(unsafe_load(Ptr{UInt32}(in_ptr + len - UInt(4))))
    uncompressed_size > max_outlen && return LibDeflateErrors.deflate_insufficient_space
    # Now DEFLATE decompress
    decomp_result = unsafe_decompress!(
        Base.HasLength(),
        decompressor,
        out_ptr,
        uncompressed_size,
        in_ptr + header_len,
        compressed_len,
    )
    decomp_result isa LibDeflateError && return decomp_result

    # Check for CRC checksum and validate it
    crc_exp = ltoh(unsafe_load(Ptr{UInt32}(in_ptr + len - UInt(8))))
    crc_obs = unsafe_crc32(out_ptr, uncompressed_size % Int)
    crc_exp == crc_obs || return LibDeflateErrors.gzip_bad_crc32

    return GzipDecompressResult(uncompressed_size, header)
end
