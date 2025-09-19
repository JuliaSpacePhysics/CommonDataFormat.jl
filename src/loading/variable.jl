function variable(cdf::CDFDataset, name)
    source = parent(cdf)
    RecordSizeType = recordsize_type(cdf)
    vdr = find_vdr(cdf, name)
    isnothing(vdr) && throw(KeyError(name))
    data_type = vdr.data_type
    T = data_type in (CDF_CHAR, CDF_UCHAR) ? StaticString{Int(vdr.num_elems)} : julia_type(data_type)
    dims = Base.size(vdr)::Tuple{Vararg{Int}}
    btye_swap = is_big_endian_encoding(cdf.cdr.encoding)
    compression = variable_compression(source, vdr, RecordSizeType)
    data = load_variable_data(source, vdr.vxr_head, T, dims, RecordSizeType, btye_swap, compression)
    return CDFVariable(name, data, vdr, cdf)
end

struct VVREntry
    RecordType::Int32
    first::Int
    last::Int
    offset::Int
end

@inline Base.length(entry::VVREntry) = entry.last - entry.first + 1

"""
    load_variable_data(source, vxr_head, ::Type{T}, dims, RecordSizeType, btye_swap::Bool, compression::CompressionType)

Load actual data for a variable by following VXR->VVR chain.
"""
function load_variable_data(source, vxr_head, ::Type{T}, dims, ::Type{RecordSizeType}, btye_swap::Bool, compression::CompressionType, nbuffers = nthreads()) where {T, RecordSizeType}
    total_len = prod(dims)
    data = Vector{T}(undef, total_len)
    total_len == 0 && return reshape(data, dims)
    record_size = prod(dims[1:(end - 1)])::Int
    vvrs = read_vvrs(source, Int(vxr_head), RecordSizeType)
    read_variable_data!(data, source, vvrs, compression, record_size, RecordSizeType; nbuffers)
    btye_swap && _btye_swap!(data)
    return reshape(data, dims)
end

function read_variable_data!(data::Vector{T}, source, vvrs, compression, record_size, ::Type{FieldSizeT}; nbuffers = nthreads()) where {T, FieldSizeT}
    pos = 1
    if compression == NoCompression || first(vvrs).RecordType == VVR_ # vvr records is the ultimative source
        for entry in vvrs
            N = min(length(data) - pos + 1, length(entry) * record_size)
            load_vvr_data!(data, pos, source, entry.offset, N, FieldSizeT)
            pos += N
        end
    elseif length(vvrs) == 1
        load_cvvr_data!(data, 1, source, vvrs[1].offset, length(data), FieldSizeT, compression)
        pos = length(data) + 1
    else
        n_ch = min(nbuffers, length(vvrs))
        chnl = Channel{Decompressor}(n_ch)
        foreach(i -> put!(chnl, Decompressor()), 1:n_ch)
        Ns = length.(vvrs) .* record_size
        positions = cumsum([0; Ns])
        Base.@inbounds Threads.@threads for i in eachindex(vvrs)
            decompressor = take!(chnl)
            N = Ns[i]
            load_cvvr_data!(data, positions[i] + 1, source, vvrs[i].offset, N, FieldSizeT, compression; decompressor)
            put!(chnl, decompressor)
        end
        pos = positions[end] + 1
    end
    return @assert pos == length(data) + 1
end


function read_vvrs(src, vxr_head, RecordSizeType)
    entries = Vector{VVREntry}()
    collect_vxr_entries!(entries, src, vxr_head, RecordSizeType)
    return entries
end

function collect_vxr_entries!(entries::Vector{VVREntry}, src::Vector{UInt8}, offset, ::Type{FieldSizeT}) where FieldSizeT
    while offset != 0

        vxr = VXR(src, offset, FieldSizeT)
        for (first, last, offset) in vxr
            leaf_offset = Int(offset)
            record_type = Header(src, leaf_offset + 1, FieldSizeT).record_type
            @assert record_type in (VVR_, CVVR_, VXR_)
            if record_type == VXR_
                collect_vxr_entries!(entries, src, leaf_offset, FieldSizeT)
            else
                push!(entries, VVREntry(record_type, Int(first), Int(last), leaf_offset))
            end
        end
        offset = Int(vxr.vxr_next)
    end
    return entries
end

function variable_compression(buffer::Vector{UInt8}, vdr, RecordSizeType)
    has_compression = (vdr.flags & 0x04) != 0
    offset_value = vdr.cpr_or_spr_offset
    if has_compression && offset_value != 0
        cpr = CPR(buffer, Int(offset_value), RecordSizeType)
        return CompressionType(cpr.compression_type)
    end
    return NoCompression
end
