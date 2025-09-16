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

include("cdr.jl")
include("vdr.jl")
include("adr.jl")
include("gdr.jl")

"""
z-Variable Descriptor Record (zVDR)
"""
struct zVDR{DT}
    header::Header
    vdr_next::Int64     # Offset to next VDR in chain
    data_type::DT    # CDF data type
    max_rec::Int32       # Maximum record number (-1 if none)
    vxr_head::Int64     # Variable indeX Record head
    vxr_tail::Int64     # Variable indeX Record tail
    flags::UInt32        # Variable flags
    s_records::UInt32    # Sparse records flag
    rfu_b::UInt32        # Reserved field B
    rfu_c::UInt32        # Reserved field C
    rfu_f::UInt32        # Reserved field F
    num_elems::UInt32    # Number of elements (for strings)
    num::UInt32          # Variable number
    cpr_or_spr_offset::UInt64  # Compression/Sparseness Parameters Record offset
    blocking_factor::UInt32
    name::String         # Variable name
    z_num_dims::UInt32   # Number of dimensions (z-variables only)
    z_dim_sizes::Vector{UInt32}  # Dimension sizes (z-variables only)
    dim_varys::Vector{UInt32}    # Dimension variance flags
end


@inline function zVDR(io::IO, args...)
    vdr = VDR(io, args...)
    z_num_dims = read_uint32_be(io)

    # Read dimension sizes
    z_dim_sizes = Vector{UInt32}(undef, z_num_dims)
    dim_varys = Vector{UInt32}(undef, z_num_dims)
    for i in eachindex(z_dim_sizes)
        z_dim_sizes[i] = read_uint32_be(io)
    end
    # Read dimension variance flags
    for i in eachindex(dim_varys)
        dim_varys[i] = read_uint32_be(io)
    end

    return zVDR(vdr..., z_num_dims, z_dim_sizes, dim_varys)
end

"""
Variable Index Record (VXR) - contains pointers to variable data records
"""
struct VXR
    header::Header
    vxr_next::UInt64        # Next VXR in chain
    n_entries::UInt32       # Number of entries
    n_used_entries::UInt32  # Number of used entries
    first::Vector{UInt32}   # First record numbers
    last::Vector{UInt32}    # Last record numbers
    offset::Vector{UInt64}  # Offsets to VVR/CVVR records
end

"""
Variable Value Record (VVR) - contains actual variable data
"""
struct VVR{T}
    header::Header
    data::Vector{T}     # Raw variable data
end

for R in (:ADR, :CDR, :GDR, :VXR, :VDR)
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
