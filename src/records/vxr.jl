"""
Variable Index Record (VXR) - contains pointers to variable data records
"""
struct VXR{FieldSizeT}
    # header::Header
    vxr_next::FieldSizeT       # Next VXR in chain
    n_entries::Int32       # Number of entries
    n_used_entries::Int32  # Number of used entries
    pointer::Ptr{Int32}
    # first::Tuple{Vararg{Int32}}   # First record numbers , Unused entries in this array contain 0xFFFFFFFF.
    # last::Tuple{Vararg{Int32}}    # Last record numbers, Unused entries in this array contain 0xFFFFFFFF.
    # offset::Tuple{Vararg{Int64}}  # Offsets to VVR/CVVR records
end


"""
    VXR(source, offset, RecordSizeType)

Load a Variable Index Record from the source at the specified offset.
"""
function VXR(source::Vector{UInt8}, offset, FieldSizeT)
    pos = check_record_type(6, source, offset, FieldSizeT)
    vxr_next, pos = read_be_i(source, pos, FieldSizeT)
    n_entries, pos = read_be_i(source, pos, Int32)
    n_used_entries, pos = read_be_i(source, pos, Int32)
    p = convert(Ptr{Int32}, pointer(source, pos))
    return VXR(vxr_next, n_entries, n_used_entries, p)
end

function Base.iterate(vxr::VXR{FieldSizeT}, state = 1) where {FieldSizeT}
    state > vxr.n_used_entries && return nothing
    pointer = vxr.pointer
    first = read_be(pointer, state)
    last = read_be(pointer, state + vxr.n_entries)
    offset_pointer = convert(Ptr{FieldSizeT}, pointer + (2 * vxr.n_entries) * sizeof(Int32))
    offset = read_be(offset_pointer, state)
    return ((first, last, Int(offset)), state + 1)
end