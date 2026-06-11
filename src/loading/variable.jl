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
    return _variable(cdf, name, vdr)
end

# Branch over dimension count so each leaf builds dims tuple at compile time statically
function _variable(cdf, name, vdr)
    M = num_record_dims(vdr)
    return Base.Cartesian.@nif 12 d -> (M == d - 1) d -> (
        d == 12 ? throw(ArgumentError("variable has $M dimensions; the CDF format allows at most 10")) :
            _variable(cdf, name, vdr, Val(d - 1))
    )
end

function _variable(cdf, name, vdr, ::Val{M}) where {M}
    dims = (map(Int, record_sizes(vdr, Val(M)))..., Int(vdr.max_rec) + 1)
    code = Int(vdr.data_type)
    if code == 51 || code == 52 # CHAR/UCHAR: eltype depends on runtime num_elems
        T = StaticString{Int(vdr.num_elems), UInt8}
        return CDFVariable{T, M + 1, typeof(vdr), typeof(cdf)}(name, vdr, cdf, dims)
    end
    # Branch to static constructor per element type
    return Base.Cartesian.@nif(
        16,
        d -> code == CODE_TYPE_PAIRS[d][1],
        d -> _construct(cdf, name, vdr, dims, CODE_TYPE_PAIRS[d][2]),
        d -> throw(ArgumentError("unsupported CDF data type $code"))
    )
end

@inline _construct(cdf, name, vdr, dims::NTuple{N, Int}, ::Type{T}) where {N, T} =
    CDFVariable{T, N, typeof(vdr), typeof(cdf)}(name, vdr, cdf, dims)

"""
    read!(ds::CDFDataset, name, dest::AbstractArray{T, N}) -> dest

Read the full contents of variable `name` into the preallocated `dest`.
"""
function Base.read!(ds::CDFDataset, name::String, dest::AbstractArray{T, N}) where {T, N}
    vdr = find_vdr(ds, name)
    isnothing(vdr) && throw(KeyError(name))
    return _read_full!(dest, ds, name, vdr)
end

"""
    read(ds::CDFDataset, name, ::Type{Array{T, N}}) -> Array{T, N}

Allocating variant of [`read!`](@ref): read the full contents of variable `name` into a
freshly allocated `Array{T, N}`.
"""
function Base.read(ds::CDFDataset, name::String, ::Type{Array{T, N}}) where {T, N}
    vdr = find_vdr(ds, name)
    isnothing(vdr) && throw(KeyError(name))
    dims = (map(Int, record_sizes(vdr, Val(N - 1)))..., Int(vdr.max_rec) + 1)
    return _read_full!(Array{T, N}(undef, dims), ds, name, vdr)
end

function _read_full!(dest::AbstractArray{T, N}, ds, name, vdr) where {T, N}
    Base.require_one_based_indexing(dest)
    Tfile = julia_type(vdr.data_type, vdr.num_elems)
    T === Tfile || throw(ArgumentError("element type mismatch for \"$name\": file has $Tfile, destination has $T"))
    dims = (map(Int, record_sizes(vdr, Val(N - 1)))..., Int(vdr.max_rec) + 1)
    size(dest) == dims || throw(DimensionMismatch("variable \"$name\" has size $dims, destination has size $(size(dest))"))
    var = CDFVariable{T, N, typeof(vdr), typeof(ds)}(name, vdr, ds, dims)
    DiskArrays.readblock!(var, dest, axes(dest)...)
    return dest
end

@inline _record_view(A::AbstractArray{<:Any, M}, r) where {M} =
    view(A, ntuple(_ -> Colon(), M - 1)..., r)

