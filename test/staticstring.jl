using CommonDataFormat: StaticString
using Test

@testset "StaticString" begin
    s = "Hello, World!"
    ss = StaticString(s)

    StaticString(codeunits(s))
    @test ss == s
    @test String(ss) == s
    @test !isempty(ss)
    @test contains(ss, "World")
    @test occursin("World", ss)
    @test replace(ss, "World" => "Julia") == "Hello, Julia!"

    @test codeunit(ss) == UInt8
end
