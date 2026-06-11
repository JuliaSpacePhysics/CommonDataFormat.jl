# Fixture from test/make_sparse_cdf.py (cdflib writer): physical records 1-3, 7-8, 11
# (1-based), virtual gaps at 4-6 and 9-10.
@testset "Sparse records" begin
    ds = CDFDataset(data_path("a_sparse_cdf.cdf"))

    phys = [10.0, 11.0, 12.0, 16.0, 17.0, 20.0]

    # pad sparse, NASA default pad for CDF_DOUBLE
    d = -1.0e30
    @test ds["pad_default"][:] == [10.0, 11.0, 12.0, d, d, d, 16.0, 17.0, d, d, 20.0]

    # pad sparse with explicit VDR pad value
    p = ds["pad_explicit"]
    @test p[:] == [10.0, 11.0, 12.0, -99.0, -99.0, -99.0, 16.0, 17.0, -99.0, -99.0, 20.0]
    @test p[3:5] == [12.0, -99.0, -99.0] # partial range straddling physical/virtual
    @test p[4:4] == [-99.0] # purely virtual range
    @test p[11:11] == [20.0]

    # previous sparse: repeat last record of preceding block; pad before first block
    @test ds["prev"][:] == [10.0, 11.0, 12.0, 12.0, 12.0, 12.0, 16.0, 17.0, 17.0, 17.0, 20.0]

    # 2D: whole virtual record takes the pad value (cdflib's reader only pads the
    # first element — spec says the full record)
    m = ds["pad2d"][:, :]
    @test size(m) == (2, 11)
    @test m[:, 1] == [0.0, 1.0]
    @test m[:, 4] == [-99.0, -99.0]
    @test m[:, 11] == [10.0, 11.0]
    @test ds["pad2d"][1:1, 5:7] == [-99.0 -99.0 6.0]

    @test read(ds, "prev", Vector{Float64}) == ds["prev"][:]
end
