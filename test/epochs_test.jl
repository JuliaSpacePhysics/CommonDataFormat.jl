using Test
using CommonDataFormat
using Dates

@testset "Epochs" begin
    @test Epoch(DateTime(0)) == Epoch(0)
    @test DateTime(Epoch(DateTime(0))) == DateTime(0)
    @test Epoch(Epoch(0)) == Epoch(0)
    @test Epoch(10) - Epoch(0) == Millisecond(10)
    # @test Epoch16(DateTime(0)) == Epoch16(0, 0)
end

@testset "TT2000" begin
    @test DateTime(TT2000(DateTime(2000))) == DateTime(2000)
    @test TT2000(DateTime(TT2000(0))) == TT2000(0)
    @test TT2000(TT2000(0)) == TT2000(0)
    @test TT2000(10) - TT2000(0) == Nanosecond(10)
    @test floor(TT2000(0), Minute(1)) == DateTime(2000, 1, 1, 11, 58)
    @test TT2000(0) + Minute(1) == TT2000(60_000_000_000)
end
