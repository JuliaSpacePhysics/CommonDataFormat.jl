using CommonDataFormat
using Test
import CommonDataFormat as CDF

include("utils.jl")
include("comprehensive_test.jl")

@testset "Uncompressed cdf file" begin
    file = data_path("a_cdf.cdf")
    ds = CDFDataset(file)
    @test ds.version == (3, 9, 0)
    @test ds.majority == CDF.Row
    @test ds.compression == CDF.NoCompression
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
