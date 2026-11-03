# CDF allows 10 record dimensions
const MAX_LEVELS = 11
const SinkLevels = NTuple{MAX_LEVELS,Int}

# Type-erased block moves: Element movers, chosen once per block by element size; `ByteMove` covers odd sizes (CHAR data)
struct WordMove{U} end
struct ByteMove end
@inline (::WordMove{U})(d::Ptr{UInt8}, s::Ptr{UInt8}, ::Int) where {U} = unsafe_store!(Ptr{U}(d), unsafe_load(Ptr{U}(s)))
@inline (::ByteMove)(d::Ptr{UInt8}, s::Ptr{UInt8}, esz::Int) = unsafe_copyto!(d, s, esz)

# Gather a column-major block of `dims` elements (`esz` bytes each) whose source byte
# strides are `sstrides` into contiguous `dst`. Levels past the used ones are `1` with stride `0`.
function _copy_block!(dst::Ptr{UInt8}, src::Ptr{UInt8}, esz::Int, dims::SinkLevels, sstrides::SinkLevels)
    esz == 8 && return _copy_block!(dst, src, esz, dims, sstrides, WordMove{UInt64}())
    esz == 4 && return _copy_block!(dst, src, esz, dims, sstrides, WordMove{UInt32}())
    esz == 2 && return _copy_block!(dst, src, esz, dims, sstrides, WordMove{UInt16}())
    esz == 1 && return _copy_block!(dst, src, esz, dims, sstrides, WordMove{UInt8}())
    esz == 16 && return _copy_block!(dst, src, esz, dims, sstrides, WordMove{UInt128}())
    return _copy_block!(dst, src, esz, dims, sstrides, ByteMove())
end

@inline function _copy_runs!(dst::Ptr{UInt8}, src::Ptr{UInt8}, esz::Int, n0::Int, s0::Int, n1::Int, s1::Int, move)
    run_bytes = n0 * esz
    memcpy_run = s0 == esz && run_bytes > 64  # a memmove call per short run costs more than it saves
    for r in 0:(n1-1)
        run = src + r * s1
        if memcpy_run
            unsafe_copyto!(dst, run, run_bytes)
        else
            for i in 0:(n0-1)
                move(dst + i * esz, run + i * s0, esz)
            end
        end
        dst += run_bytes
    end
    return dst
end

# Levels above the two innermost step an odometer: a call per run would dominate short runs.
function _copy_block!(dst::Ptr{UInt8}, src::Ptr{UInt8}, esz::Int, dims::SinkLevels, sstrides::SinkLevels, move)
    n0, s0, n1, s1 = dims[1], sstrides[1], dims[2], sstrides[2]
    nouter = 1
    for k in 3:MAX_LEVELS
        nouter *= dims[k]
    end
    if nouter == 1
        _copy_runs!(dst, src, esz, n0, s0, n1, s1, move)
        return
    end
    idx = zeros(Int, MAX_LEVELS)
    soff = 0
    for _ in 1:nouter
        dst = _copy_runs!(dst, src + soff, esz, n0, s0, n1, s1, move)
        k = 3
        while k <= MAX_LEVELS
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

# Byte stride of each record dimension as stored. Row-majority stores the last record dimension fastest.
_strides(esz, rdims) = Base.front(accumulate(*, (esz, rdims...)))
_strides(esz, rdims, row) = row ? reverse(_strides(esz, reverse(rdims))) : _strides(esz, rdims)

# Output of a read. Records keep their stored layout in the file and in decode buffers, and each is
# gathered straight into `dest`; decoders can target `dest` itself only when it shares that layout (`_direct`).
struct RecordSink
    dest::Ptr{UInt8}
    esz::Int
    nlevels::Int  # 0 if `_direct`
    dims::SinkLevels  # taken from each record, without singletons (a loop per run), then the record count
    sstrides::SinkLevels
    offset::Int  # bytes into a stored record of the first element taken
    record_bytes::Int  # stored
    out_bytes::Int  # per record in `dest`
end

_direct(s::RecordSink) = iszero(s.nlevels)

