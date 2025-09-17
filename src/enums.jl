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

function cdf_type_size(cdf_type)
    size_map = Dict(
        CDF_INT1 => 1, CDF_INT2 => 2, CDF_INT4 => 4, CDF_INT8 => 8, CDF_UINT1 => 1, CDF_UINT2 => 2, CDF_UINT4 => 4,
        CDF_REAL4 => 4, CDF_REAL8 => 8, CDF_FLOAT => 4, CDF_DOUBLE => 8, CDF_EPOCH => 8,
        CDF_EPOCH16 => 16, CDF_TIME_TT2000 => 8, CDF_CHAR => 1, CDF_UCHAR => 1
    )
    return size_map[DataType(cdf_type)]
end

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
    CDF_CHAR => Char,
    CDF_UCHAR => UInt8,
    CDF_EPOCH => Int64,
    CDF_EPOCH16 => Int64,
    CDF_TIME_TT2000 => Int64
)

function julia_type(cdf_type)
    return type_map[cdf_type]
end

julia_type(i::Integer) = julia_type(DataType(i))