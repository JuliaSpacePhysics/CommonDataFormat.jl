"""
CDF Descriptor Record (CDR) - the main file header record
Contains version, encoding, format information, and pointer to GDR
"""
struct CDR <: Record
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
    CDR(buffer, pos, RecordSizeType)

Load a CDF Descriptor Record from the IO stream at the specified offset.
This follows the CDF specification for CDR record structure.
"""
@inline function CDR(buffer::Vector{UInt8}, pos, RecordSizeType)
    header = Header(buffer, pos, RecordSizeType)
    @assert header.record_type == 1 "Invalid CDR record type"
    pos += sizeof(RecordSizeType) + 4
    # Read remaining CDR fields in order as per CDF specification
    gdr_offset, pos = read_be_i(buffer, pos, RecordSizeType)
    fields = read_be(buffer, pos, 9, Int32)
    return CDR(header, gdr_offset, fields...)
end
