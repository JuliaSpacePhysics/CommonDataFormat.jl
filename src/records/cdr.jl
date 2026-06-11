"""
CDF Descriptor Record (CDR) - the main file header record
Contains version, encoding, format information, and pointer to GDR
"""
struct CDR{FST} <: Record
    # header::Header
    gdr_offset::FST   # Can be UInt32 for v2, UInt64 for v3
    version::Int32
    release::Int32
    encoding::Int32
    flags::Int32
    rfu_a::RInt32       # Reserved field A
    rfu_b::RInt32       # Reserved field B
    increment::Int32
    identifier::Int32
    # rfu_e::RInt32       # Reserved field E
    # Note: copyright string follows but we'll handle it separately
end

version(cdr::CDR; verbose = true) = verbose ? (cdr.version, cdr.release, cdr.increment) : cdr.version
majority(cdr::CDR) = (cdr.flags & 0x01) != 0 ? Row : Column  # Row=0, Column=1
is_cdf_v3(cdr::CDR) = cdr.version == 3

@inline function CDR{FST}(buffer::Vector{UInt8}, offset) where {FST}
    pos = check_record_type(1, buffer, offset, FST)
    fields, pos = read_be_fields(buffer, pos, CDR{FST}, Val(1:9))
    return CDR(fields...)
end
