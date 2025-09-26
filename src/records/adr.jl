"""
Attribute Descriptor Record (ADR)

Contains a description of an attribute in a CDF. There will be one ADR per attribute. The ADRhead field of the ADR contains the file offset of the first ADR.
"""
struct ADR{FSZ, S} <: Record
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
    Name::S
end

is_global(adr) = adr.Scope == 1


"""
    ADR(buf, offset, RecordSizeType)

Load an Attribute Descriptor Record from the buffer at the specified position.
"""
@inline function ADR(buffer::Vector{UInt8}, offset, RecordSizeType)
    pos = check_record_type(4, buffer, offset, RecordSizeType)
    # Read ADR fields
    fields, pos = read_be_fields(buffer, pos, ADR{RecordSizeType, String}, Val(1:11))
    name = readname(buffer, pos)
    return ADR(fields..., name)
end
