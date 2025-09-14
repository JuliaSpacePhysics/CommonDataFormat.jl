# CDF parsing utilities
# Low-level binary reading and record parsing functions

@inline read_be(io, T) = ntoh(read(io, T))
@inline read_be(io, n, T) = ntuple(i -> read_be(io, T), n)

# Big-endian readers (CDF uses big-endian for most fields)
"""
    read_uint32_be(io::IO)

Read a 32-bit unsigned integer in big-endian byte order.
CDF format uses big-endian for record fields.
"""
read_uint32_be(io::IO) = ntoh(read(io, UInt32))

"""
    read_uint64_be(io::IO)

Read a 64-bit unsigned integer in big-endian byte order.
CDF format uses big-endian for record fields.
"""
read_uint64_be(io::IO) = ntoh(read(io, UInt64))

"""
    is_cdf_v3(magic_bytes)

Determine if this is a CDF v3 file based on the magic number.
"""
is_cdf_v3(magic_bytes) = magic_bytes == 0xCDF30001

const cdf_magic_bytes = [0xCDF30001, 0xCDF26002, 0x0000FFFF] # CDF format uses different magic numbers: CDF3.0, CDF2.x versions

function validate_cdf_magic(magic_bytes)
    return magic_bytes in cdf_magic_bytes
end
