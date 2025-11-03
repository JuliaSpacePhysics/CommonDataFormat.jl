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

@inline function read_be_i(v::Vector{UInt8}, i, T::Base.DataType)
    return read_be(v, i, T), i + _sizeof(T)
end

@inline function read_be_i(v::Vector{UInt8}, i, n::Integer, T)
    S = sizeof(T)
    return ntuple(j -> read_be(v, i + (j - 1) * S, T), n), i + n * S
end

const name_bytes_buffer = Vector{UInt8}(undef, 256)

"""
    @read_be_fields buffer pos T1 T2 ...

Unrolls sequential big-endian reads starting at `pos` within `buffer`.
Returns a tuple of the parsed values and the updated position, mirroring
`read_be_i` but without the runtime `ntuple`/offset bookkeeping.

# Example

```julia
values, next = @read_be_fields buf pos UInt32 Int16
```
"""
macro read_be_fields(buffer, pos, Ts...)
    isempty(Ts) && error("@read_be_fields requires at least one field type")

    types = flatten_field_types(__module__, Ts)
    buf = esc(buffer)
    start = esc(pos)
    pos_sym = gensym(:pos)
    value_syms = [gensym(:field) for _ in types]

    stmts = Any[:(local $pos_sym = $start)]
    for (sym, T) in zip(value_syms, types)
        Tesc = esc(T)
        push!(stmts, :(local $sym = read_be($buf, $pos_sym, $Tesc)))
        push!(stmts, :($pos_sym += _sizeof($Tesc)))
    end

    tuple_expr = Expr(:tuple, value_syms...)
    push!(stmts, :(($tuple_expr, $pos_sym)))

    return Expr(:block, stmts...)
end

# Optimized version using loop unrolling for better performance
@generated function read_be_fields(buffer::Vector{UInt8}, pos::Integer, ::Type{SType}, ::Val{indxs}) where {SType, indxs}
    exprs = Expr[]
    value_syms = [gensym(:field) for _ in 1:length(indxs)]
    pos_sym = gensym(:pos)

    # Initialize position
    push!(exprs, :(local $pos_sym = pos))

    # Read each field
    for (i, idx) in enumerate(indxs)
        T = fieldtype(SType, idx)
        push!(exprs, :(local $(value_syms[i]) = read_be(buffer, $pos_sym, $T)))
        push!(exprs, :($pos_sym += _sizeof($T)))
    end

    # Return tuple of values and final position
    tuple_expr = Expr(:tuple, value_syms...)
    push!(exprs, :(($tuple_expr, $pos_sym)))

    return Expr(:block, exprs...)
end

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

# Read variable name (null-terminated string, up to 256 chars)
@inline function readname(io::IO)
    read!(io, name_bytes_buffer)
    null_pos = findfirst(==(0x00), name_bytes_buffer)
    pos = isnothing(null_pos) ? 256 : null_pos - 1
    return @views String(name_bytes_buffer[1:pos])
end

function readname(buf::Vector{UInt8}, offset::Int)
    for i in offset:(offset + 255)
        if buf[i] == 0x00
            return @views buf[offset:(i - 1)]
        end
    end
    return @views buf[offset:(offset + 255)]
end

@resumable function get_offsets_lazy(buffer::Vector{UInt8}, pos, ::Type{RecordSizeType}) where {RecordSizeType}
    pos = Int(pos)
    while pos != 0
        @yield pos
        pos = Int(read_be(buffer, pos + 1 + sizeof(RecordSizeType) + 4, RecordSizeType))
    end
end

function get_offsets!(offsets, buffer::Vector{UInt8}, pos, FieldSizeType)
    pos = Int(pos)
    while pos != 0
        push!(offsets, pos)
        pos = Int(read_be(buffer, pos + 1 + sizeof(FieldSizeType) + 4, FieldSizeType))
    end
    return offsets
end
get_offsets(args...) = get_offsets!(Int[], args...)

"""
    is_cdf_v3(magic_bytes)

Determine if this is a CDF v3 file based on the magic number.
"""
is_cdf_v3(magic_bytes) = magic_bytes == 0xCDF30001

"""
    is_big_endian_encoding(encoding)

Determine if a CDF encoding uses big-endian byte order based on CDF specification encoding values.
"""
function is_big_endian_encoding(encoding)
    # Big-endian encodings: network(1), SUN(2), NeXT(12), PPC(9), SGi(5), IBMRS(7), ARM_BIG(19)
    return encoding in (1, 2, 5, 7, 9, 12, 19)
end

const cdf_magic_bytes = [0xCDF30001, 0xCDF26002, 0x0000FFFF] # CDF format uses different magic numbers: CDF3.0, CDF2.x versions

function validate_cdf_magic(magic_bytes)
    return magic_bytes in cdf_magic_bytes
end

_btye_swap!(data) = map!(ntoh, data, data)
_btye_swap!(data::AbstractArray{StaticString{N}}) where {N} = data
# function _btye_swap!(data::AbstractArray{TT2000})
#     rd = reinterpret(Int64, data)
#     return map!(ntoh, rd, rd)
# end
