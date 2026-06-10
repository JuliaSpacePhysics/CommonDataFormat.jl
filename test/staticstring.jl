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
