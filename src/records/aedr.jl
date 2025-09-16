# An Attribute Entry Descriptor Record (AEDR) contains a description of an attribute entry. There are two types of AEDRs: AgrEDRs describing g/rEntries and AzEDRs describing zEntries. The AgrEDRhead field of an ADR contains the file offset of the first AgrEDR for the corresponding attribute. Likewise, the AzEDRhead field of an ADR contains the file offset of the first AzEDR. The linked lists of AEDRs starting at AgrEDRhead and AzEDRhead will contain only AEDRs of that type - AgrEDRs or AzEDRs, respectively. Note that the term g/rEntry is used to refer to an entry that may be either a gEntry or an rEntry. The type of entry described by an AgrEDR depends on the scope of the corresponding attribute. AgrEDRs of a global-scoped attribute describe gEntries. AgrEDRs of a variable-scoped attribute describe rEntries. The scope of an attribute is stored in the Scope field of the corresponding ADR.

"""
    AEDR

Attribute g/r Entry Descriptor Record.
Describes a global entry (for global attributes) or rVariable entry (for variable attributes).
"""
struct AEDR{A}
    header::Header
    AEDRnext::Int64     # Offset to next AEDR in chain
    AttrNum::Int32      # Attribute number
    DataType::Int32     # CDF data type of the entry
    Num::Int32          # Entry number
    NumElems::Int32     # Number of elements in the entry
    NumStrings::Int32   # Number of strings (for string data)
    rfuB::Int32         # Reserved field B
    rfuC::Int32         # Reserved field C
    rfuD::Int32         # Reserved field D
    rfuE::Int32         # Reserved field E
    Value::A            # This consists of the number of elements (specified by the NumElems field) of the data type (specified by the DataType field). This can be thought of as a 1-dimensional array of values (stored contiguously). The size of this field is the product of the number of elements and the size in bytes of each element.
end

@inline function load_aedr_data(buffer::Vector{UInt8}, offset, RecordSizeType, cdf_encoding)
    datatype = read_be(buffer, offset + 25, Int32)
    NumElems = read_be(buffer, offset + 33, Int32)
    T = julia_type(datatype)
    needs_byte_swap = is_big_endian_encoding(cdf_encoding) && T <: Number
    data = load_attribute_data(T, buffer, offset + 57, NumElems, needs_byte_swap)
    return data
end


function load_attribute_data(::Type{T}, buffer::Vector{UInt8}, pos, NumElems, needs_byte_swap) where {T}
    data = Vector{T}(undef, NumElems)
    dst_ptr = pointer(data)
    src_ptr = convert(Ptr{T}, pointer(buffer, pos))
    unsafe_copyto!(dst_ptr, src_ptr, NumElems)
    needs_byte_swap && map!(ntoh, data)
    return data
end

function load_attribute_data(::Type{Char}, buffer::Vector{UInt8}, pos, NumElems, needs_byte_swap)
    return @views String((buffer[pos:(pos + NumElems - 1)]))
end