function RecordSink(dest::Ptr{UInt8}, esz::Int, rdims::NTuple{K,Int}, ranges::NTuple{K,UnitRange{Int}}, row::Bool) where {K}
    record_bytes = esz * prod(rdims; init = 1)
    out_bytes = esz * prod(length, ranges; init = 1)
    dims, sstrides = ntuple(_ -> 1, Val(MAX_LEVELS)), ntuple(_ -> 0, Val(MAX_LEVELS))
    if out_bytes == record_bytes && (!row || count(>(1), rdims) <= 1)
        return RecordSink(dest, esz, 0, dims, sstrides, 0, record_bytes, out_bytes)
    end
    offset, m = 0, 0
    for (r, st) in zip(ranges, _strides(esz, rdims, row))
        offset += (first(r) - 1) * st
        if length(r) > 1
            m += 1
            dims = Base.setindex(dims, length(r), m)
            sstrides = Base.setindex(sstrides, st, m)
        end
    end
    sstrides = Base.setindex(sstrides, record_bytes, m + 1)
    return RecordSink(dest, esz, m + 1, dims, sstrides, offset, record_bytes, out_bytes)
end

# `nrec` stored records at `src` into `dest`, `rec` records in.
function _store!(s::RecordSink, rec::Int, src::Ptr{UInt8}, nrec::Int)
    dst = s.dest + rec * s.out_bytes
    if _direct(s)
        unsafe_copyto!(dst, src, nrec * s.record_bytes)
    else
        _copy_block!(dst, src + s.offset, s.esz, Base.setindex(s.dims, nrec, s.nlevels), s.sstrides)
    end
    return
end

function _check_region(var, dest, ranges)
    all(map(issubset, ranges, axes(var))) || throw(BoundsError(var, ranges))
    length(dest) == prod(map(length, ranges); init = 1) || throw(DimensionMismatch("destination of length $(length(dest)) for a region of size $(map(length, ranges))"))
    return
end

function Base.read!(var::CDFVariable{T,N}, dest::AbstractArray{T}, ranges::Vararg{AbstractUnitRange{<:Integer},N}) where {T,N}
    _check_region(var, dest, ranges)
    isempty(dest) && return dest
    _isdense(dest) || return copyto!(dest, read!(var, Array{T}(undef, size(dest)), ranges...))
    return _read_array!(var, dest, ranges)
end

# Decoding writes through a pointer, so `dest` must be CPU memory laying out bits elements in
# column-major order without gaps
_isdense(::Array) = true
_isdense(a::StridedArray{T}) where {T} = isbitstype(T) && _cpubacked(a) && _contiguous(a)
_isdense(_) = false

_cpubacked(::Array) = true
@static if isdefined(Base, :Memory)
    _cpubacked(::Memory) = true
end
_cpubacked(a::Union{SubArray, Base.ReshapedArray, Base.ReinterpretArray}) = _cpubacked(parent(a))
_cpubacked(_) = false

function _contiguous(a)
    s = 1
    for d in 1:ndims(a)
        size(a, d) == 1 || stride(a, d) == s || return false
        s *= size(a, d)
    end
    return true
end

function _read_array!(var::CDFVariable{T}, dest::AbstractArray{T}, ranges) where {T}
    GC.@preserve dest _read_region!(Ptr{UInt8}(_ptr(dest)), sizeof(T), var, ranges)
    is_big_endian_encoding(var) && _byte_swap!(dest)
    return dest
end

# CHAR elements are `num_elems`-byte fields, null-padded; the string ends at the trailing-null run.
function _read_array!(var::CDFVariable{String}, dest::Array{String}, ranges)
    w = Int(var.vdr.num_elems)
    bytes = Vector{UInt8}(undef, w * length(dest))
    GC.@preserve bytes _read_region!(pointer(bytes), w, var, ranges)
    _fill_strings!(vec(dest), bytes, w)
    return dest
end

function _fill_strings!(dest::Vector{String}, bytes::Vector{UInt8}, w::Int)
    GC.@preserve bytes for k in eachindex(dest)
        o = (k - 1) * w
        # Per-record flags repeat for long runs, so share the previous String when possible.
        if k > 1 && ccall(:memcmp, Cint, (Ptr{UInt8}, Ptr{UInt8}, Csize_t), pointer(bytes, o + 1), pointer(bytes, o + 1 - w), w) == 0
            dest[k] = dest[k - 1]
            continue
        end
        n = w
        while n > 0 && iszero(@inbounds bytes[o + n])
            n -= 1
        end
        dest[k] = unsafe_string(pointer(bytes, o + 1), n)
    end
    return dest
end

_int_range(r) = Int(first(r)):Int(last(r))

function record_index(vdr, ds::CDFDataset)
    return @lock getfield(ds, :record_index_lock) begin
        get!(getfield(ds, :record_index), Int(vdr.vxr_head)) do
            entries = read_vvrs(vdr, ds)
            (entries, any(e -> e.compressed, entries) ? variable_compression(vdr, ds) : NoCompression)
        end
    end
