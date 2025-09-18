# https://rosettacode.org/wiki/Run-length_encoding#Julia
# https://github.com/SciQLop/CDFpp/blob/main/include/cdfpp/cdf-io/rle.hpp

const ZERO_BYTE = UInt8(0)

function _rle_decompress(data::AbstractVector{UInt8}, expected_bytes::Int)
    expected_bytes < 0 && throw(ArgumentError("expected_bytes must be non-negative"))
    output = Vector{UInt8}(undef, expected_bytes)
    out_idx = 1
    i = 1
    len = length(data)
    while i <= len && out_idx <= expected_bytes
        value = data[i]
        if value == ZERO_BYTE
            i += 1
            i > len && throw(ArgumentError("Malformed RLE stream"))
            count = Int(data[i]) + 1
            out_end = out_idx + count - 1
            out_end > expected_bytes && throw(ArgumentError("RLE stream exceeds expected size"))
            output[out_idx:out_end] .= ZERO_BYTE
            out_idx += count
        else
            output[out_idx] = value
            out_idx += 1
        end
        i += 1
    end
    out_idx - 1 == expected_bytes || throw(ArgumentError("RLE stream shorter than expected size"))
    return output
end