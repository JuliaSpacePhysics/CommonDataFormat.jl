abstract type Record end

abstract type ReservedField end
struct RInt32 <: ReservedField end
Base.sizeof(::Type{RInt32}) = sizeof(Int32)
