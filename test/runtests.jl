using CommonDataFormat
using Test
import CommonDataFormat as CDF

include("utils.jl")
include("comprehensive_test.jl")
include("CommonDataModelExt_test.jl")

@testset "Uncompressed cdf file" begin
    file = data_path("a_cdf.cdf")
    ds = CDFDataset(file)
    @test ds.version == (3, 9, 0)
    @test ds.majority == CDF.Row
    @test ds.compression == CDF.NoCompression
    @test first(ds) == ds["var"]
end

@testset "Compressed cdf file (gzip)" begin
    compressed = CDFDataset(data_path("a_compressed_cdf.cdf"))
    reference = CDFDataset(data_path("a_cdf.cdf"))
    @test compressed.version == reference.version
    @test compressed.compression == CDF.GzipCompression
    @test keys(compressed) == keys(reference)
    @test compressed["var"][1:5] == reference["var"][1:5]
    @test compressed["zeros"][1:5] == reference["zeros"][1:5]
end

@testset "Compressed cdf file (rle)" begin
    compressed = CDFDataset(data_path("a_rle_compressed_cdf.cdf"))
    reference = CDFDataset(data_path("a_cdf.cdf"))
    @test compressed.compression == CDF.RLECompression
    @test compressed["bytes"][1:5] == reference["bytes"][1:5]
    @test compressed["var2d"][1, :] == reference["var2d"][1, :]
end

@testset "Compressed variable records" begin
    ds = CDFDataset(data_path("a_cdf_with_compressed_vars.cdf"))
    reference = CDFDataset(data_path("a_cdf.cdf"))
    @test ds.compression == CDF.NoCompression
    @test ds["var"][1:5] == reference["var"][1:5]
    @test ds["var2d"][1, :] == reference["var2d"][1, :]
    @test ds["var_string"] == reference["var_string"]
end

@testset "CHECK_VARIABLES - Variable structure verification" begin
    file = data_path("omni_coho1hr_merged_mag_plasma_20240901_v01.cdf")
    ds = CDFDataset(file)
    @test keys(ds) == ["Epoch", "heliographicLatitude", "heliographicLongitude", "BR", "BT", "BN", "ABS_B", "V", "elevAngle", "azimuthAngle", "N", "T"]
    var = ds["BR"]
    @test ds.attrib["TITLE"][1] == "Near-Earth Heliosphere Data (OMNI)"
    @test var[1:3] == Float32[6.7, 6.7, 7.3]
    @test var["UNITS"] == "nT"
    @test var["FIELDNAM"] == "BR (RTN)"
    @test @allocations(ds["BR"]) <= 60
    if VERSION >= v"1.12"
        @test @allocations(ds.attrib) <= 300
    else
        @test @allocations(ds.attrib) <= 500
    end
end

@testset "CHECK_VARIABLES - CDF_CHAR" begin
    file = data_path("ge_h0_cpi_00000000_v01.cdf")
    ds = CDFDataset(file)
    @test ds["label_v3c"] == ["Ion Vx GSE    " ; "Ion Vy GSE    " ; "Ion Vz GSE    ";;]
end

@testset "Epochs" begin
    @test string(Epoch(-1.0e31)) == "FILLVAL"
    @test string(TT2000(0)) == "2000-01-01T11:58:55.816"
    @test TT2000(0) == TT2000(0) |> bswap
    @test TT2000(0) == DateTime("2000-01-01T11:58:55.816")
end