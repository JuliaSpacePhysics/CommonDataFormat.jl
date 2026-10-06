"""
Attribute Descriptor Record (ADR)

Contains a description of an attribute in a CDF. There will be one ADR per attribute. The ADRhead field of the ADR contains the file offset of the first ADR.
"""
struct ADR{FSZ} <: Record
    # header::Header
    ADRnext::FSZ    # Offset to next ADR in chain
    AgrEDRhead::FSZ    # The offset of the first Attribute g/rEntry Descriptor Record (AgrEDR) for this attribute.
    Scope::Int32     # 1 = global, 2 = variable
    Num::Int32          # Attribute number
    NgrEntries::Int32      # Number of r-variables
    MAXgrEntry::Int32     # Number of attributes
    rfuA::RInt32        # Reserved field A
    AzEDRhead::FSZ   # The offset of the first Attribute zEntry Descriptor Record (AzEDR) for this attribute.
    NzEntries::Int32      # Number of z-variables
    MAXzEntry::Int32     # Number of z-entries
    rfuE::RInt32        # Reserved field E
    name_pos::Int       # Name is read on demand (`adr_name`); lookups only compare it in place
end

is_global(adr) = adr.Scope == 1
# Scope, read without parsing the rest of the ADR: header + ADRnext + AgrEDRhead
is_global(buffer, offset, ::Type{FST}) where {FST} = read_be(buffer, offset + 3 * sizeof(FST) + 5, Int32) == 1
_adr_name_pos(offset, ::Type{FST}) where {FST} = offset + 37 + 4 * sizeof(FST)


@inline function ADR{FST}(buffer::Vector{UInt8}, offset) where {FST}
    pos = check_record_type(4, buffer, offset, FST)
    # Read ADR fields
    fields, pos = read_be_fields(buffer, pos, ADR{FST}, Val(1:11))
    return ADR{FST}(fields..., pos)
end

adr_name(buffer, adr::ADR{FST}) where {FST} = String(readname(buffer, adr.name_pos, FST))
