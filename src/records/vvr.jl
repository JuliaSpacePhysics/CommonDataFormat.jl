# Variable data loading functionality
# Handles VVR (Variable Value Record) parsing and data extraction

"""
Variable Value Record (VVR) - contains actual variable data
"""
struct VVR{T}
    header::Header
    data::Vector{T}     # Raw variable data
end

@inline function VVR(buffer::Vector{UInt8}, offset, RecordSizeType, data)
    pos = offset + 1
    header = Header(buffer, pos, RecordSizeType)
    @assert header.record_type == 7 "Invalid VVR record type"
    return VVR(header, data)
end

function _copy_to!(dest, doffs, src, soffs, N)
    T = eltype(dest)
    GC.@preserve dest src begin
        src_ptr = convert(Ptr{T}, pointer(src, soffs))
        dst_ptr = pointer(dest, doffs)
        unsafe_copyto!(dst_ptr, src_ptr, N)
    end
end

function load_vvr_data!(data::Vector{T}, pos, src::Vector{UInt8}, offset, N, RecordSizeType) where {T}
    src_start = offset + 1 + sizeof(RecordSizeType) + sizeof(Int32)
    _copy_to!(data, pos, src, src_start, N)
    return
end
