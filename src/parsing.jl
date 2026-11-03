# Low-level binary reading and record parsing functions

@inline function read_be(v::Vector{UInt8}, i, T)
    checkbounds(v, i:(i + sizeof(T) - 1))
    return GC.@preserve v begin
        p = convert(Ptr{T}, pointer(v, i))
        ntoh(unsafe_load(p))
    end
end

@inline read_be(::Vector{UInt8}, i, ::Type{RInt32}) = RInt32()

@inline function read_be(p::Ptr{T}, i) where {T}
    return ntoh(unsafe_load(p + (i - 1) * sizeof(T)))
end

@inline function read_be(v::Vector{UInt8}, i, ::Val{M}, T) where {M}
    S = sizeof(T)
    return ntuple(j -> read_be(v, i + (j - 1) * S, T), Val(M))
end

@inline function read_be_i(v::Vector{UInt8}, i, T::Base.DataType)
    return read_be(v, i, T), i + _sizeof(T)
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
    checkbounds(v, i:(i + sizeof(x) - 1))
    GC.@preserve v unsafe_store!(convert(Ptr{typeof(x)}, pointer(v, i)), hton(x))
    return i + sizeof(x)
end

@inline write_be(v::Vector{UInt8}, i, ::RInt32) = i + _sizeof(RInt32)

# CDF before 3.8 had no UTF-8, so text values may be Latin-1
_utf8(s::String) = isvalid(s) ? s : String(map(Char, codeunits(s)))

# Name fields are NUL-padded to a fixed width: 256 bytes in CDF v3, 64 in v2.
_name_width(::Type{FST}) where {FST} = FST == Int64 ? 256 : 64

function readname(buf::Vector{UInt8}, offset::Int, ::Type{FST}) where {FST}
    w = _name_width(FST)
    n = something(findfirst(iszero, @view buf[offset:(offset + w - 1)]), w + 1) - 1
    return GC.@preserve buf unsafe_string(pointer(buf, offset), n)
end

function name_equals(buf::Vector{UInt8}, offset::Int, name::String, ::Type{FST}) where {FST}
    n = ncodeunits(name)
    w = _name_width(FST)
    n <= w || return false
    (n == w || buf[offset + n] == 0x00) || return false
    return GC.@preserve buf name ccall(:memcmp, Cint, (Ptr{UInt8}, Ptr{UInt8}, Csize_t), pointer(buf, offset), pointer(name), n) == 0
end

function is_big_endian_encoding(encoding)
    # network(1), SUN(2), SGi(5), IBMRS(7), PPC(9), HP(11), NeXT(12), ARM_BIG(18)
    return encoding in (1, 2, 5, 7, 9, 11, 12, 18)
end

# Big-endian files: words are `unit` bytes each; a `unit` of 1 means raw bytes, nothing to swap.
_swap_unit(::Type{T}) where {T} = sizeof(T)
_swap_unit(::Type{Epoch16}) = 8  # two Float64s

function _byte_swap!(dst::Ptr{UInt8}, src::Ptr{UInt8}, nbytes::Int, unit::Int)
    if unit <= 1
        dst == src || unsafe_copyto!(dst, src, nbytes)
        return
    end
    unit == 2 && return _swap_words!(Ptr{UInt16}(dst), Ptr{UInt16}(src), nbytes ÷ 2)
    unit == 4 && return _swap_words!(Ptr{UInt32}(dst), Ptr{UInt32}(src), nbytes ÷ 4)
    unit == 8 && return _swap_words!(Ptr{UInt64}(dst), Ptr{UInt64}(src), nbytes ÷ 8)
    throw(ArgumentError("unsupported byte-swap unit $unit"))
end
function _swap_words!(dst::Ptr{U}, src::Ptr{U}, n::Int) where {U}
    @simd ivdep for i in 1:n
        unsafe_store!(dst, ntoh(unsafe_load(src, i)), i)
    end
    return
end
# `pointer` goes through `cconvert`, so when `T` is not inferred any new
# `cconvert(::Type{Ptr{X}}, ::Vector)` method (e.g. LibGit2's) invalidates the caller.
_ptr(a::AbstractArray{T}) where {T} = Base.unsafe_convert(Ptr{T}, a)
