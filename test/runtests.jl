using CommonDataFormat
using Test
import CommonDataFormat as CDF


# Test data paths
const CDFpp_TEST_DATA_PATH = joinpath(@__DIR__, "..", "ref", "CDFpp", "tests", "resources")
const CDFlib_TEST_DATA_PATH = joinpath(@__DIR__, "..", "ref", "cdflib", "tests", "testfiles")
const PROJECT_DATA_PATH = joinpath(@__DIR__, "..", "data")

# Include test files
# include("basic_tests.jl")
# include("cdf_file_tests.jl")

function data_path(name)
    for dir in [CDFpp_TEST_DATA_PATH, CDFlib_TEST_DATA_PATH, PROJECT_DATA_PATH]
        path = joinpath(dir, name)
        isfile(path) && return path
    end
    error("Data file not found: $name")
end

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
    @info @allocations(var["UNITS"])
    # 17.875 μs (56 allocs: 6.141 KiB)
end

@testset "CHECK_VARIABLES - CDF_CHAR" begin
    file = data_path("ge_h0_cpi_00000000_v01.cdf")
    ds = CDFDataset(file)
    @info ds["label_v3c"]
end

@testset "CHECK_VARIABLES - Variable structure verification" begin
    file = data_path("a_cdf.cdf")
    ds = CDFDataset(file)

    # Check total number of variables (should be 18 as per C++)
    @test length(ds) == 18

    var = ds["var"]
    # @test var.data == ones(101)

    var2d = ds["var2d"]
    @test var2d.data == ones(4, 3)

    var3d = ds["var3d"]
    @test var3d.data == ones(3, 2, 4)

    # # Check variable shapes/dimensions
    # @test ds["epoch"].dimensions == [1] && ds["epoch"].num_records == 101
    # @test ds["epoch16"].dimensions == [1] && ds["epoch16"].num_records == 101
    # @test ds["tt2000"].dimensions == [1] && ds["tt2000"].num_records == 101
    # @test ds["zeros"].dimensions == [1] && ds["zeros"].num_records == 2048
    # @test ds["bytes"].dimensions == [1] && ds["bytes"].num_records == 10
    # @test ds["var2d_counter"].dimensions == [10] && ds["var2d_counter"].num_records == 10

    # # Check data types
    # @test ds["epoch"].data_type == CDF.CDF_EPOCH
    # @test ds["epoch16"].data_type == CDF.CDF_EPOCH16
    # @test ds["tt2000"].data_type == CDF.CDF_TIME_TT2000
    # @test ds["var_string"].data_type == CDF.CDF_CHAR
    # @test ds["var_string_uchar"].data_type == CDF.CDF_UCHAR

    # # String variables with specific dimensions
    # @test ds["var_string"].dimensions == [1] && ds["var_string"].num_records == 1
    # @test ds["var_string_uchar"].dimensions == [1] && ds["var_string_uchar"].num_records == 1

    # # Check 5D variable exists
    @test haskey(ds, "var5d_counter")
    @info ds["var5d_counter"]
end
