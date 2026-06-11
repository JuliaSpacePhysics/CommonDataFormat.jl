# https://github.com/mkitti/StaticStrings.jl
# https://github.com/JuliaPy/PythonCall.jl/blob/main/src/Utils/Utils.jl

struct StaticString{N, T} <: AbstractString
    codeunits::NTuple{N, T}
    StaticString{N, T}(codeunits::NTuple{N, T}) where {N, T} = new{N, T}(codeunits)
end

function Base.iterate(x::StaticString{N, UInt8}, i::Int = 1) where {N}
    i > ncodeunits(x) && return
    cs = x.codeunits
    c = @inbounds cs[i]
    if (c & 0x80) == 0x00
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

function Base.String(x::StaticString)
    n = ncodeunits(x)
    b = Base.StringVector(n)
    @inbounds for i in 1:n
        b[i] = x.codeunits[i]
    end
    return String(b)
end

# CDF CHAR values are fixed-width null-padded; the string ends at the trailing-null run
# so length/collect/String agree with iterate truncating there.
@inline function Base.ncodeunits(s::StaticString{N}) where {N}
    cs = s.codeunits
    n = N
    while n > 0 && iszero(@inbounds cs[n])
        n -= 1
    end
    return n
end
Base.codeunit(::StaticString{N, T}) where {N, T} = T
Base.@propagate_inbounds Base.codeunit(s::StaticString, i::Int) = s.codeunits[i]

function StaticString(cu::Base.CodeUnits{T}) where {T}
    N = length(cu)
    return StaticString{N, T}(NTuple{N, T}(cu))
end
StaticString(s::AbstractString) = StaticString(codeunits(s))

Base.isvalid(s::StaticString, i::Int) = checkbounds(Bool, s, i) && Base._thisind_str(s, i) == i
