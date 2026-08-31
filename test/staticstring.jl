using CommonDataFormat: StaticString
using Test

@testset "Basic operations" begin
    s = "Hello, World!"
    ss = StaticString(s)

    @test StaticString(codeunits(s)) == s
    @test ss == s
    @test String(ss) == s
    @test !isempty(ss)
    @test contains(ss, "World")
    @test occursin("World", ss)
    @test replace(ss, "World" => "Julia") == "Hello, Julia!"

    @test codeunit(ss) == UInt8
end

@testset "Null padding and UTF-8" begin
    # null padding: iterate/length/collect/String must agree
    pad = StaticString{8, UInt8}((UInt8('a'), UInt8('b'), zeros(UInt8, 6)...))
    @test ncodeunits(pad) == 2
    @test length(pad) == 2
    @test collect(pad) == ['a', 'b']
    @test String(pad) == "ab"
    @test pad == "ab"
    @test isempty(StaticString{4, UInt8}(ntuple(_ -> 0x00, 4)))

    # multi-byte UTF-8 indexing
    s = StaticString("héllo")
    @test collect(s) == collect("héllo")
    @test thisind(s, 3) == 2
    @test isvalid(s, 2) && !isvalid(s, 3)
    @test length(s) == 5 && ncodeunits(s) == 6
end

@testset "show" begin
    pad = StaticString{8, UInt8}((UInt8('a'), UInt8('b'), zeros(UInt8, 6)...))
    @test sprint(show, pad) == "\"ab\""              # null padding trimmed, quoted like String
    @test sprint(show, StaticString("a\"\n")) == sprint(show, "a\"\n")

    disp(x) = sprint(show, MIME"text/plain"(), x)
    for a in (fill(pad, 3), fill(pad, 2, 2))
        header, body = split(disp(a), ":\n"; limit = 2)
        # element rendering delegates to String; only the summary keeps the real eltype
        @test body == split(disp(map(String, a)), ":\n"; limit = 2)[2]
        @test occursin("StaticString{8, UInt8}", header)
    end
    empty = StaticString{4, UInt8}[]
    @test disp(empty) == sprint(summary, empty)
end
