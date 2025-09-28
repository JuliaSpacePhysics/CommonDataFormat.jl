using Test
using CommonDataFormat

include("utils.jl")

@testset "CDFDataset" begin
    file = data_path("ac_h2_sis_20101105_v06.cdf")
    ds = CDFDataset(file)
    var = ds["flux_He"]
    @test "TITLE" in keys(ds.attrib)
    @test "CATDESC" in keys(var.attrib)
    @test CommonDataFormat.attrib(var, "FILLVAL")[1] == -1.0f31
end

@testset "local test" begin
    file = joinpath(pkgdir(CommonDataFormat), "data", ".wi_h2_mfi_20210119_v05.cdf")
    if isfile(file)
        ds = CDFDataset(file)
        @test ndims(ds["BGSM"]) == 2
    end
end