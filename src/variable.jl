struct VVREntry
    first::Int
    last::Int
    offset::Int
    compressed::Bool  # leaf is a CVVR (a compressed variable may still store poorly-compressing blocks as plain VVRs)
end

Base.length(entry::VVREntry) = entry.last - entry.first + 1

# A handle on a variable in the file.
struct CDFVariable{T,N,V,P}
    name::String
    vdr::V
    parentdataset::P
    dims::NTuple{N,Int}
end

Base.eltype(::Type{<:CDFVariable{T}}) where {T} = T
Base.ndims(::CDFVariable{T,N}) where {T,N} = N
Base.size(var::CDFVariable) = var.dims
Base.size(var::CDFVariable, d::Integer) = d <= ndims(var) ? var.dims[d] : 1
Base.length(var::CDFVariable) = prod(var.dims)
Base.isempty(var::CDFVariable) = length(var) == 0
Base.axes(var::CDFVariable) = map(Base.OneTo, var.dims)
Base.axes(var::CDFVariable, d::Integer) = Base.OneTo(size(var, d))
Base.firstindex(::CDFVariable, d::Integer...) = 1
Base.lastindex(var::CDFVariable) = length(var)
Base.lastindex(var::CDFVariable, d::Integer) = size(var, d)

const RegionIndex = Union{Integer,AbstractUnitRange{<:Integer},Colon}

# One index per dimension, reading only the records spanned, or one integer linear index.
function Base.getindex(var::CDFVariable{T,N}, I::RegionIndex...) where {T,N}
    length(I) == 1 && N > 1 && only(I) isa Integer && return _getlinear(var, only(I))
    length(I) == N || throw(ArgumentError("index a $N-dimensional CDFVariable with $N indices or one integer"))
    region = map(_region, axes(var), I)
    all(map(issubset, region, axes(var))) || throw(BoundsError(var, I))
    all(i -> i isa Integer, I) && return _element(var, map(Int, I))
    return reshape(read!(var, Array{T,N}(undef, map(length, region)), region...), _kept(I, region))
end

_region(ax, i::Integer) = i:i
_region(ax, ::Colon) = ax
_region(ax, r::AbstractUnitRange) = r

# Lengths of the dimensions not indexed by an integer.
_kept(::Tuple{}, ::Tuple{}) = ()
_kept(I::Tuple, R::Tuple) = first(I) isa Integer ? _kept(Base.tail(I), Base.tail(R)) : (length(first(R)), _kept(Base.tail(I), Base.tail(R))...)

function _getlinear(var::CDFVariable, i::Integer)
    1 <= i <= length(var) || throw(BoundsError(var, (i,)))
    return _element(var, Tuple(CartesianIndices(var.dims)[i]))
end

_element(var::CDFVariable{T,N}, I::NTuple{N,Int}) where {T,N} =
    only(read!(var, Array{T,N}(undef, ntuple(_ -> 1, Val(N))), map(i -> i:i, I)...))

Base.Array(var::CDFVariable{T,N}) where {T,N} = read!(var, Array{T,N}(undef, var.dims))

Base.read!(var::CDFVariable, dest::AbstractArray) = read!(var, dest, axes(var)...)

@inline majority(var::CDFVariable) = majority(var.parentdataset)
@inline is_big_endian_encoding(var::CDFVariable) = is_big_endian_encoding(var.parentdataset)

@inline function Base.getproperty(var::CDFVariable, name::Symbol)
    name in fieldnames(CDFVariable) && return getfield(var, name)
    name === :attrib && return attrib(var)
    name === :datatype && return CDFDataType(var.vdr.data_type)
    throw(ArgumentError("Unknown property $name"))
end

Base.getindex(var::CDFVariable, name::String) = var.attrib[name]
Base.haskey(var::CDFVariable, name::String) = haskey(var.attrib, name)

attrib(var::CDFVariable) = LazyVAttrib(var.parentdataset, var.vdr.num, var.vdr.zvar)
attrib(var::CDFVariable, name::String) = get(attrib(var), name)

is_record_varying(v::CDFVariable) = is_record_varying(v.vdr)
variable_type(v::CDFVariable) = get(v.attrib, "VAR_TYPE", "unknown")

# Base's summary/showarg specializes on the full type; keep it cheap per element type.
Base.summary(io::IO, var::CDFVariable{T}) where {T} =
    print(io, Base.dims2string(size(var)), " CDFVariable{", T, "}")

Base.show(io::IO, var::CDFVariable) = (summary(io, var); print(io, " ", repr(var.name)))

function Base.show(io::IO, m::MIME"text/plain", var::CDFVariable)
    summary(io, var)
    println(io)
    println(io, var.vdr)
    print(io, "attributes: ")
    show(io, m, var.attrib)
    return
end
