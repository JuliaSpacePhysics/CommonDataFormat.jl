abstract type Record end

abstract type ReservedField end
struct RInt32 <: ReservedField end

_sizeof(x) = sizeof(x)
_sizeof(::Type{RInt32}) = sizeof(Int32)
