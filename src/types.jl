abstract type Record end

abstract type ReservedField end
struct RInt32 <: ReservedField end

_sizeof(x) = sizeof(x)
_sizeof(::Type{RInt32}) = sizeof(Int32)

struct OffsetsIterator{RecordSizeType}
    buffer::Vector{UInt8}
    start_pos::Int
end

Base.eltype(::Type{<:OffsetsIterator}) = Int
# O(n) walk, but cheaper than reallocation `map` would do growing unsized
Base.length(iter::OffsetsIterator) = count(Returns(true), iter)

function Base.iterate(iter::OffsetsIterator{RecordSizeType}, pos::Int = iter.start_pos) where {RecordSizeType}
    pos == 0 && return nothing
    return (pos, next_record_offset(iter.buffer, pos, RecordSizeType))
end
