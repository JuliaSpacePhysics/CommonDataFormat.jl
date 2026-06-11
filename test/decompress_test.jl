# Variable-level (CVVR) decompression. No CDF writer in the ecosystem emits
# RLE-compressed variables (cdflib/pycdf are gzip-only), so build CVVRs by hand.
using CommonDataFormat: load_cvvr_data!, decompress_bytes!, Decompressor,
    RLECompression, HuffmanCompression, NoCompression

# CDF RLE: 0x00 followed by (run_length - 1); other bytes literal
function rle_compress(bytes)
    out = UInt8[]
    i = firstindex(bytes)
    while i <= lastindex(bytes)
        if bytes[i] == 0x00
            run = 1
            while i + run <= lastindex(bytes) && bytes[i + run] == 0x00 && run < 256
                run += 1
            end
            push!(out, 0x00, UInt8(run - 1))
            i += run
        else
            push!(out, bytes[i])
            i += 1
        end
    end
    return out
end

# CVVR layout (v3, Int64 record size): [record_size 8][type=13 4][rfu 4][cSize 8][data]
function make_cvvr(payload)
    buf = zeros(UInt8, 24 + length(payload))
    buf[1:8] .= reinterpret(UInt8, [hton(Int64(length(buf)))])
    buf[9:12] .= reinterpret(UInt8, [hton(Int32(13))])
    buf[17:24] .= reinterpret(UInt8, [hton(Int64(length(payload)))])
    buf[25:end] .= payload
    return buf
end

@testset "RLE compressed variable records" begin
    data = Float64[0.0, 1.0, 0.0, 0.0, 2.5, 0.0, 0.0, 0.0, 3.0]
    raw = collect(reinterpret(UInt8, data))
    payload = rle_compress(raw)
    @test length(payload) < length(raw) # zeros actually compressed
    buf = make_cvvr(payload)

    dest = Vector{Float64}(undef, length(data))
    load_cvvr_data!(dest, 1, buf, 0, length(data), Int64, RLECompression)
    @test dest == data

    # long zero run crossing the 256-byte chunk limit
    data2 = zeros(UInt8, 1000)
    data2[513] = 0x7f
    buf2 = make_cvvr(rle_compress(data2))
    dest2 = Vector{UInt8}(undef, 1000)
    load_cvvr_data!(dest2, 1, buf2, 0, 1000, Int64, RLECompression)
    @test dest2 == data2
end

@testset "unsupported variable compression" begin
    src = zeros(UInt8, 16)
    dest = Vector{Float64}(undef, 1)
    @test_throws ArgumentError decompress_bytes!(Decompressor(), dest, 1, src, 1, 1, 8, HuffmanCompression)
end