function DiskArrays.readblock!(var::CDFVariable{T, N}, dest::AbstractArray{T}, ranges::Vararg{AbstractUnitRange{<:Integer}, N}; nbuffers = nthreads()) where {T, N}
    N > 0 && @boundscheck checkbounds(var, ranges...)
    isempty(dest) && return dest

    buffer = parent(var.parentdataset)
    RecordSizeType = recordsize_type(var.parentdataset)
    entries, vvr_type = read_vvrs(var.vdr)
    # vvr record type is the ultimate source of compression
    compression = vvr_type == VVR_ ? NoCompression : variable_compression(var.vdr)
    sparse_type(var.vdr) == 0 ||
        return _readblock_sparse!(var, dest, ranges, entries, compression, buffer, RecordSizeType)
    isempty(entries) && return dest

    record_range = ranges[end]
    other_ranges = ranges[1:(N - 1)]
    dims_without_record = var.dims[1:(N - 1)]

    is_full_record = length.(other_ranges) == dims_without_record
    is_no_compression = compression == NoCompression

    first_rec = first(record_range)
    last_rec = last(record_range)
    start_idx = findfirst(entry -> entry.first <= first_rec <= entry.last, entries)::Int
    end_idx = findfirst(entry -> entry.first <= last_rec <= entry.last, entries)::Int
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
                dest_view = _record_view(dest, dest_range)
                total_elems = record_size * length(entry)
                decompressor = take!(decompressors())
                load_cvvr_data!(dest_view, 1, buffer, entry.offset, total_elems, RecordSizeType, compression; decompressor)
                is_row_major && majority_swap!(dest_view, dims_without_record)
                put!(decompressors(), decompressor)
            else
                # partial entry
                (dest_range, local_range) = dst_src_ranges(first_rec, last_rec, entry)
                dest_view = _record_view(dest, dest_range)
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
    is_big_endian_encoding(var) && _byte_swap!(dest)
    return dest
end

# Sparse records: records absent from the VXR are virtual. Pad sparse (1) fills them
# with the VDR pad value (or the NASA default pad); previous sparse (2) repeats the
# last record of the preceding physical block.
# Mirrors cdflib semantics; spec'd in the CDF IFD (sRecords).
function _readblock_sparse!(var::CDFVariable{T, N}, dest, ranges, entries, compression, buffer, ::Type{RST}) where {T, N, RST}
    record_range = ranges[end]
    other_ranges = ranges[1:(N - 1)]
    dims_without_record = var.dims[1:(N - 1)]
    record_size = prod(dims_without_record)
    is_row_major = majority(var) == Row
    needs_byte_swap = is_big_endian_encoding(var)
    use_prev = sparse_type(var.vdr) == 2
    pad = pad_value(var.vdr, T, needs_byte_swap)

    chunk = Vector{T}()
    cached = 0
    # load (and permute, for row-major) a physical block once; runs of records from
    # the same block (incl. prev-sparse repeats) reuse it
    load_block = function (idx)
        entry = entries[idx]
        if cached != idx
            resize!(chunk, record_size * length(entry))
            if compression == NoCompression
                load_vvr_data!(chunk, 1, buffer, entry.offset, length(chunk), RST)
            else
                decompressor = take!(decompressors())
                try
                    load_cvvr_data!(chunk, 1, buffer, entry.offset, length(chunk), RST, compression; decompressor)
                finally
                    put!(decompressors(), decompressor)
                end
            end
            is_row_major && majority_swap!(reshape(chunk, dims_without_record..., :), dims_without_record)
            cached = idx
        end
        return reshape(chunk, dims_without_record..., :)
    end

    blk = 1
    nblocks = length(entries)
    for (di, r) in enumerate(record_range)
        while blk <= nblocks && entries[blk].last < r
            blk += 1
        end
        dest_view = _record_view(dest, di)
        if blk <= nblocks && entries[blk].first <= r
            arr = load_block(blk)
            dest_view .= view(arr, other_ranges..., r - entries[blk].first + 1)
        elseif use_prev && blk > 1
            arr = load_block(blk - 1)
            dest_view .= view(arr, other_ranges..., size(arr, N))
        else
            fill!(dest_view, pad)
        end
    end
    needs_byte_swap && _byte_swap!(dest)
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
