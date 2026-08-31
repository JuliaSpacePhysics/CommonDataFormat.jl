abstract type AbstractVariable{T,N} <: DiskArrays.AbstractDiskArray{T,N} end

struct VVREntry
    first::Int
    last::Int
    offset::Int
    compressed::Bool  # leaf is a CVVR (a compressed variable may still store poorly-compressing blocks as plain VVRs)
end

Base.length(entry::VVREntry) = entry.last - entry.first + 1

struct CDFVariable{T,N,V,P} <: AbstractVariable{T,N}
    name::String
    vdr::V
    parentdataset::P
    dims::NTuple{N,Int}
end

Base.size(var::CDFVariable) = var.dims

@inline majority(var::CDFVariable) = majority(var.parentdataset)
@inline is_big_endian_encoding(var::CDFVariable) = is_big_endian_encoding(var.parentdataset)

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
    vvrs = read_vvrs(var.vdr, var.parentdataset)
    N = ndims(var)
    chunks = ntuple(N) do i
        if i != N
            DiskArrays.RegularChunks(var.dims[i], 0, var.dims[i])
        else
            chunksizes = length.(vvrs)
            if length(vvrs) > 0
                chunksizes[end] = @views var.dims[N] - sum(chunksizes[1:(end-1)])
            end
            DiskArrays.IrregularChunks(chunksizes=chunksizes)
        end
    end
    return DiskArrays.GridChunks(chunks)
end


@inline function Base.getproperty(var::CDFVariable, name::Symbol)
    name in fieldnames(CDFVariable) && return getfield(var, name)
    if name == :attrib
        return attrib(var)
    elseif name == :datatype
        return CDFDataType(var.vdr.data_type)
    else
        throw(ArgumentError("Unknown property $name"))
    end
end

Base.getindex(var::CDFVariable, name::String) = var.attrib[name]
Base.haskey(var::CDFVariable, name::String) = haskey(var.attrib, name)

attrib(var::CDFVariable) = LazyVAttrib(var.parentdataset, var.vdr.num)
attrib(var::CDFVariable, name::String) = get(attrib(var), name)

is_record_varying(v::CDFVariable) = is_record_varying(v.vdr)
variable_type(v::CDFVariable) = get(v.attrib, "VAR_TYPE", "unknown")

# Base's summary/showarg specializes on the full type; keep it cheap per element type.
Base.summary(io::IO, var::CDFVariable{T}) where {T} =
    print(io, Base.dims2string(size(var)), " CDFVariable{", T, "}")

# DiskArrays' reductions read chunk-by-chunk through its generic indexing,
# which compiles per shape (~40-260 ms).
# With Unchunked chunking that already means one full read
for f in (:sum, :prod, :maximum, :minimum, :extrema, :all, :any, :count)
    @eval Base.$f(var::CDFVariable; kw...) = Base.$f(Array(var); kw...)
    @eval Base.$f(g::Function, var::CDFVariable; kw...) = Base.$f(g, Array(var); kw...)
end

Base.collect(var::CDFVariable) = Array(var)

function Base.iterate(var::CDFVariable)
    isempty(var) && return nothing
    A = Array(var)
    x, st = iterate(A)::Tuple
    return x, (A, st)
end
function Base.iterate(::CDFVariable, state::Tuple{Array,Int})
    A, st = state
    r = iterate(A, st)
    r === nothing && return nothing
    return r[1], (A, r[2])
end

function Base.show(io::IO, m::MIME"text/plain", var::CDFVariable)
    summary(io, var)
    println(io)
    println(io, var.vdr)
    print(io, "attributes: ")
    show(io, m, var.attrib)
    return
end