end

function _read_region!(dest, esz, var::CDFVariable, ranges)
    vdr, ds = var.vdr, var.parentdataset
    sink = RecordSink(dest, esz, Base.front(var.dims), map(_int_range, Base.front(ranges)), majority(ds) == Row)
    return _read_region!(sink, _int_range(ranges[end]), vdr, ds, record_index(vdr, ds)...)
end

function _read_region!(sink::RecordSink, rec_range::UnitRange{Int}, vdr, ds::CDFDataset, entries::Vector{VVREntry}, compression::CompressionType)
    virtual = _covers(entries, rec_range) ? NO_VIRTUAL : VirtualRecords(vdr.s_records == 2, pad_bytes(vdr, ds, sink.esz))
    _read_records!(sink, ds, entries, first(rec_range), last(rec_range), compression, virtual)
    return
end

function _record(var::CDFVariable{T,N}, r::Int) where {T,N}
    rdims = Base.front(var.dims)
    dest = Array{T,N}(undef, rdims..., 1)
    read!(var, dest, ntuple(i -> 1:rdims[i], N - 1)..., r:r)
    return dest
end

# Records absent from the VXR tree are virtual: sparse variables (sRecords) or records
# never written. Previous-record sparse repeats the last physical record before the gap;
# everything else, including a prev-sparse gap with no physical record before it, reads
# as the pad value.
struct VirtualRecords
    prev::Bool
    pad::Vector{UInt8}  # one element, in file encoding so the final byte swap covers it
end

const NO_VIRTUAL = VirtualRecords(false, UInt8[])

# Entries are sorted and disjoint, so both `first` and `last` increase
_entry_first(x) = x isa VVREntry ? x.first : x
_entry_last(x) = x isa VVREntry ? x.last : x

function _covers(entries, rec_range)
    r = first(rec_range)
    for i in searchsortedfirst(entries, r; by = _entry_last):lastindex(entries)
        e = entries[i]
        e.first > r && return false
        r = e.last + 1
        r > last(rec_range) && return true
    end
    return r > last(rec_range)
end

const NO_SCRATCH = UInt8[]  # direct sinks decode into `dest`

# Element-type agnostic so decompression loop compiles once per record-size type.
function _read_records!(sink::RecordSink, ds::CDFDataset, entries::Vector{VVREntry}, rec_first::Int, rec_last::Int, compression::CompressionType, virtual::VirtualRecords)
    start_idx = searchsortedfirst(entries, rec_first; by = _entry_last)
    end_idx = searchsortedlast(entries, rec_last; by = _entry_first)
    n = end_idx - start_idx + 1
    threaded = compression != NoCompression && (rec_last - rec_first + 1) * sink.record_bytes >= 1 << 20
    # Gzip entries decode up to 4 at once per task (faster per entry); with few entries,
    # smaller groups keep every thread busy.
    step = compression != GzipCompression ? 1 : threaded ? clamp(n ÷ nthreads(), 2, 4) : 4
    nworkers = threaded ? min(cld(n, step), nthreads()) : 1
    read_group(i, scratch) = _read_entries!(sink, scratch, ds, entries, i, min(i + step - 1, end_idx), rec_first, rec_last, compression)
    if nworkers == 1
        scratch = _direct(sink) ? NO_SCRATCH : UInt8[]
        for i in start_idx:step:end_idx
            read_group(i, scratch)
        end
    else
        next = Threads.Atomic{Int}(start_idx)
        function work()
            buf = UInt8[]
            while (i = Threads.atomic_add!(next, step)) <= end_idx
                read_group(i, buf)
            end
        end
        tasks = [Threads.@spawn(work()) for _ in 2:nworkers]
        try
            work()
        finally
            foreach(wait, tasks)
        end
    end
    r = rec_first
    for i in start_idx:(end_idx + 1)
        gap_end = i <= end_idx ? min(entries[i].first - 1, rec_last) : rec_last
        r <= gap_end && _fill_virtual!(sink, ds, entries, i - 1, r - rec_first, gap_end - r + 1, compression, virtual)
        i <= end_idx && (r = entries[i].last + 1)
    end
    return
end

