abstract type AbstractVariable{T, N} <: AbstractArray{T, N} end

struct CDFVariable{T, N, A <: AbstractArray{T, N}, V, P} <: AbstractVariable{T, N}
    name::String
    data::A
    vdr::V
    parentdataset::P
end


Base.parent(var::AbstractVariable) = var.data
Base.iterate(var::AbstractVariable, args...) = iterate(parent(var), args...)
for f in (:size, :Array)
    @eval Base.$f(var::AbstractVariable) = $f(parent(var))
end

for f in (:getindex,)
    @eval Base.@propagate_inbounds Base.$f(var::AbstractVariable, I::Vararg{Int}) = $f(parent(var), I...)
end

function Base.getproperty(var::CDFVariable, name::Symbol)
    name in fieldnames(CDFVariable) && return getfield(var, name)
    if name === :attrib
        return vattrib(var.parentdataset, var.vdr.num)
    elseif name === :datatype
        return DataType(var.vdr.data_type)
    else
        throw(ArgumentError("Unknown property $name"))
    end
end

# Get the corresponding metadata
function Base.getindex(var::CDFVariable, name::String)
    at = vattrib(var.parentdataset, var.vdr.num, name)
    isnothing(at) && throw(KeyError(name))
    return at
end

function Base.haskey(var::CDFVariable, name::String)
    at = vattrib(var.parentdataset, var.vdr.num, name)
    return !isnothing(at)
end

attrib(var::CDFVariable, name::String) = vattrib(var.parentdataset, var.vdr.num, name)

function CPR(var::CDFVariable)
    vdr = var.vdr
    cdf = var.parentdataset
    return CPR(parent(cdf), vdr.cpr_or_spr_offset, recordsize_type(cdf))
end