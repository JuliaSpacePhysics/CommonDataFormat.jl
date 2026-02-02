using CommonDataFormat: StaticString

@testset "StaticString" begin
    s = "Hello, World!"
    ss = StaticString(s)

    StaticString(codeunits(s))
    @test ss == s
    @test String(ss) == s
    @test !isempty(ss)
end