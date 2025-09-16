abstract type AbstractVariable{T, N} <: AbstractArray{T, N} end

struct CDFVariable{T, N, A <: AbstractArray{T, N}, V} <: AbstractVariable{T, N}
    name::String
    data::A
    vdr::V
    parentdataset::CDFDataset
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
    else
        throw(ArgumentError("Unknown property $name"))
    end
end

# Get the corresponding metadata
function Base.getindex(var::CDFVariable, name::String)
    return vattrib(var.parentdataset, var.vdr.num)[name]
end
