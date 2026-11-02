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
