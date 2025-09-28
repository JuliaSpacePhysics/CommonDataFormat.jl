@static if isdefined(Base, :OncePerProcess)
    const decompressors = Base.OncePerProcess{Channel{Decompressor}}() do
        n_ch = nthreads()
        chnl = Channel{Decompressor}(n_ch)
        foreach(i -> put!(chnl, Decompressor()), 1:n_ch)
        return chnl
    end
else
    const _decompressors = Ref{Union{Channel{Decompressor}, Nothing}}(nothing)
    function decompressors()
        if _decompressors[] === nothing
            n_ch = nthreads()
            chnl = Channel{Decompressor}(n_ch)
            foreach(i -> put!(chnl, Decompressor()), 1:n_ch)
            _decompressors[] = chnl
        end
        return _decompressors[]
    end
end


function variable(cdf::CDFDataset, name)
    source = parent(cdf)
    FieldSizeT = recordsize_type(cdf)
    vdr = find_vdr(cdf, name)
    isnothing(vdr) && throw(KeyError(name))
    T = julia_type(vdr.data_type, vdr.num_elems)
    record_dims = vdr.z_dim_sizes
    dims = Int.((record_dims..., vdr.max_rec + 1))
    N = length(dims)
    record_size = prod(record_dims)
    vvrs, vvr_type = read_vvrs(source, vdr, FieldSizeT)
    compression = if !isempty(vvrs) #  # vvr records is the ultimative source
        vvr_type == VVR_ ? NoCompression : variable_compression(source, vdr, FieldSizeT)
    else
        NoCompression
    end
    byte_swap = is_big_endian_encoding(cdf.cdr.encoding)

    return CDFVariable{T, N, typeof(vdr), typeof(cdf)}(
        name,
        vdr, cdf,
        dims, record_size,
        vvrs,
        compression,
        byte_swap,
    )
end

function DiskArrays.readblock!(var::CDFVariable{T, N}, dest::AbstractArray{T}, ranges::Vararg{AbstractUnitRange{<:Integer}, N}; nbuffers = nthreads()) where {T, N}
    N > 0 && @boundscheck checkbounds(var, ranges...)
    isempty(dest) && return dest

    buffer = parent(var.parentdataset)
    RecordSizeType = recordsize_type(var.parentdataset)
    entries = var.vvrs
    isempty(entries) && return dest

    record_range = ranges[end]
    other_ranges = ranges[1:(N - 1)]
    dims_without_record = var.dims[1:(N - 1)]

    is_full_record = length.(other_ranges) == dims_without_record
    is_no_compression = var.compression == NoCompression

    first_rec = first(record_range)
    last_rec = last(record_range)
    start_idx = findfirst(entry -> entry.first <= first_rec <= entry.last, entries)
    end_idx = findfirst(entry -> entry.first <= last_rec <= entry.last, entries)
    record_size = var.record_size

    # If the variable is not compressed and the other dimension ranges are the same as the variable range
    # we can directly read the data into dest
    if is_no_compression && is_full_record
        record_bytes = record_size * sizeof(T)
        doffs = 1
        header_skip = sizeof(RecordSizeType) + sizeof(Int32)
        for i in start_idx:end_idx
            entry = entries[i]
            overlap_first = max(first_rec, entry.first)
            overlap_last = min(last_rec, entry.last)
            N_elems = (overlap_last - overlap_first + 1) * record_size
            data_start = entry.offset + 1 + header_skip
            byte_offset = data_start + (overlap_first - entry.first) * record_bytes
            _copy_to!(dest, doffs, buffer, byte_offset, N_elems)
            doffs += N_elems
        end
        @assert doffs == length(dest) + 1
    else
        Base.@inbounds Threads.@threads for i in eachindex(start_idx:end_idx)
            entry = entries[i]
            decompressor = take!(decompressors())
            if is_full_record && entry.first >= first_rec && entry.last <= last_rec
                # full entry
                dest_range = dst_src_ranges(first_rec, last_rec, entry)[1]
                dest_view = selectdim(dest, N, dest_range)
                total_elems = record_size * length(entry)
                load_cvvr_data!(dest_view, 1, buffer, entry.offset, total_elems, RecordSizeType, var.compression; decompressor)
            else
                # partial entry
                (dest_range, local_range) = dst_src_ranges(first_rec, last_rec, entry)
                dest_view = selectdim(dest, N, dest_range)
                n_records = length(entry)
                total_elems = record_size * n_records
                chunk_data = _load_entry_chunk(var, entry, RecordSizeType, buffer; decompressor)
                chunk_array = reshape(chunk_data, dims_without_record..., :)
                src_view = view(chunk_array, other_ranges..., local_range)
                dest_view .= src_view
            end
            put!(decompressors(), decompressor)
        end
    end
    var.byte_swap && _btye_swap!(dest)
    return dest
end

function _load_entry_chunk(var::CDFVariable{T}, entry::VVREntry, RecordSizeType, buffer; decompressor) where {T}
    n_records = entry.last - entry.first + 1
    total_elems = n_records * var.record_size
    chunk = Vector{T}(undef, total_elems)
    total_elems == 0 && return chunk
    if var.compression == NoCompression
        load_vvr_data!(chunk, 1, buffer, entry.offset, total_elems, RecordSizeType)
    else
        load_cvvr_data!(chunk, 1, buffer, entry.offset, total_elems, RecordSizeType, var.compression; decompressor)
    end
    return chunk
end

function read_vvrs(src, vdr, ::Type{FieldSizeT}) where {FieldSizeT}
    vxr_head = vdr.vxr_head
    entries = Vector{VVREntry}()
    sizehint!(entries, 1)
    vvr_type = collect_vxr_entries!(entries, src, Int(vxr_head), FieldSizeT)
    vvr_type = @something vvr_type VVR_
    return entries, vvr_type
end

function collect_vxr_entries!(entries::Vector{VVREntry}, src, offset, ::Type{FieldSizeT}) where {FieldSizeT}
    vvr_type = nothing
    while offset != 0
        vxr = VXR(src, offset, FieldSizeT)
        for (first, last, leaf_offset) in vxr
            record_type = get_record_type(src, leaf_offset, FieldSizeT)
            @assert record_type in (VVR_, CVVR_, VXR_)
            if record_type == VXR_
                vvr_type = collect_vxr_entries!(entries, src, leaf_offset, FieldSizeT)
            else
                push!(entries, VVREntry(Int(first) + 1, Int(last) + 1, leaf_offset))
                vvr_type = record_type
            end
        end
        offset = vxr.vxr_next
    end
    return vvr_type
end

function variable_compression(buffer::Vector{UInt8}, vdr, RecordSizeType)
    offset_value = Int(vdr.cpr_or_spr_offset)
    if is_compressed(vdr) && offset_value != 0
        cpr = CPR(buffer, offset_value, RecordSizeType)
        return CompressionType(cpr.compression_type)
    end
    return NoCompression
end
