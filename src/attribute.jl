"""
    CDFAttribute

Represents a CDF attribute with all its entries.
Attributes can be global (affecting the entire file) or variable-scoped.
"""
struct CDFAttribute{E}
    scope::Int32         # 1 = global, 2 = variable-scoped
    entries::E
end

# Pretty printing for attributes
function Base.show(io::IO, attr::CDFAttribute)
    n = length(attr.entries)
    return n == 1 ? print(io, attr.entries[1]) : print(io, attr.entries)
end
