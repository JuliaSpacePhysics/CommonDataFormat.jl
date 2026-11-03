using CommonDataFormat.Inflate: InflateError, gzip_decompress!
using Zlib_jll: libz

mutable struct ZStream
    next_in::Ptr{UInt8}; avail_in::Cuint; total_in::Culong
    next_out::Ptr{UInt8}; avail_out::Cuint; total_out::Culong
    msg::Ptr{UInt8}; state::Ptr{Cvoid}; zalloc::Ptr{Cvoid}; zfree::Ptr{Cvoid}; opaque::Ptr{Cvoid}
    data_type::Cint; adler::Culong; reserved::Culong
    ZStream() = new(C_NULL, 0, 0, C_NULL, 0, 0, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, 0, 0, 0)
end

# strategy: 0 default, 2 Huffman-only, 3 RLE, 4 fixed codes; level 0 emits stored blocks.
function zlib_gzip(data::Vector{UInt8}; level = 6, strategy = 0)
    z = ZStream()
    ver = unsafe_string(ccall((:zlibVersion, libz), Ptr{UInt8}, ()))
    @assert ccall((:deflateInit2_, libz), Cint, (Ref{ZStream}, Cint, Cint, Cint, Cint, Cint, Cstring, Cint),
        z, level, 8, 31, 8, strategy, ver, sizeof(ZStream)) == 0
    out = Vector{UInt8}(undef, length(data) + length(data) ÷ 100 + 1024)
    GC.@preserve data out begin
        z.next_in, z.avail_in = pointer(data), length(data)
        z.next_out, z.avail_out = pointer(out), length(out)
        @assert ccall((:deflate, libz), Cint, (Ref{ZStream}, Cint), z, 4) == 1
    end
    ccall((:deflateEnd, libz), Cint, (Ref{ZStream},), z)
    return resize!(out, z.total_out)
end

function inflate(gz::Vector{UInt8}, n::Integer)
    out = Vector{UInt8}(undef, n)
    GC.@preserve out gz gzip_decompress!(pointer(out), n, pointer(gz), length(gz))
    return out
end

function inflate_group(cases)
    outs = [Vector{UInt8}(undef, length(d)) for (d, _) in cases]
    members = Tuple((pointer(o), length(o), pointer(gz), length(gz)) for (o, (_, gz)) in zip(outs, cases))
    GC.@preserve outs cases gzip_decompress!(members)
    return outs
end

# Canonical Huffman codewords (RFC 1951 3.2.2), bit-reversed for LSB-first output.
function huffman_codes(lens)
    codes = zeros(UInt64, length(lens))
    code = UInt64(0)
    for l in 1:15
        for i in eachindex(lens)
            lens[i] == l || continue
            codes[i] = bitreverse(code) >> (64 - l)
            code += 1
        end
        code <<= 1
    end
    return codes
end

# A gzip member of `nsyms` random symbols, from a hand-built block whose codes reach the limits
# zlib rarely emits: 15-bit length codes with 5 extra bits, 15-bit offset codes with 13.
function worst_case_gzip(nsyms)
    litlen = zeros(Int, 285)
    literals = [65, 66, 67, 68, 69, 70, 71, 72, 73, 75, 76]
    for (l, sym) in zip(1:15, [65, 66, 67, 68, 69, 70, 71, 72, 73, 272, 75, 256, 268, 257, 76])
        litlen[sym + 1] = l
    end
    litlen[284 + 1] = 15
    offset = zeros(Int, 30)
    offset[1:14] .= 1:14
    offset[28 + 1] = offset[29 + 1] = 15
    litcodes, offcodes = huffman_codes(litlen), huffman_codes(offset)

    bytes = UInt8[0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff]
    buf, nbuf = UInt64(0), 0
    function put(v, n)
        buf |= UInt64(v) << nbuf
        nbuf += n
        while nbuf >= 8
            push!(bytes, buf % UInt8)
            buf >>= 8
            nbuf -= 8
        end
    end
    put(1, 1); put(2, 2)  # final, dynamic
    put(285 - 257, 5); put(30 - 1, 5); put(19 - 4, 4)
    # Precode: code lengths 0-15 get 4-bit codewords, repeat symbols 16-18 are unused.
    foreach(sym -> put(sym <= 15 ? 4 : 0, 3), (16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15))
    foreach(l -> put(bitreverse(UInt64(l)) >> 60, 4), [litlen; offset])

    out = UInt8[]
    put_sym(sym) = put(litcodes[sym + 1], litlen[sym + 1])
    for _ in 1:nsyms
        if isempty(out) || rand() < 0.6
            sym = rand(literals)
            put_sym(sym)
            push!(out, sym)
            continue
        end
        lensym, lenbase, lenextra = rand(((257, 3, 0), (268, 17, 1), (272, 31, 2), (284, 227, 5)))
        put_sym(lensym)
        extra = rand(0:((1 << lenextra) - 1))
        put(extra, lenextra)
        offsym, offbase, offextra = length(out) >= 32768 && rand(Bool) ? rand(((28, 16385, 13), (29, 24577, 13))) : (0, 1, 0)
        put(offcodes[offsym + 1], offset[offsym + 1])
        offbits = rand(0:((1 << offextra) - 1))
        put(offbits, offextra)
        for _ in 1:(lenbase + extra)
            push!(out, out[end - (offbase + offbits) + 1])
        end
    end
    put_sym(256)
    put(0, 7)  # flush to a byte boundary
    crc = GC.@preserve out CommonDataFormat.Inflate.crc32(pointer(out), length(out))
    return out, [bytes; reinterpret(UInt8, [htol(crc), htol(length(out) % UInt32)])]
