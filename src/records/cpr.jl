# A Compressed Parameters Record (CPR) is used to keep the information as the compression method and level used to create a CDF or variable. This record is pointed to by either a CCR or a VDR. When a compression is applied to the whole CDF, the CPR is pointed to by the CCR. If a compression is only applied to a variable, a CPR is pointed to by a VDR. Currently, only Run-Length Encoding (RLE), Huffman (HUFF), Adaptive Huffman (AHUFF) and GNU GZIP compression algorithms are supported.

struct CPR <: Record
    compression_type::Int32
    rfu_a::RInt32
    parameter_count::Int32
    # parameters::Tuple{Vararg{Int32}}
end

@inline function CPR(buffer::Vector{UInt8}, offset, FieldSizeT)
    pos = check_record_type(11, buffer, offset, FieldSizeT)
    fields, pos = @read_be_fields(buffer, pos, fieldtypes(CPR)...)
    # parameter_count, pos = read_be_i(buffer, pos, Int32)
    # parameters = read_be(buffer, pos, parameter_count, Int32)
    return CPR(fields...)
end