# Fill `n` records of the output starting `skip` records in; `prev_idx` is the last entry before the gap.
function _fill_virtual!(sink, ds, entries, prev_idx, skip, n, compression, virtual)
    out = sink.out_bytes
    first_rec = sink.dest + skip * out
    if virtual.prev && prev_idx >= 1
        e = entries[prev_idx]
        _read_span!(sink, UInt8[], ds, e, e.last, e.last, skip, compression)
    else
        pad = virtual.pad
        esz = length(pad)
        GC.@preserve pad for k in 0:esz:(out - 1)
            unsafe_copyto!(first_rec + k, pointer(pad), esz)
        end
    end
    for j in 1:(n - 1)
        unsafe_copyto!(first_rec + j * out, first_rec, out)
    end
    return
end

# Entries `i:j` (at most 4); whole gzip entries among them decode together.
function _read_entries!(sink, scratch, ds, entries, i, j, rec_first, rec_last, compression)
    i == j && return _read_entry!(sink, scratch, ds, entries[i], rec_first, rec_last, compression)
    k1 = k2 = k3 = k4 = n = 0
    for k in i:j
        if compression == GzipCompression && _whole_compressed(entries[k], rec_first, rec_last)
            n += 1
            n == 1 ? (k1 = k) : n == 2 ? (k2 = k) : n == 3 ? (k3 = k) : (k4 = k)
        else
            _read_entry!(sink, scratch, ds, entries[k], rec_first, rec_last, compression)
        end
    end
    whole(ks) = _decode_whole!(sink, scratch, ds, map(k -> (entries[k], entries[k].first - rec_first), ks), compression)
    n == 1 && whole((k1,))
    n == 2 && whole((k1, k2))
    n == 3 && whole((k1, k2, k3))
    n == 4 && whole((k1, k2, k3, k4))
    return
end

# Whole compressed entries, each given with its position in the output records; several decode in lockstep (gzip only).
function _decode_whole!(sink, scratch, ds::CDFDataset{RST}, jobs, compression) where {RST}
    buffer = parent(ds)
    rb = sink.record_bytes
    direct = _direct(sink)
    sizes = map(((e, _),) -> length(e) * rb, jobs)
    offsets = direct ? map(((_, rec),) -> rec * rb, jobs) : accumulate(+, (0, Base.front(sizes)...))
    direct || resize!(scratch, sum(sizes))
    GC.@preserve scratch begin
        out = direct ? sink.dest : pointer(scratch)
        if length(jobs) == 1
            load_cvvr_data!(out + only(offsets), buffer, jobs[1][1].offset, only(sizes), RST, compression)
        else
            load_cvvr_group!(buffer, map(((e, _), o, n) -> (out + o, e.offset, n), jobs, offsets, sizes), RST)
        end
        if !direct
            for ((e, rec), o) in zip(jobs, offsets)
                _store!(sink, rec, out + o, length(e))
            end
        end
    end
    return
end

_whole_compressed(e::VVREntry, rec_first, rec_last) = e.compressed && e.first >= rec_first && e.last <= rec_last

function _read_entry!(sink, scratch, ds, e::VVREntry, rec_first, rec_last, compression)
    lo, hi = max(rec_first, e.first), min(rec_last, e.last)
    return _read_span!(sink, scratch, ds, e, lo, hi, lo - rec_first, compression)
end

# Records `lo:hi` of `e` into the output, `rec` records in.
function _read_span!(sink, scratch, ds::CDFDataset{RST}, e::VVREntry, lo, hi, rec, compression) where {RST}
    buffer = parent(ds)
    rb = sink.record_bytes
    skip = (lo - e.first) * rb
    if !e.compressed
        nrec = hi - lo + 1
        pos = _after_header(e.offset, RST) + skip
        checkbounds(buffer, pos:(pos + nrec * rb - 1))
        GC.@preserve buffer _store!(sink, rec, pointer(buffer, pos), nrec)
    elseif _whole_compressed(e, lo, hi)
        _decode_whole!(sink, scratch, ds, ((e, rec),), compression)
    else
        block = cached_block!(BLOCK_CACHE, (dataset_id(ds), e.offset)) do
            b = Vector{UInt8}(undef, length(e) * rb)
            GC.@preserve b load_cvvr_data!(pointer(b), buffer, e.offset, length(b), RST, compression)
            b
        end
        GC.@preserve block _store!(sink, rec, pointer(block, skip + 1), hi - lo + 1)
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

function variable_compression(vdr::VDR{FieldSizeT}, cdf) where {FieldSizeT}
    offset_value = Int(vdr.cpr_or_spr_offset)
    if is_compressed(vdr) && offset_value != 0
        buffer = parent(cdf)
        cpr = CPR(buffer, offset_value, FieldSizeT)
        return CompressionType(cpr.compression_type)
    end
    return NoCompression
end
