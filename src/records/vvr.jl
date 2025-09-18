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

@inline function load_vvr_data!(data, io::IO, offset, RecordSizeType, btye_swap::Bool)
    seek(io, offset)
    header = Header(io, RecordSizeType)
    @assert header.record_type == 7 "Invalid VVR record type"
    # Read all available data in this VVR
    read!(io, data)
    btye_swap && _btye_swap!(data)
    return
end

function load_vvr_data!(data, buffer::Vector{UInt8}, offset, RecordSizeType, btye_swap::Bool; check = false)
    pos = offset + 1
    check && @assert Header(buffer, pos, RecordSizeType).record_type == 7 "Invalid VVR record type"
    pos += sizeof(RecordSizeType) + sizeof(Int32)
    T = eltype(data)
    src_ptr = convert(Ptr{T}, pointer(buffer, pos))
    dst_ptr = pointer(data)
    N = length(data)
    unsafe_copyto!(dst_ptr, src_ptr, N)
    btye_swap && _btye_swap!(data)
    return
end
