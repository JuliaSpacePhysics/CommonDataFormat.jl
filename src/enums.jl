@enum Majority begin
    Row = 0
    Column = 1
end

@enum CompressionType::Int8 begin
    NoCompression = 0
    RLECompression = 1
    HuffmanCompression = 2
    AdaptiveHuffmanCompression = 3
    GzipCompression = 5
    ZstdCompression = 16
end

const NoCompressionBytes = [0x00, 0x00, 0xff, 0xff]

function CompressionType(bytes::UInt32)
    if bytes == 0x0000FFFF
        return NoCompression
    else
        return GzipCompression
    end
end

@enum DataType begin
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

DataType(x::DataType) = x
DataType(x::UInt32) = DataType(Int32(x))

Base.:(==)(x::DataType, y::T) where {T <: Integer} = T(x) == y
Base.:(==)(x::T, y::DataType) where {T <: Integer} = x == T(y)

const type_map = Dict(
    CDF_INT1 => Int8,
    CDF_INT2 => Int16,
    CDF_INT4 => Int32,
    CDF_INT8 => Int64,
    CDF_UINT1 => UInt8,
    CDF_UINT2 => UInt16,
    CDF_UINT4 => UInt32,
    CDF_REAL4 => Float32,
    CDF_REAL8 => Float64,
    CDF_BYTE => Int8,
    CDF_FLOAT => Float32,
    CDF_DOUBLE => Float64,
    CDF_CHAR => UInt8,
    CDF_UCHAR => UInt8,
    CDF_EPOCH => Epoch,
    CDF_EPOCH16 => Epoch16,
    CDF_TIME_TT2000 => TT2000
)

function julia_type(cdf_type)
    return type_map[cdf_type]
end

julia_type(i::Integer) = julia_type(DataType(i))
