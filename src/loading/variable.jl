# ---- Type-erased block moves: dims/strides are runtime vectors ----
# Element movers, chosen once per block by element size; `ByteMove` covers odd sizes (CHAR data).
struct WordMove{U} end
struct ByteMove end
@inline (::WordMove{U})(d::Ptr{UInt8}, s::Ptr{UInt8}, ::Int) where {U} = unsafe_store!(Ptr{U}(d), unsafe_load(Ptr{U}(s)))
@inline (::ByteMove)(d::Ptr{UInt8}, s::Ptr{UInt8}, esz::Int) = unsafe_copyto!(d, s, esz)

# Gather a column-major block of `dims` elements (`esz` bytes each) whose source byte
# strides are `sstrides` into contiguous `dst`.
function _copy_block!(dst::Ptr{UInt8}, src::Ptr{UInt8}, esz::Int, dims::Vector{Int}, sstrides::Vector{Int})
    esz == 8 && return _copy_block!(dst, src, esz, dims, sstrides, WordMove{UInt64}())
    esz == 4 && return _copy_block!(dst, src, esz, dims, sstrides, WordMove{UInt32}())
    esz == 2 && return _copy_block!(dst, src, esz, dims, sstrides, WordMove{UInt16}())
    esz == 1 && return _copy_block!(dst, src, esz, dims, sstrides, WordMove{UInt8}())
    esz == 16 && return _copy_block!(dst, src, esz, dims, sstrides, WordMove{UInt128}())
    return _copy_block!(dst, src, esz, dims, sstrides, ByteMove())
end

function _copy_block!(dst::Ptr{UInt8}, src::Ptr{UInt8}, esz::Int, dims::Vector{Int}, sstrides::Vector{Int}, move)
    n = length(dims)
    n0 = dims[1]
    s0 = sstrides[1]
    run_bytes = n0 * esz
    memcpy_run = s0 == esz && run_bytes > 64  # a memmove call per short run costs more than it saves
    nruns = 1
    for k in 2:n
        nruns *= dims[k]
    end
    idx = zeros(Int, n)
    soff = 0
    doff = 0
    for _ in 1:nruns
        if memcpy_run
            unsafe_copyto!(dst + doff, src + soff, run_bytes)
        else
            for i in 0:(n0-1)
                move(dst + doff + i * esz, src + soff + i * s0, esz)
            end
        end
        doff += run_bytes
        k = 2
        while k <= n
            idx[k] += 1
            soff += sstrides[k]
            idx[k] < dims[k] && break
            soff -= dims[k] * sstrides[k]
            idx[k] = 0
            k += 1
        end
    end
    return
end

# Row-major records → column-major in place. Each record of `rdims` is stored in
# `reverse(rdims)` order; swapped through a bounded temp, a chunk of records at a time.
function _majority_swap!(data::Ptr{UInt8}, esz::Int, rdims::Vector{Int}, nrec::Int)
    k = length(rdims)
    k <= 1 && return
    record_bytes = prod(rdims) * esz
    sstrides = Vector{Int}(undef, k + 1)
    s = esz
    for i in k:-1:1
        sstrides[i] = s
        s *= rdims[i]
    end
    sstrides[k+1] = record_bytes
    chunk = clamp((1 << 20) ÷ record_bytes, 1, nrec)
    dims = [rdims; chunk]
    temp = Vector{UInt8}(undef, chunk * record_bytes)
    GC.@preserve temp for r0 in 0:chunk:(nrec-1)
        n = min(chunk, nrec - r0)
        dims[end] = n
        base = data + r0 * record_bytes
        _copy_block!(pointer(temp), base, esz, dims, sstrides)
        unsafe_copyto!(base, pointer(temp), n * record_bytes)
    end
    return
end

# Extract `ranges` of the record dims (all records) from contiguous column-major `src`.
function _copy_subblock!(dst::Ptr{UInt8}, src::Ptr{UInt8}, esz::Int, rdims::Vector{Int}, ranges::Vector{UnitRange{Int}}, nrec::Int)
    k = length(rdims)
    sstrides = Vector{Int}(undef, k + 1)
    s = esz
    off = 0
    for i in 1:k
        sstrides[i] = s
        off += (first(ranges[i]) - 1) * s
        s *= rdims[i]
    end
    sstrides[k+1] = s
    dims = [length.(ranges); nrec]
    _copy_block!(dst, src + off, esz, dims, sstrides)
    return
end

function DiskArrays.readblock!(var::CDFVariable{T,N}, dest::AbstractArray{T}, ranges::Vararg{AbstractUnitRange{<:Integer},N}) where {T,N}
    N > 0 && @boundscheck checkbounds(var, ranges...)
    isempty(dest) && return dest
    if !(dest isa Array)
        copyto!(dest, DiskArrays.readblock!(var, Array{T}(undef, size(dest)), ranges...))
        return dest
    end
    rdims = Int[Base.front(var.dims)...]
    other_ranges = UnitRange{Int}[Int(first(r)):Int(last(r)) for r in Base.front(ranges)]
    rec_range = Int(first(ranges[end])):Int(last(ranges[end]))
    GC.@preserve dest _readblock!(Ptr{UInt8}(pointer(dest)), sizeof(T), rdims, other_ranges, rec_range, var.vdr, var.parentdataset)
    is_big_endian_encoding(var) && _byte_swap!(dest)
    return dest
