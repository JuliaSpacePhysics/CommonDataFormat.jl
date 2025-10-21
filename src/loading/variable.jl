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

"""
    majority_swap!(data, dims_without_record)

Convert row-major data layout to column-major (Julia's native layout) in-place.
For row-major CDF files, this reverses the dimension order (except record dimension).
"""
function majority_swap!(data::AbstractArray{T, N}, dims_without_record) where {T, N}
    N <= 2 && return data
    perm = ntuple(i -> N - i, N - 1)
    reversed_dims = reverse(dims_without_record)
    temp = similar(data, dims_without_record)
    for slc in eachslice(data; dims = N)
        permutedims!(temp, reshape(slc, reversed_dims), perm)
        copyto!(slc, temp)
    end
    return data
end


function variable(cdf::CDFDataset, name)
    vdr = find_vdr(cdf, name)
    isnothing(vdr) && throw(KeyError(name))
    T = julia_type(vdr.data_type, vdr.num_elems)
    dims = (record_sizes(vdr)..., vdr.max_rec + 1)
    N = vdr isa VDR ? vdr.num_dims + 1 : length(dims)
    byte_swap = is_big_endian_encoding(cdf.cdr.encoding)

    return CDFVariable{T, N, typeof(vdr), typeof(cdf)}(
        name, vdr, cdf, dims, byte_swap
    )
end

function DiskArrays.readblock!(var::CDFVariable{T, N}, dest::AbstractArray{T}, ranges::Vararg{AbstractUnitRange{<:Integer}, N}; nbuffers = nthreads()) where {T, N}
    N > 0 && @boundscheck checkbounds(var, ranges...)
    isempty(dest) && return dest

    buffer = parent(var.parentdataset)
    RecordSizeType = recordsize_type(var.parentdataset)
    entries, vvr_type = read_vvrs(var.vdr)
    isempty(entries) && return dest
    compression = if !isempty(entries) #  # vvr records is the ultimative source
        vvr_type == VVR_ ? NoCompression : variable_compression(var.vdr)
    else
        NoCompression
    end

    record_range = ranges[end]
    other_ranges = ranges[1:(N - 1)]
    dims_without_record = var.dims[1:(N - 1)]

    is_full_record = length.(other_ranges) == dims_without_record
    is_no_compression = compression == NoCompression

    first_rec = first(record_range)
    last_rec = last(record_range)
    start_idx = findfirst(entry -> entry.first <= first_rec <= entry.last, entries)
    end_idx = findfirst(entry -> entry.first <= last_rec <= entry.last, entries)
    record_size = prod(dims_without_record)

    is_row_major = majority(var) == Row
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
        is_row_major && majority_swap!(dest, dims_without_record)
    else
        Base.@inbounds Threads.@threads for i in start_idx:end_idx
            entry = entries[i]
            if is_full_record && entry.first >= first_rec && entry.last <= last_rec
                # full entry
                dest_range = dst_src_ranges(first_rec, last_rec, entry)[1]
                dest_view = selectdim(dest, N, dest_range)
                total_elems = record_size * length(entry)
                decompressor = take!(decompressors())
                load_cvvr_data!(dest_view, 1, buffer, entry.offset, total_elems, RecordSizeType, compression; decompressor)
                is_row_major && majority_swap!(dest_view, dims_without_record)
                put!(decompressors(), decompressor)
            else
                # partial entry
                (dest_range, local_range) = dst_src_ranges(first_rec, last_rec, entry)
                dest_view = selectdim(dest, N, dest_range)
                n_records = length(entry)
                total_elems = record_size * n_records
                chunk = Vector{T}(undef, total_elems)

                if is_no_compression
                    load_vvr_data!(chunk, 1, buffer, entry.offset, total_elems, RecordSizeType)
                else
                    decompressor = take!(decompressors())
                    load_cvvr_data!(chunk, 1, buffer, entry.offset, total_elems, RecordSizeType, compression; decompressor)
                    put!(decompressors(), decompressor)
                end

                # chunk_data = _load_entry_chunk(var, entry, RecordSizeType, buffer, var.compression; decompressor)
                chunk_array = reshape(chunk, dims_without_record..., :)
                is_row_major && majority_swap!(chunk_array, dims_without_record)
                src_view = view(chunk_array, other_ranges..., local_range)
                dest_view .= src_view
            end
        end
    end
    var.byte_swap && _btye_swap!(dest)
    return dest
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

function variable_compression(vdr::AbstractVDR{FieldSizeT}) where {FieldSizeT}
    offset_value = Int(vdr.cpr_or_spr_offset)
    if is_compressed(vdr) && offset_value != 0
        buffer = vdr.buffer
        cpr = CPR(buffer, offset_value, FieldSizeT)
        return CompressionType(cpr.compression_type)
    end
    return NoCompression
end
