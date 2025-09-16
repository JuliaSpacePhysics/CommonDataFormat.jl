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
    GDR(io::IO, RecordSizeType)

Load a Global Descriptor Record from the IO stream at the specified offset.
"""
@inline function GDR(io::IO, RecordSizeType)
    # Read header
    header = Header(io, RecordSizeType)
    @assert header.record_type == 2

    # Read GDR fields
    rvdr_head, zvdr_head, adr_head, eof = read_be(io, 4, RecordSizeType)
    nr_vars, num_attr, r_max_rec, r_num_dims, nz_vars = read_be(io, 5, Int32)
    uir_head = read_be(io, Int64)
    rfu_c, leap_second_last_updated, rfu_e = read_be(io, 3, Int32)
    # Read dimension sizes array
    r_dim_sizes = map(i -> read_uint32_be(io), 1:r_num_dims)

    return GDR(
        header, rvdr_head, zvdr_head, adr_head, eof, nr_vars, num_attr,
        r_max_rec, r_num_dims, nz_vars, uir_head, rfu_c,
        leap_second_last_updated, rfu_e, r_dim_sizes
    )
end