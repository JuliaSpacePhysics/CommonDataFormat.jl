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
    vvrs::Vector{VVREntry}
    compression::CompressionType
    byte_swap::Bool
end

Base.size(var::CDFVariable) = var.dims

function dst_src_ranges(first, last, entry)
    overlap_first = max(first, entry.first)
    overlap_last = min(last, entry.last)
    local_first = overlap_first - entry.first + 1
    local_last = overlap_last - entry.first + 1
    dest_first = overlap_first - first + 1
    dest_last = overlap_last - first + 1
    return (dest_first:dest_last, local_first:local_last)
end

DiskArrays.haschunks(::CDFVariable) = DiskArrays.Chunked()
function DiskArrays.eachchunk(var::CDFVariable)
    N = ndims(var)
    chunks = ntuple(N) do i
        if i != N
            DiskArrays.RegularChunks(var.dims[i], 0, var.dims[i])
        else
            chunksizes = length.(var.vvrs)
            if length(var.vvrs) > 0
                chunksizes[end] = @views var.dims[N] - sum(chunksizes[1:end-1])
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

function CPR(var::CDFVariable)
    vdr = var.vdr
    cdf = var.parentdataset
    return CPR(parent(cdf), vdr.cpr_or_spr_offset, recordsize_type(cdf))
end

is_record_varying(v::CDFVariable) = is_record_varying(v.vdr)