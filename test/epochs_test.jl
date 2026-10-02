using Test
using CommonDataFormat
import CommonDataFormat as CDF
using Dates
using Durations: Timestamp

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

    @test TT2000(TT2000(663940869211021568)) == TT2000(663940869211021568)

    @test string(TT2000(0)) == "2000-01-01T11:58:55.816"
    @test TT2000(0) == TT2000(0) |> bswap
    @test TT2000(0) == DateTime("2000-01-01T11:58:55.816")
end

@testset "TT2000 leap seconds" begin
    # values from cdflib.cdfepoch.compute_tt2000
    for (s, v) in (
            ("2016-12-31T23:59:30", 536500838184000000),
            ("2016-12-31T23:59:59.5", 536500867684000000),
            ("2017-01-01T00:00:00", 536500869184000000),
            ("2015-06-30T23:59:50", 488980857184000000),
            ("1971-12-31T23:59:59.5", -883655958425054000),
            ("1965-03-15T12:00:00", -1098143964080614000),
        )
        dt = DateTime(s)
        @test Dates.value(TT2000(dt)) == v
        @test DateTime(TT2000(v)) == dt
    end
    # inserted leap second 2016-12-31T23:59:60.5
    @test DateTime(TT2000(536500868684000000)) == DateTime("2017-01-01T00:00:00.5")
end

@testset "Timestamp" begin
    ns = Timestamp{Nanosecond}
    t = TT2000(DateTime(2020)) + Microsecond(400)
    @test t != DateTime(2020)
    @test t == ns("2020-01-01T00:00:00.0004")
    @test DateTime(t) == DateTime(2020)
    @test_throws InexactError Timestamp{Millisecond}(t)

    s = "2020-01-01T00:00:00.000400007"
    @test TT2000(s) == TT2000(ns(s)) == t + Nanosecond(7)
    @test ns(TT2000(ns(s))) == ns(s)
    @test (Dates.microsecond(TT2000(s)), Dates.nanosecond(TT2000(s))) == (400, 7)
    @test string(TT2000(s)) == s
    @test floor(TT2000(s), Microsecond(1)) == t

    @test ns(Epoch16(ns(s))) == ns(s)

    # full range and precision of each type, beyond Timestamp{Nanosecond} (1677-2262, ns)
    @test Epoch16("0999-12-31T23:59:59.000000000001") == Epoch16(Epoch16(DateTime(1000)).seconds - 1, 1.0)
    @test TT2000("2291-01-01T00:00:00.000000001") == TT2000(DateTime(2291)) + Nanosecond(1)
    @test_throws InexactError TT2000("2020-01-01T00:00:00.0000000001")
    # not the fixed-width layout: the Dates parser supplies the fraction
    @test Epoch16("2020-1-1T00:00:00.5") == TT2000("2020-1-1T00:00:00.5") == DateTime(2020, 1, 1, 0, 0, 0, 500)

    # 1 ns below the first leap-second table entry
    x = ns(DateTime(1972)) - Nanosecond(1)
    @test ns(TT2000(x)) == x
end

@testset "Promotion" begin
    # Inside the inserted leap second 2016-12-31T23:59:60, which UTC types cannot represent.
    leap = TT2000(DateTime(2017)) - Millisecond(500)
    @test leap < DateTime(2017)
    @test TT2000(DateTime(2017)) - DateTime(2016, 12, 31, 23, 59, 59) == Second(2)

    dt = DateTime(2020, 2, 3, 4, 5, 6, 7)
    @test Epoch(dt) == Epoch16(dt) == TT2000(dt)
    # Epoch cannot hold nanoseconds, so it promotes to the Timestamp
    @test Epoch(dt) < Timestamp(dt) + Nanosecond(1)
end

@testset "Range" begin
    # TT2000 reaches past the Int64 Unix-nanosecond range (2262)
    @test DateTime(TT2000(DateTime(2291))) == DateTime(2291)
    @test_throws InexactError TT2000(DateTime(2300))
    @test DateTime(TT2000(typemin(Int64) + 1)) == DateTime("1707-09-22T12:12:10.961")

    # Epoch16 spans years 0-9999, beyond Timestamp{Nanosecond}
    for dt in (DateTime(0), DateTime(9999, 12, 31, 23, 59, 59, 999))
        @test string(Epoch16(dt)) == string(dt)
    end
end

@testset "FILLVAL" begin
    @test string(TT2000(typemin(Int64))) == "FILLVAL"
    @test string(Epoch16(-1.0e31, -1.0e31)) == "FILLVAL"
end

@testset "Epoch16" begin
    t = Epoch16(6.377810224e10, 8.97e11)
    @test t == DateTime(2021, 1, 17, 11, 30, 40, 897)
    @test Epoch16(DateTime(t)) == t
    @test string(t) == "2021-01-17T11:30:40.897"
    @test ntoh(hton(t)) == t
    @test Epoch16(6.377810224e10, 8.97e11) - Epoch16(6.377810224e10, 0) == CDF.Picosecond(8.97e11)
    # floored, not rounded
    @test DateTime(Epoch16(6.377810224e10, 8.979999e11)) == DateTime(t)
    @test t + Millisecond(103) + Nanosecond(1) == Epoch16(6.377810224e10 + 1, 1.0e3)
    @test t - Day(1) - Millisecond(897) - Nanosecond(1) == Epoch16(6.377810224e10 - 86401, 999_999_999_000.0)
    @test issorted([t - Nanosecond(1), t, t + Nanosecond(1), t + Second(1)])
end

@testset "Picosecond" begin
    @test CDF.Picosecond(1) == CDF.Picosecond(1)
    @test Nanosecond(CDF.Picosecond(Nanosecond(1000))) == Nanosecond(1000)
    @test string(CDF.Picosecond(1)) == "1.0 picosecond"
    @test CDF.Picosecond(Millisecond(1)) == CDF.Picosecond(1.0e9)
    @test CDF.Picosecond(1.0e9) == Millisecond(1)
end
