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
    r_dim_sizes::Tuple{Vararg{UInt32}}  # Dimension sizes for r-variables
end


"""
    GDR(buffer::Vector{UInt8}, pos, RecordSizeType)

Load a Global Descriptor Record from the buffer at the specified offset.
"""
@inline function GDR(buffer::Vector{UInt8}, pos, RecordSizeType)
    # Read header
    header = Header(buffer, pos, RecordSizeType)
    @assert header.record_type == 2
    pos += sizeof(RecordSizeType) + 4

    # Read GDR fields
    fields1, pos = read_be_i(buffer, pos, 4, RecordSizeType)
    (nr_vars, num_attr, r_max_rec, r_num_dims, nz_vars), pos = read_be_i(buffer, pos, 5, Int32)
    uir_head, pos = read_be_i(buffer, pos, Int64)
    fields3, pos = read_be_i(buffer, pos, 3, Int32)
    # Read dimension sizes array
    r_dim_sizes = read_be(buffer, pos, r_num_dims, UInt32)
    return GDR(
        header, fields1..., nr_vars, num_attr,
        r_max_rec, r_num_dims, nz_vars, uir_head, fields3...,
        r_dim_sizes
    )
end
