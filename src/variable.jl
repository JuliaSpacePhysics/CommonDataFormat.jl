struct CDFVariable{T, N, A <: AbstractArray{T, N}, V} <: AbstractArray{T, N}
    name::String
    data::A
    vdr::V
end


Base.parent(var::CDFVariable) = var.data
Base.iterate(var::CDFVariable, args...) = iterate(parent(var), args...)
for f in (:size, :Array)
    @eval Base.$f(var::CDFVariable) = $f(parent(var))
end

for f in (:getindex,)
    @eval Base.@propagate_inbounds Base.$f(var::CDFVariable, I::Vararg{Int}) = $f(parent(var), I...)
end