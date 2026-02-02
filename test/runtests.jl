using CommonDataFormat
using Test
import CommonDataFormat as CDF

include("utils.jl")
include("epochs_test.jl")
include("comprehensive_test.jl")
include("cdf2_test.jl")
include("CommonDataModelExt_test.jl")
include("staticstring.jl")

@testset "Aqua" begin
    using Aqua
    Aqua.test_all(CommonDataFormat)
end

@testset "JET" begin
    using JET
    JET.test_package(CommonDataFormat; target_modules = [CommonDataFormat])
end

@testset "Fill Value" begin
    for T in (Int8, Int16, Int32, Int64, Float32, Float64, UInt8, UInt16, UInt32)
        @test CDF.fillvalue(T) isa T
    end
    @test string(Epoch(-1.0e31)) == "FILLVAL"
end

@testset "Uncompressed cdf file" begin
    file = data_path("a_cdf.cdf")
    ds = CDFDataset(file)
    @test ds.version == (3, 9, 0)
    @test ds.majority == CDF.Row
    @test ds.compression == CDF.NoCompression
    @test first(ds) == ds["var"]
    @test occursin("Version: 3.9.0", string(ds))
    display(ds)
    display(ds["var"])
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

    var = ds["var"]
    #TODO: find a better and small dataset to really test the chunking
    @test CommonDataFormat._eachchunk_vvrs(ds["var3d"]) == CommonDataFormat._eachchunk(ds["var3d"])
    @test occursin("compressed", string(var.vdr))
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


    @test ds["Epoch"][1] == DateTime(2024, 9, 1, 0, 0)
    @test ntoh(hton(ds["Epoch"][1])) == DateTime(2024, 9, 1, 0, 0)

    @test @allocations(ds["BR"]) <= 50
    allocations = @allocated(ds.attrib)
    threshold = VERSION >= v"1.12" ? 30000 : 70000
    if allocations > threshold
        @info "ds.attrib allocated $allocations bytes (threshold: $threshold)"
    end
end

@testset "CDF_CHAR" begin
    file = data_path("ge_h0_cpi_00000000_v01.cdf")
    ds = CDFDataset(file)
    @test ds["label_v3c"] == ["Ion Vx GSE    " ; "Ion Vy GSE    " ; "Ion Vz GSE    ";;]
end

@testset "r-variables" begin
    file = data_path("ac_h0_mfi_20230102_v07.cdf")
    ds = CDFDataset(file)
    var = ds["BGSEc"]
    @test var.vdr isa CommonDataFormat.rVDR
    @test size(var) == (3, 5400)
end

@testset "r-variables 2" begin
    file = download_test_data("https://github.com/JuliaSpacePhysics/CommonDataFormat.jl/releases/download/v0.1.8/omni2_h0_mrg1hr_20150101_v01.cdf")
    ds = CDFDataset(file)
    var = ds["Epoch"]
    @test var.vdr isa CommonDataFormat.rVDR
    @test size(var) == (4344,)
end
