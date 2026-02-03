abstract type Record end

abstract type ReservedField end
struct RInt32 <: ReservedField end

_sizeof(x) = sizeof(x)
_sizeof(::Type{RInt32}) = sizeof(Int32)

struct OffsetsIterator{RecordSizeType}
    buffer::Vector{UInt8}
    start_pos::Int
end

Base.IteratorSize(::Type{<:OffsetsIterator}) = Base.SizeUnknown()
Base.eltype(::Type{<:OffsetsIterator}) = Int

function Base.iterate(iter::OffsetsIterator{RecordSizeType}, pos::Int = iter.start_pos) where {RecordSizeType}
    pos == 0 && return nothing
    next_pos = Int(read_be(iter.buffer, pos + 1 + sizeof(RecordSizeType) + 4, RecordSizeType))
    return (pos, next_pos)
end
