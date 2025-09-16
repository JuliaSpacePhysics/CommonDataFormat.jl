# CDF Record structures and definitions
# Based on the C++ CDFpp implementation structure
# [CDF Internal Format Description](https://spdf.gsfc.nasa.gov/pub/software/cdf/doc/cdfifd.pdf)
abstract type Record end

Base.iterate(r::Record, i = 1) = i > fieldcount(typeof(r)) ? nothing : (getfield(r, i), i + 1)

"""
CDF Record header structure - common to all record types
"""
struct Header
    record_size::Int64  # Can be Int32 for v2, Int64 for v3
    record_type::Int32
end

@inline function Header(io::IO, RecordSizeType)
    record_size = Int64(read_be(io, RecordSizeType))
    record_type = read_be(io, Int32)
    return Header(record_size, record_type)
end

@inline function Header(buf::Vector{UInt8}, pos, RecordSizeType)
    record_size = Int64(read_be(buf, pos, RecordSizeType))
    record_type = read_be(buf, pos + sizeof(RecordSizeType), Int32)
    return Header(record_size, record_type)
end

include("cdr.jl")
include("vdr.jl")
include("vxr.jl")
include("adr.jl")
include("aedr.jl")
include("gdr.jl")

for R in (:ADR, :AEDR, :GDR, :VDR)
    @eval begin
        @inline function $R(io::IO, offset, RecordSizeType)
            seek(io, offset)
            return $R(io, RecordSizeType)
        end
    end
end

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
        row_majority = (flags & 0x01) != 0,
        single_file_format = (flags & 0x02) != 0,
        checksum_used = (flags & 0x04) != 0,
        md5_checksum = (flags & 0x08) != 0,
    )
end

# Pretty printing for CDR structure
function Base.show(io::IO, cdr::CDR)
    flag_info = decode_cdr_flags(cdr.flags)

    println(io, "CDR (CDF Descriptor Record):")
    println(io, "  Record Size: $(cdr.header.record_size) bytes")
    println(io, "  Record Type: $(cdr.header.record_type)")
    println(io, "  GDR Offset: 0x$(string(cdr.gdr_offset, base = 16, pad = 8))")
    println(io, "  Version: $(cdr.version).$(cdr.release).$(cdr.increment)")
    println(io, "  Encoding: $(cdr.encoding)")
    println(io, "  Flags: 0x$(string(cdr.flags, base = 16, pad = 8))")
    println(io, "    - Row Majority: $(flag_info.row_majority)")
    println(io, "    - Single File Format: $(flag_info.single_file_format)")
    println(io, "    - Checksum Used: $(flag_info.checksum_used)")
    println(io, "    - MD5 Checksum: $(flag_info.md5_checksum)")
    return println(io, "  Identifier: $(cdr.identifier)")
end
