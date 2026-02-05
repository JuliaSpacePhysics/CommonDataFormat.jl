# https://github.com/mkitti/StaticStrings.jl
# https://github.com/JuliaPy/PythonCall.jl/blob/main/src/Utils/Utils.jl
using Base: between

struct StaticString{N, T} <: AbstractString
    codeunits::NTuple{N, T}
    StaticString{N, T}(codeunits::NTuple{N, T}) where {N, T} = new{N, T}(codeunits)
end

function Base.iterate(x::StaticString{N, UInt8}, i::Int = 1) where {N}
    i > N && return
    cs = x.codeunits
    c = @inbounds cs[i]
    if all(iszero, (cs[j] for j in i:N))
        return
    elseif (c & 0x80) == 0x00
        return (reinterpret(Char, UInt32(c) << 24), i + 1)
    elseif (c & 0x40) == 0x00
        nothing
    elseif (c & 0x20) == 0x00
        if @inbounds (i ≤ N - 1) && ((cs[i + 1] & 0xC0) == 0x80)
            return (
                reinterpret(Char, (UInt32(cs[i]) << 24) | (UInt32(cs[i + 1]) << 16)),
                i + 2,
            )
        end
    elseif (c & 0x10) == 0x00
        if @inbounds (i ≤ N - 2) && ((cs[i + 1] & 0xC0) == 0x80) && ((cs[i + 2] & 0xC0) == 0x80)
            return (
                reinterpret(
                    Char,
                    (UInt32(cs[i]) << 24) |
                        (UInt32(cs[i + 1]) << 16) |
                        (UInt32(cs[i + 2]) << 8),
                ),
                i + 3,
            )
        end
    elseif (c & 0x08) == 0x00
        if @inbounds (i ≤ N - 3) &&
                ((cs[i + 1] & 0xC0) == 0x80) &&
                ((cs[i + 2] & 0xC0) == 0x80) &&
                ((cs[i + 3] & 0xC0) == 0x80)
            return (
                reinterpret(
                    Char,
                    (UInt32(cs[i]) << 24) |
                        (UInt32(cs[i + 1]) << 16) |
                        (UInt32(cs[i + 2]) << 8) |
                        UInt32(cs[i + 3]),
                ),
                i + 4,
            )
        end
    end
    throw(StringIndexError(x, i))
end

function Base.String(x::StaticString{N, T}) where {N, T}
    b = Base.StringVector(N)
    return String(b .= x.codeunits)
end

@inline Base.ncodeunits(::StaticString{N}) where {N} = N
Base.codeunit(::StaticString{N, T}) where {N, T} = T
Base.@propagate_inbounds Base.codeunit(s::StaticString, i::Int) = s.codeunits[i]

function StaticString(cu::Base.CodeUnits{T}) where {T}
    N = length(cu)
    return StaticString{N, T}(NTuple{N, T}(cu))
end
StaticString(s::AbstractString) = StaticString(codeunits(s))

Base.isvalid(s::StaticString, i::Int) = checkbounds(Bool, s, i) && thisind(s, i) == i
Base.thisind(s::StaticString, i::Int) = _thisind_str(s, i)

@inline function _thisind_str(s, i::Int)
    i == 0 && return 0
    n = ncodeunits(s)
    i == n + 1 && return i
    @boundscheck between(i, 1, n) || throw(BoundsError(s, i))
    @inbounds b = codeunit(s, i)
    (b & 0xc0 == 0x80) & (i - 1 > 0) || return i
    @inbounds b = codeunit(s, i - 1)
    between(b, 0b11000000, 0b11110111) && return i - 1
    (b & 0xc0 == 0x80) & (i - 2 > 0) || return i
    @inbounds b = codeunit(s, i - 2)
    between(b, 0b11100000, 0b11110111) && return i - 2
    (b & 0xc0 == 0x80) & (i - 3 > 0) || return i
    @inbounds b = codeunit(s, i - 3)
    between(b, 0b11110000, 0b11110111) && return i - 3
    return i
end
