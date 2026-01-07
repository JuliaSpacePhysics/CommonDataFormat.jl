"""
Global Descriptor Record (GDR) - contains global information about the CDF file
Points to variable and attribute descriptor records
"""
struct GDR{FS}
    # header::Header
    rVDRhead::FS    # Offset to first r-variable descriptor record
    zVDRhead::FS    # Offset to first z-variable descriptor record
    ADRhead::FS     # Offset to first attribute descriptor record
    eof::FS          # End of file offset
    NrVars::Int32      # Number of r-variables
    num_attr::Int32     # Number of attributes
    r_max_rec::Int32    # Maximum record number for r-variables
    r_num_dims::Int32   # Number of dimensions for r-variables
    NzVars::Int32      # Number of z-variables
    # uir_head::Int64     # Unused internal record head
    # rfu_c::Int32        # Reserved field C
    # leap_second_last_updated::Int32
    # rfu_e::Int32        # Reserved field E
    pos::Int
    # r_dim_sizes::Vector{Int32}  # Dimension sizes for r-variables
end


"""
    GDR(buffer::Vector{UInt8}, pos, FieldSizeT)

Load a Global Descriptor Record from the buffer at the specified offset.
"""
@inline function GDR(buffer::Vector{UInt8}, offset, FieldSizeT)
    pos = check_record_type(2, buffer, offset, FieldSizeT)
    fields, pos = read_be_fields(buffer, pos, GDR{FieldSizeT}, Val(1:9))
    return GDR(fields..., pos)
end

function r_dim_sizes(gdr::GDR, buffer::Vector{UInt8})
    pos = gdr.pos + sizeof(Int64) + sizeof(Int32) + sizeof(Int32) + sizeof(Int32)
    r_num_dims = gdr.r_num_dims
    @assert r_num_dims >= 0
    return read_be(buffer, pos, r_num_dims, Int32)
end