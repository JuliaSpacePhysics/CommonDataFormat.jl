using Test
using CommonDataFormat
import CommonDataFormat as CDF
using Dates

@testset "Epochs" begin
    t = Epoch(DateTime(0))
    @test t == Epoch(0)
    @test DateTime(Epoch(DateTime(0))) == DateTime(0)
    @test Epoch(Epoch(0)) == Epoch(0)
    @test Epoch(10) - Epoch(0) == Millisecond(10)
    @test string(Epoch(-1.0e31)) == "FILLVAL"
    @test Epoch(10) - Millisecond(10) == Epoch(0)
    @test Epoch(0) + Second(1) == Epoch(1000)
    @test ntoh(hton(t)) == t
    # @test Epoch16(DateTime(0)) == Epoch16(0, 0)
end

@testset "TT2000" begin
    t = TT2000(DateTime(2000))
    @test DateTime(t) == DateTime(2000)
    @test TT2000(DateTime(TT2000(0))) == TT2000(0)
    @test TT2000(TT2000(0)) == TT2000(0)
    @test TT2000(10) - TT2000(0) == Nanosecond(10)
    @test t - Day(1) == DateTime(1999, 12, 31)
    @test floor(TT2000(0), Minute(1)) == DateTime(2000, 1, 1, 11, 58)
    @test TT2000(0) + Minute(1) == TT2000(60_000_000_000)

    @test string(TT2000(0)) == "2000-01-01T11:58:55.816"
    @test TT2000(0) == TT2000(0) |> bswap
    @test TT2000(0) == DateTime("2000-01-01T11:58:55.816")
end

@testset "Epoch16" begin
    t = Epoch16(6.377810224e10, 8.97e11)
    @test t == DateTime(2021, 1, 17, 11, 30, 40, 897)
    @test Epoch16(DateTime(t)) == t
    @test string(t) == "2021-01-17T11:30:40.897"
    @test ntoh(hton(t)) == t
    @test Epoch16(6.377810224e10, 8.97e11) - Epoch16(6.377810224e10, 0) == CDF.Picosecond(8.97e11)
end

@testset "Picosecond" begin
    @test CDF.Picosecond(1) == CDF.Picosecond(1)
    @test Nanosecond(CDF.Picosecond(Nanosecond(1000))) == Nanosecond(1000)
    @test string(CDF.Picosecond(1)) == "1.0 picosecond"
    @test CDF.Picosecond(Millisecond(1)) == CDF.Picosecond(1.0e9)
    @test CDF.Picosecond(1.0e9) == Millisecond(1)
end
