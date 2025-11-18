# CDF Record structures and definitions
# Based on the C++ CDFpp implementation structure
# [CDF Internal Format Description](https://spdf.gsfc.nasa.gov/pub/software/cdf/doc/cdfifd.pdf)
Base.iterate(r::Record, i = 1) = i > fieldcount(typeof(r)) ? nothing : (getfield(r, i), i + 1)

"""
CDF Record header structure - common to all record types
"""
struct Header
    record_size::Int64  # Can be Int32 for v2, Int64 for v3
    record_type::Int32
end

@inline function Header(buf::Vector{UInt8}, pos, FieldSizeT)
    record_size = Int64(read_be(buf, pos, FieldSizeT))
    record_type = read_be(buf, pos + sizeof(FieldSizeT), Int32)
    return Header(record_size, record_type)
end

get_record_type(buffer, offset, FieldSizeT) = read_be(buffer, offset + sizeof(FieldSizeT) + 1, Int32)

@inline function check_record_type(record_type::Integer, buffer, offset, FieldSizeT)
    pos = offset + sizeof(FieldSizeT) + 1
    header_type = read_be(buffer, pos, Int32)
    @assert header_type == record_type
    return pos + sizeof(Int32)
end

@inline function check_record_type(record_types, buffer, offset, FieldSizeT)
    pos = offset + sizeof(FieldSizeT) + 1
    header_type = read_be(buffer, pos, Int32)
    @assert header_type in record_types
    return pos + sizeof(Int32)
end

include("cdr.jl")
include("gdr.jl")
include("vdr.jl")
include("vxr.jl")
include("adr.jl")
include("aedr.jl")
include("vvr.jl")
include("cpr.jl")
include("ccr.jl")
include("cvvr.jl")

# Utility functions to decode CDR flags
"""
    decode_cdr_flags(flags::UInt32)

Decode the CDR flags field into individual boolean flags.

# CDF Flags (from CDF specification):
- Bit 0: Majority (1=row-major, 0=column-major)
- Bit 1: File format (1=single-file, 0=multi-file)
- Bit 2: Checksum used (1=checksum present, 0=no checksum)
- Bit 3: MD5 checksum method (requires bit 2=1)
"""
function decode_cdr_flags(flags)
    flags = UInt32(flags)
    return (
        single_file_format = (flags & 0x02) != 0,
        checksum_used = (flags & 0x04) != 0,
        md5_checksum = (flags & 0x08) != 0,
    )
end

# Pretty printing for CDR structure
function Base.show(io::IO, cdr::CDR)
    flag_info = decode_cdr_flags(cdr.flags)

    println(io, "CDR (CDF Descriptor Record):")
    println(io, "  Version: $(cdr.version).$(cdr.release).$(cdr.increment)")
    println(io, "  Encoding: $(cdr.encoding)")
    println(io, "  Flags: 0x$(string(cdr.flags, base = 16, pad = 8))")
    println(io, "    - Majority: $(majority(cdr))")
    println(io, "    - Single File Format: $(flag_info.single_file_format)")
    println(io, "    - Checksum Used: $(flag_info.checksum_used)")
    println(io, "    - MD5 Checksum: $(flag_info.md5_checksum)")
    println(io, "  Identifier: $(cdr.identifier)")
    return
end
