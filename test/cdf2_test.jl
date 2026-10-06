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