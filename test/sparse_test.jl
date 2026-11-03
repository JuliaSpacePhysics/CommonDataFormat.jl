# data/make_sparse_cdf.py: physical records 1-3, 7-8, 11 (1-based); virtual 4-6, 9-10
@testset "Sparse records" begin
    ds = CDFDataset(data_path("sparse.cdf"))
    d = -1.0e30  # NASA default pad for CDF_DOUBLE
    @test ds["pad_default"][:] == [10, 11, 12, d, d, d, 16, 17, d, d, 20]

    p = ds["pad_explicit"]
    @test p[:] == [10, 11, 12, -99, -99, -99, 16, 17, -99, -99, 20]
    @test p[3:5] == [12, -99, -99]
    @test p[4:5] == [-99, -99]
    @test p[9:11] == [-99, -99, 20]

    prev = [10, 11, 12, 12, 12, 12, 16, 17, 17, 17, 20]
    @test ds["prev"][:] == prev
    @test ds["prev"][5:6] == [12, 12]  # previous record lies outside the requested range

    # whole virtual record takes the pad (cdflib's reader pads only the first element)
    m = ds["pad2d"][:, :]
    @test m[:, [1, 4, 11]] == [0 -99 10; 1 -99 11]
    @test ds["pad2d"][2:2, 5:7] == [-99 -99 7]
end

# data/sparse_records.cdf from SciQLop/CDFpp, written by NASA's CDF library 3.9.2
# (tests/resources/make_sparse_records.c). Expected values are what CDFgetzVarRecordData returned.
@testset "Missing records match NASA's library" begin
    ds = CDFDataset(data_path("sparse_records.cdf"))
    fill = -1.0f31
    @test ds["pad_explicit"][:] == Float32[10, 1.5, 1.5, 30, 1.5, 50]
    @test ds["pad_with_fillval"][:] == Float32[10, fill, fill, 30, fill, 50]
    @test ds["prev"][:] == Int32[7, 7, 22, 22, 44]
    @test ds["prev_with_fillval"][:] == Int32[-99, -99, 22, 22, 44]
    @test ds["default_double"][:] == [1, -1.0e30, 3]
    @test ds["default_uint2"][:] == UInt16[1, 65534, 3]
    @test ds["default_char"][:] == ["abc", " ", "xyz"]
    @test ds["default_tt2000"][2].instant.value == typemin(Int64) + 1
    @test ds["default_epoch"][2].instant == 0
    @test ds["compressed_pad"][:] == Float32[10, 2.5, 2.5, 30]
    @test ds["no_sparse_gap"][:] == Float32[10, -1.0f30, -1.0f30, 30]
end
