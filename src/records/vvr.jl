function _copy_to!(dest, doffs, src, soffs, N)
    T = eltype(dest)
    GC.@preserve dest src begin
        src_ptr = convert(Ptr{T}, pointer(src, soffs))
        dst_ptr = pointer(dest, doffs)
        unsafe_copyto!(dst_ptr, src_ptr, N)
    end
end

function load_vvr_data!(data::Vector{T}, pos, src::Vector{UInt8}, offset, N, ::Type{RecordSizeType}) where {T, RecordSizeType}
    src_start = offset + 1 + sizeof(RecordSizeType) + sizeof(Int32)
    _copy_to!(data, pos, src, src_start, N)
    return
end
