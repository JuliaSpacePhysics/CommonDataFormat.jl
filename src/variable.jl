abstract type AbstractVariable{T, N} <: DiskArrays.AbstractDiskArray{T, N} end

struct VVREntry
    first::Int
    last::Int
    offset::Int
end

Base.length(entry::VVREntry) = entry.last - entry.first + 1

struct CDFVariable{T, N, V, P} <: AbstractVariable{T, N}
    name::String
    vdr::V
    parentdataset::P
    dims::NTuple{N, Int}
end

Base.size(var::CDFVariable) = var.dims

@inline majority(var::CDFVariable) = majority(var.parentdataset)
@inline is_big_endian_encoding(var::CDFVariable) = is_big_endian_encoding(var.parentdataset)

function dst_src_ranges(first, last, entry)
    overlap_first = max(first, entry.first)
    overlap_last = min(last, entry.last)
    local_first = overlap_first - entry.first + 1
    local_last = overlap_last - entry.first + 1
    dest_first = overlap_first - first + 1
    dest_last = overlap_last - first + 1
    return (dest_first:dest_last, local_first:local_last)
end

# Codes seem to be faster if we disable chunking
DiskArrays.haschunks(::CDFVariable) = DiskArrays.Unchunked()
# DiskArrays.haschunks(::CDFVariable) = DiskArrays.Chunked()
DiskArrays.eachchunk(var::CDFVariable) = _eachchunk(var)

function _eachchunk(var::CDFVariable)
    N = ndims(var)
    chunks = ntuple(N) do i
        arraysize = var.dims[i]
        chunksize = max(arraysize, 1) # handle zero-size dimensions
        DiskArrays.RegularChunks(chunksize, 0, arraysize)
    end
    return DiskArrays.GridChunks(chunks)
end

function _eachchunk_vvrs(var::CDFVariable)
    vvrs, _ = read_vvrs(var.vdr)
    N = ndims(var)
    chunks = ntuple(N) do i
        if i != N
            DiskArrays.RegularChunks(var.dims[i], 0, var.dims[i])
        else
            chunksizes = length.(vvrs)
            if length(vvrs) > 0
                chunksizes[end] = @views var.dims[N] - sum(chunksizes[1:(end - 1)])
            end
            DiskArrays.IrregularChunks(chunksizes = chunksizes)
        end
    end
    return DiskArrays.GridChunks(chunks)
end


function Base.getproperty(var::CDFVariable, name::Symbol)
    name in fieldnames(CDFVariable) && return getfield(var, name)
    if name == :attrib
        return vattrib(var.parentdataset, var.vdr.num)
    elseif name == :datatype
        return DataType(var.vdr.data_type)
    else
        throw(ArgumentError("Unknown property $name"))
    end
end

function Base.getindex(var::CDFVariable, name::String)
    at = vattrib(var.parentdataset, var.vdr.num, name)
    isnothing(at) && throw(KeyError(name))
    return at
end

function Base.haskey(var::CDFVariable, name::String)
    return !isnothing(vattrib(var.parentdataset, var.vdr.num, name))
end

attrib(var::CDFVariable, name::String) = vattrib(var.parentdataset, var.vdr.num, name)
attrib(var::CDFVariable) = vattrib(var.parentdataset, var.vdr.num)

is_record_varying(v::CDFVariable) = is_record_varying(v.vdr)
variable_type(v::CDFVariable) = get(v.attrib, "VAR_TYPE", "unknown")

function Base.show(io::IO, m::MIME"text/plain", var::CDFVariable)
    summary(io, var)
    println(io)
    println(io, var.vdr)
    print(io, "attributes: ")
    show(io, m, var.attrib)
    return
end