end

@testset "Inflate" begin
    rng_floats = collect(reinterpret(UInt8, Float32.(cumsum(randn(50_000)))))
    text = Vector{UInt8}(repeat("the quick brown fox jumps over the lazy dog ", 3000))
    periodic = collect(reinterpret(UInt8, repeat(Float32[-1.0f31, 2.5f0, 7.0f0], 30_000)))  # match distances < 8 and long runs
    datasets = [UInt8[], [0x2a], rand(UInt8, 100_000), rng_floats, text, periodic, zeros(UInt8, 300_000)]
    modes = [(0, 0), (1, 0), (6, 0), (9, 0), (6, 2), (6, 3), (6, 4)]
    cases = [(d, zlib_gzip(d; level, strategy)) for d in datasets for (level, strategy) in modes]
    for (d, gz) in cases
        @test inflate(gz, length(d)) == d
    end
    # Groups mixing lengths and block types, so streams finish at different times.
    for n in 2:4, _ in 1:15
        group = rand(cases, n)
        @test inflate_group(group) == first.(group)
    end

    @testset "code limits: bit budget and output overrun" begin
        cases = [worst_case_gzip(8000) for _ in 1:20]
        canary = 512
        for (d, gz) in cases
            out = fill(0xa5, length(d) + canary)
            GC.@preserve out gz gzip_decompress!(pointer(out), length(d), pointer(gz), length(gz))
            @test view(out, 1:length(d)) == d
            @test all(==(0xa5), view(out, (length(d) + 1):length(out)))

            cut = rand(1:(length(d) - 1))
            out = fill(0xa5, cut + canary)
            @test_throws InflateError GC.@preserve out gz gzip_decompress!(pointer(out), cut, pointer(gz), length(gz))
            @test all(==(0xa5), view(out, (cut + 1):length(out)))
        end
        @test inflate_group(cases[1:4]) == first.(cases[1:4])
    end

    @testset "optional header fields" begin
        d = text
        gz = zlib_gzip(d)
        withfields = [gz[1:3]; 0x1c; gz[5:10]; 0x03; 0x00; 0x41; 0x42; 0x43; Vector{UInt8}("name\0comment\0"); gz[11:end]]
        @test inflate(withfields, length(d)) == d
    end

    @testset "corrupt input" begin
        d = rng_floats
        gz = zlib_gzip(d)
        @test_throws InflateError inflate(gz, length(d) - 1)
        @test_throws InflateError inflate(gz, length(d) + 1)
        bad_crc = copy(gz); bad_crc[end - 5] ⊻= 0x01
        @test_throws InflateError inflate(bad_crc, length(d))
        @test_throws InflateError inflate([gz[1:(end ÷ 2)]; gz[(end - 7):end]], length(d))
        bad_magic = copy(gz); bad_magic[1] = 0x00
        @test_throws InflateError inflate(bad_magic, length(d))
        # A flipped payload bit must raise, not crash or hang.
        for _ in 1:50
            c = copy(gz)
            i = rand(11:(length(c) - 8))
            c[i] ⊻= UInt8(1) << rand(0:7)
            @test try inflate(c, length(d)) == d catch e; e isa InflateError end
        end
    end
end