end

function _readblock!(dest::Ptr{UInt8}, esz::Int, rdims::Vector{Int}, other_ranges::Vector{UnitRange{Int}}, rec_range::UnitRange{Int}, vdr, ds)
    entries = read_vvrs(vdr, ds)
    isempty(entries) && return
    compression = any(e -> e.compressed, entries) ? variable_compression(vdr, ds) : NoCompression
    buffer = parent(ds)
    RST = recordsize_type(ds)
    swap = majority(ds) == Row
    nrec = length(rec_range)
    record_bytes = prod(rdims) * esz
    if length.(other_ranges) == rdims
        dest_vec = unsafe_wrap(Vector{UInt8}, dest, nrec * record_bytes)
        _read_records!(dest_vec, buffer, entries, first(rec_range), last(rec_range), record_bytes, compression, RST)
        swap && _majority_swap!(dest, esz, rdims, nrec)
    else
        scratch = Vector{UInt8}(undef, nrec * record_bytes)
        GC.@preserve scratch begin
            _read_records!(scratch, buffer, entries, first(rec_range), last(rec_range), record_bytes, compression, RST)
            swap && _majority_swap!(pointer(scratch), esz, rdims, nrec)
            _copy_subblock!(dest, pointer(scratch), esz, rdims, other_ranges, nrec)
        end
    end
    return
end

# Whole-variable reads skip DiskArrays' indexing layer, which is costly to compile
function Base.Array(var::CDFVariable{T,N}) where {T,N}
    return DiskArrays.readblock!(var, Array{T,N}(undef, size(var)), axes(var)...)
end

function _record(var::CDFVariable{T,N}, r::Int) where {T,N}
    rdims = Base.front(var.dims)
    dest = Array{T,N}(undef, rdims..., 1)
    return DiskArrays.readblock!(var, dest, ntuple(i -> 1:rdims[i], N - 1)..., r:r)
end

# Fill `dest` (exactly `nrec * record_bytes` bytes) with records `rec_first:rec_last`.
# Element-type agnostic so the (threaded) decompression loop compiles once.
function _read_records!(dest::Vector{UInt8}, buffer::Vector{UInt8}, entries::Vector{VVREntry}, rec_first::Int, rec_last::Int, record_bytes::Int, compression::CompressionType, ::Type{RST}) where {RST}
    start_idx = findfirst(e -> e.first <= rec_first <= e.last, entries)::Int
    end_idx = findfirst(e -> e.first <= rec_last <= e.last, entries)::Int
    if compression == NoCompression
        for i in start_idx:end_idx
            _read_entry!(dest, buffer, entries[i], rec_first, rec_last, record_bytes, compression, RST, nothing)
        end
    else
        Threads.@threads for i in start_idx:end_idx
            decompressor = take!(decompressors())
            try
                _read_entry!(dest, buffer, entries[i], rec_first, rec_last, record_bytes, compression, RST, decompressor)
            finally
                put!(decompressors(), decompressor)
            end
        end
    end
    return dest
end

function _read_entry!(dest, buffer, e::VVREntry, rec_first, rec_last, record_bytes, compression, ::Type{RST}, decompressor) where {RST}
    lo, hi = max(rec_first, e.first), min(rec_last, e.last)
    doffs = (lo - rec_first) * record_bytes + 1
    nbytes = (hi - lo + 1) * record_bytes
    skip = (lo - e.first) * record_bytes
    if !e.compressed
        load_vvr_data!(dest, doffs, buffer, e.offset + skip, nbytes, RST)
    elseif skip == 0 && hi == e.last
        load_cvvr_data!(dest, doffs, buffer, e.offset, nbytes, RST, compression; decompressor)
    else
        scratch = Vector{UInt8}(undef, length(e) * record_bytes)
        load_cvvr_data!(scratch, 1, buffer, e.offset, length(scratch), RST, compression; decompressor)
        copyto!(dest, doffs, scratch, skip + 1, nbytes)
    end
    return
end

function collect_vxr_entries!(entries::Vector{VVREntry}, src, offset, ::Type{FieldSizeT}) where {FieldSizeT}
    while offset != 0
        vxr = VXR{FieldSizeT}(src, offset)
        for (first, last, leaf_offset) in vxr
            record_type = get_record_type(src, leaf_offset, FieldSizeT)
            @assert record_type in (VVR_, CVVR_, VXR_)
            if record_type == VXR_
                collect_vxr_entries!(entries, src, leaf_offset, FieldSizeT)
            else
                push!(entries, VVREntry(Int(first) + 1, Int(last) + 1, leaf_offset, record_type == CVVR_))
            end
        end
        offset = vxr.vxr_next
    end
    return entries
end

function variable_compression(vdr::AbstractVDR{FieldSizeT}, cdf) where {FieldSizeT}
    offset_value = Int(vdr.cpr_or_spr_offset)
    if is_compressed(vdr) && offset_value != 0
        buffer = parent(cdf)
        cpr = CPR(buffer, offset_value, FieldSizeT)
        return CompressionType(cpr.compression_type)
    end
    return NoCompression
end
