# CDF Record structures and definitions
# Based on the C++ CDFpp implementation structure

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

"""
CDF Descriptor Record (CDR) - the main file header record
Contains version, encoding, format information, and pointer to GDR
"""
struct CDR
    header::Header
    gdr_offset::UInt64   # Can be UssInt32 for v2, UInt64 for v3
    version::Int32
    release::Int32
    encoding::Int32
    flags::Int32
    rfu_a::Int32       # Reserved field A
    rfu_b::Int32       # Reserved field B
    increment::Int32
    identifier::Int32
    rfu_e::Int32       # Reserved field E
    # Note: copyright string follows but we'll handle it separately
end

version(cdr::CDR; verbose = true) = verbose ? (cdr.version, cdr.release, cdr.increment) : cdr.version
Majority(cdr::CDR) = (cdr.flags & 0x01) != 0 ? Majority(0) : Majority(1)  # Row=0, Column=1
is_cdf_v3(cdr::CDR) = cdr.version == 3

"""
File header containing parsed information from CDR
"""
struct FileHeader
    version::Tuple{UInt32, UInt32, UInt32}
    majority::Majority
    compression::CompressionType
    cdr::CDR  # Store the parsed CDR for reference
end

"""
Global Descriptor Record (GDR) - contains global information about the CDF file
Points to variable and attribute descriptor records
"""
struct GDR
    header::Header
    rVDRhead::Int64    # Offset to first r-variable descriptor record
    zVDRhead::Int64    # Offset to first z-variable descriptor record
    ADRhead::Int64     # Offset to first attribute descriptor record
    eof::Int64          # End of file offset
    NrVars::Int32      # Number of r-variables
    num_attr::Int32     # Number of attributes
    r_max_rec::Int32    # Maximum record number for r-variables
    r_num_dims::Int32   # Number of dimensions for r-variables
    NzVars::Int32      # Number of z-variables
    uir_head::Int64     # Unused internal record head
    rfu_c::Int32        # Reserved field C
    leap_second_last_updated::Int32
    rfu_e::Int32        # Reserved field E
    r_dim_sizes::Vector{UInt32}  # Dimension sizes for r-variables
end

"""
Variable Descriptor Record (VDR) - describes a single variable
Can be either r-variable (record variant) or z-variable (zero variant)

See also: [zVDR](@ref)
"""
struct VDR{DT}
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
end

Base.iterate(vdr::VDR, i = 1) = i > fieldcount(typeof(vdr)) ? nothing : (getfield(vdr, i), i + 1)

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

"""
    extract_file_properties(cdr::CDR)

Extract high-level file properties from parsed CDR record.
"""
function extract_file_properties(cdr)
    # Extract version tuple
    version = (cdr.version, cdr.release, cdr.increment)

    # Extract majority from flags (bit 0: 1=row major, 0=column major)
    majority = (cdr.flags & 0x01) != 0 ? Majority(0) : Majority(1)  # Row=0, Column=1
    return (version, majority)
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

function Base.show(io::IO, header::FileHeader)
    println(io, "CDF File Header:")
    println(io, "  Version: $(header.version)")
    println(io, "  Majority: $(header.majority)")
    return println(io, "  Compression: $(header.compression)")
end
