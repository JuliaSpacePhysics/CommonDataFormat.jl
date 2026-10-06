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
