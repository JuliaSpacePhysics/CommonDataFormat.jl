# CDF parsing utilities
# Low-level binary reading and record parsing functions

# Buffer-based reading functions for zero-copy access
# https://github.com/JuliaLang/julia/issues/31305
@inline function read_be(v::Vector{UInt8}, i, T)
    return GC.@preserve v begin
        p = convert(Ptr{T}, pointer(v, i))
        ntoh(unsafe_load(p))
    end
end

@inline read_be(::Vector{UInt8}, i, ::Type{RInt32}) = RInt32()

@inline function read_be(p::Ptr{T}, i) where {T}
    return ntoh(unsafe_load(p + (i - 1) * sizeof(T)))
end

@inline function read_be(v::Vector{UInt8}, i, n, T)
    S = sizeof(T)
    return ntuple(j -> read_be(v, i + (j - 1) * S, T), n)
end

@inline function read_be(v::Vector{UInt8}, i, ::Val{M}, T) where {M}
    S = sizeof(T)
    return ntuple(j -> read_be(v, i + (j - 1) * S, T), Val(M))
end

@inline function read_be_i(v::Vector{UInt8}, i, T::Base.DataType)
    return read_be(v, i, T), i + _sizeof(T)
end

@inline function read_be_i(v::Vector{UInt8}, i, n::Integer, T)
    S = sizeof(T)
    return ntuple(j -> read_be(v, i + (j - 1) * S, T), n), i + n * S
end

function field_layout(SType, indxs)
    offsets = Int[]
    types = Any[]
    pos = 0
    for idx in indxs
        push!(offsets, pos)
        push!(types, fieldtype(SType, idx))
        pos += _sizeof(types[end])
    end
    return offsets, types, pos
end

@generated function read_be_fields(buffer::Vector{UInt8}, pos::Integer, ::Type{SType}, ::Val{indxs}) where {SType, indxs}
    offsets, types, total = field_layout(SType, indxs)
    values = [:(read_be(buffer, pos + $(offsets[i]), $(types[i]))) for i in eachindex(offsets)]
    return :(($(Expr(:tuple, values...)), pos + $total))
end

@generated function write_be_fields(buffer::Vector{UInt8}, pos::Integer, ::Type{SType}, ::Val{indxs}, values::Tuple) where {SType, indxs}
    offsets, types, total = field_layout(SType, indxs)
    exprs = [
        :(write_be(buffer, pos + $(offsets[i]), convert($(types[i]), values[$i])))
            for i in eachindex(offsets)
    ]
    return Expr(:block, exprs..., :(pos + $total))
end

@inline function write_be(v::Vector{UInt8}, i, x)
    GC.@preserve v unsafe_store!(convert(Ptr{typeof(x)}, pointer(v, i)), hton(x))
    return i + sizeof(x)
end

@inline write_be(v::Vector{UInt8}, i, ::RInt32) = i + _sizeof(RInt32)

function flatten_field_types(mod, args)
    types = Any[]
    for arg in args
        if arg isa Expr && arg.head === :...
            vals = Base.eval(mod, arg.args[1])
            for T in vals
                push!(types, Meta.quot(T))
            end
        else
            push!(types, arg)
        end
    end
    return types
end

function readname(buf::Vector{UInt8}, offset::Int)
    for i in offset:(offset + 255)
        if buf[i] == 0x00
            return @views buf[offset:(i - 1)]
        end
    end
    return @views buf[offset:(offset + 255)]
end

is_cdf_v3(magic_bytes) = magic_bytes == 0xCDF30001

function is_big_endian_encoding(encoding)
    # Big-endian encodings: network(1), SUN(2), NeXT(12), PPC(9), SGi(5), IBMRS(7), ARM_BIG(19)
    return encoding in (1, 2, 5, 7, 9, 12, 19)
end

const cdf_magic_bytes = (0xCDF30001, 0xCDF26002, 0x0000FFFF) # CDF format uses different magic numbers: CDF3.0, CDF2.x versions

function validate_cdf_magic(magic_bytes)
    return magic_bytes in cdf_magic_bytes
end

_byte_swap!(data) = map!(ntoh, data, data)
_byte_swap!(data::AbstractArray{<:StaticString{N}}) where {N} = data
