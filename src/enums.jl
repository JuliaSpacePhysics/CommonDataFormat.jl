@enum Majority::Bool begin
    Row = false
    Column = true
end

@enum RecordType::Int8 begin
    VXR_ = 6
    VVR_ = 7
    CVXR_ = 12
    CVVR_ = 13
end

@enum CompressionType::Int8 begin
    NoCompression = 0
    RLECompression = 1
    HuffmanCompression = 2
    AdaptiveHuffmanCompression = 3
    GzipCompression = 5
    ZstdCompression = 16
end

@enum CDFDataType begin
    CDF_NONE = 0
    CDF_INT1 = 1
    CDF_INT2 = 2
    CDF_INT4 = 4
    CDF_INT8 = 8
    CDF_UINT1 = 11
    CDF_UINT2 = 12
    CDF_UINT4 = 14
    CDF_BYTE = 41
    CDF_REAL4 = 21
    CDF_REAL8 = 22
    CDF_FLOAT = 44
    CDF_DOUBLE = 45
    CDF_EPOCH = 31
    CDF_EPOCH16 = 32
    CDF_TIME_TT2000 = 33
    CDF_CHAR = 51
    CDF_UCHAR = 52
end

Base.:(==)(x::RecordType, y::T) where {T <: Integer} = T(x) == y
Base.:(==)(x::T, y::RecordType) where {T <: Integer} = x == T(y)
Base.:(==)(x::CDFDataType, y::T) where {T <: Integer} = T(x) == y
Base.:(==)(x::T, y::CDFDataType) where {T <: Integer} = x == T(y)

# code → eltype for fixed-size types ordered roughly by frequency
const CODE_TYPE_PAIRS = (
    (21, Float32), (22, Float64), (44, Float32), (45, Float64),
    (33, TT2000), (31, Epoch), (32, Epoch16),
    (1, Int8), (2, Int16), (4, Int32), (8, Int64),
    (11, UInt8), (12, UInt16), (14, UInt32), (41, Int8),
)

const type_map = Dict{CDFDataType, Type}(
    Dict(CDFDataType(c) => T for (c, T) in CODE_TYPE_PAIRS)...,
    CDF_CHAR => UInt8,
    CDF_UCHAR => UInt8,
)

function julia_type(cdf_type, num_elems)
    cdf_type = CDFDataType(cdf_type)
    return cdf_type in (CDF_CHAR, CDF_UCHAR) ? StaticString{Int(num_elems), UInt8} : type_map[cdf_type]
end
