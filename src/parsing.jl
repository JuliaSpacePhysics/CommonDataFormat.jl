# CDF parsing utilities
# Low-level binary reading and record parsing functions

@inline read_be(io::IO, T) = ntoh(read(io, T))
@inline read_be(io::IO, n, T) = ntuple(i -> read_be(io, T), n)


# Buffer-based reading functions for zero-copy access
# https://github.com/JuliaLang/julia/issues/31305
@inline function read_be(v::Vector{UInt8}, i, T)
    p = convert(Ptr{T}, pointer(v, i))
    return ntoh(unsafe_load(p))
end

@inline function _read_be(v::Vector{UInt8}, i, T)
    S = sizeof(T)
    bytes = @inbounds reinterpret(T, @view v[i:(i + S - 1)])[1]
    return ntoh(bytes)
end

@inline function read_be(v::Vector{UInt8}, i, n, T)
    S = sizeof(T)
    return ntuple(j -> read_be(v, i + (j - 1) * S, T), n)
end

@inline function read_be_i(v::Vector{UInt8}, i, T)
    return read_be(v, i, T), i + sizeof(T)
end

@inline function read_be_i(v::Vector{UInt8}, i, n, T)
    S = sizeof(T)
    return ntuple(j -> read_be(v, i + (j - 1) * S, T), n), i + n * S
end

const name_bytes_buffer = Vector{UInt8}(undef, 256)

# Read variable name (null-terminated string, up to 256 chars)
@inline function readname(io::IO)
    read!(io, name_bytes_buffer)
    null_pos = findfirst(==(0x00), name_bytes_buffer)
    pos = isnothing(null_pos) ? 256 : null_pos - 1
    return @views String(name_bytes_buffer[1:pos])
end

function readname(buf::Vector{UInt8}, offset::Int)
    for i in offset:(offset + 255)
        if buf[i] == 0x00
            return @views buf[offset:(i - 1)]
        end
    end
    return @views buf[offset:(offset + 255)]
end


function get_offsets!(offsets, buffer::Vector{UInt8}, pos::Int64, RecordSizeType)
    while pos != 0
        push!(offsets, pos)
        pos = read_be(buffer, pos + 1 + sizeof(RecordSizeType) + 4, Int64)
    end
    return offsets
end
get_offsets(args...) = get_offsets!(Int64[], args...)


# Big-endian readers (CDF uses big-endian for most fields)
"""
    read_uint32_be(io::IO)

Read a 32-bit unsigned integer in big-endian byte order.
CDF format uses big-endian for record fields.
"""
read_uint32_be(io::IO) = ntoh(read(io, UInt32))

"""
    is_cdf_v3(magic_bytes)

Determine if this is a CDF v3 file based on the magic number.
"""
is_cdf_v3(magic_bytes) = magic_bytes == 0xCDF30001

const cdf_magic_bytes = [0xCDF30001, 0xCDF26002, 0x0000FFFF] # CDF format uses different magic numbers: CDF3.0, CDF2.x versions

function validate_cdf_magic(magic_bytes)
    return magic_bytes in cdf_magic_bytes
end
