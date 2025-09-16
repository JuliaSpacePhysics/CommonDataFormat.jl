"""
Attribute Descriptor Record (ADR)

Contains a description of an attribute in a CDF. There will be one ADR per attribute. The ADRhead field of the ADR contains the file offset of the first ADR.
"""
struct ADR{S} <: Record
    header::Header
    ADRnext::Int64    # Offset to next ADR in chain
    AgrEDRhead::Int64    # The offset of the first Attribute g/rEntry Descriptor Record (AgrEDR) for this attribute.
    Scope::Int32     # 1 = global, 2 = variable
    Num::Int32          # Attribute number
    NgrEntries::Int32      # Number of r-variables
    MAXgrEntry::Int32     # Number of attributes
    rfuA::Int32        # Reserved field A
    AzEDRhead::Int64   # The offset of the first Attribute zEntry Descriptor Record (AzEDR) for this attribute.
    NzEntries::Int32      # Number of z-variables
    MAXzEntry::Int32     # Number of z-entries
    rfuE::Int32        # Reserved field E
    Name::S
end

is_global(adr) = adr.Scope == 1


"""
    ADR(io::IO, RecordSizeType)

Load an Attribute Descriptor Record from the IO stream at the specified offset.
"""
@inline function ADR(io::IO, RecordSizeType)
    # Read header
    header = Header(io, RecordSizeType)
    @assert header.record_type == 4

    # Read ADR fields
    ADRnext = read_be(io, Int64)
    AgrEDRhead = read_be(io, Int64)
    fields1 = read_be(io, 5, Int32)
    AzEDRhead = read_be(io, Int64)
    fields2 = read_be(io, 3, Int32)
    name = readname(io)

    return ADR(
        header, ADRnext, AgrEDRhead, fields1..., AzEDRhead, fields2..., name
    )
end

"""
    ADR(buf, pos, RecordSizeType)

Load an Attribute Descriptor Record from the buffer at the specified position.
"""
@inline function ADR(buffer::Vector{UInt8}, offset, RecordSizeType)
    pos = offset + 1
    header = Header(buffer, pos, RecordSizeType)
    @assert header.record_type == 4
    pos += sizeof(RecordSizeType) + 4

    # Read ADR fields
    ADRnext, pos = read_be_i(buffer, pos, Int64)
    AgrEDRhead, pos = read_be_i(buffer, pos, Int64)
    fields1, pos = read_be_i(buffer, pos, 5, Int32)
    AzEDRhead, pos = read_be_i(buffer, pos, Int64)
    fields2, pos = read_be_i(buffer, pos, 3, Int32)
    name = readname(buffer, pos)
    return ADR(
        header, ADRnext, AgrEDRhead, fields1..., AzEDRhead, fields2..., name
    )
end
