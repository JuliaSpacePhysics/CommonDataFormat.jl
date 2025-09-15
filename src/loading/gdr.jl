"""
    load_gdr(io::IO, offset::UInt64, is_v3::Bool) -> GDR

Load a Global Descriptor Record from the IO stream at the specified offset.
"""
@inline function load_gdr(io::IO, offset::UInt64, RecordSizeType)
    seek(io, offset)
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