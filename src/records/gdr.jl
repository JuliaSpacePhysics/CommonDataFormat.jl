"""
Global Descriptor Record (GDR) - contains global information about the CDF file
Points to variable and attribute descriptor records
"""
struct GDR
    # header::Header
    rVDRhead::Int64    # Offset to first r-variable descriptor record
    zVDRhead::Int64    # Offset to first z-variable descriptor record
    ADRhead::Int64     # Offset to first attribute descriptor record
    eof::Int64          # End of file offset
    NrVars::Int32      # Number of r-variables
    num_attr::Int32     # Number of attributes
    r_max_rec::Int32    # Maximum record number for r-variables
    r_num_dims::Int32   # Number of dimensions for r-variables
    NzVars::Int32      # Number of z-variables
    # uir_head::Int64     # Unused internal record head
    # rfu_c::Int32        # Reserved field C
    # leap_second_last_updated::Int32
    # rfu_e::Int32        # Reserved field E
    # r_dim_sizes::Tuple{Vararg{Int32}}  # Dimension sizes for r-variables
end


"""
    GDR(buffer::Vector{UInt8}, pos, FieldSizeT)

Load a Global Descriptor Record from the buffer at the specified offset.
"""
@inline function GDR(buffer::Vector{UInt8}, offset, FieldSizeT)
    pos = check_record_type(2, buffer, offset, FieldSizeT)
    fields, pos = @read_be_fields(buffer, pos, fieldtypes(GDR)...)
    # r_num_dims = fields[8]
    # r_dim_sizes = read_be(buffer, pos, r_num_dims, Int32)
    return GDR(fields...)
end
