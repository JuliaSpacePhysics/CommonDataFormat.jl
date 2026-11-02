using CommonDataFormat
using Test
import CommonDataFormat as CDF

include("utils.jl")
include("epochs_test.jl")
@testset "Comprehensive Test" begin
    include("comprehensive_test.jl")
end
include("cdf2_test.jl")
include("CommonDataModelExt_test.jl")
include("decompress_test.jl")
include("inflate_test.jl")
include("parsing_test.jl")
include("sparse_test.jl")

@testset "Aqua" begin
    using Aqua
    Aqua.test_all(CommonDataFormat)
end

if isempty(VERSION.prerelease)
    @testset "JET" begin
        using JET
        JET.test_package(CommonDataFormat; target_modules = [CommonDataFormat])
    end
end

@testset "Trim" begin
    include("trim.jl")
end

# Reference the record gather against permutedims/view on random shapes.
@testset "record sink" begin
    for esz in (1, 4, 8, 9), k in 1:4, row in (false, true)
        rdims = rand(1:5, k)
        nrec = rand(1:4)
        raw = rand(UInt8, prod(rdims) * esz * nrec)
        stored = reshape(raw, esz, (row ? reverse(rdims) : rdims)..., nrec)
        src = row ? permutedims(stored, (1, (k + 1):-1:2..., k + 2)) : stored
        for ranges in ([1:d for d in rdims], [let a = rand(1:d); a:rand(a:d) end for d in rdims], [(d + 1) ÷ 2:(d + 1) ÷ 2 for d in rdims])
            dst = Vector{UInt8}(undef, esz * prod(length, ranges) * nrec)
            GC.@preserve raw dst begin
                sink = CDF.RecordSink(pointer(dst), esz, Tuple(rdims), Tuple(ranges), row)
                CDF._store!(sink, 0, pointer(raw), nrec)
            end
            @test dst == vec(src[:, ranges..., :])
        end
    end
end

# The test files lack these entry layouts, so CVVRs are synthesized from `(first, last, bytes)`.
function gzip_dataset(spans)
    buffer, entries = UInt8[], CDF.VVREntry[]
    for (first_rec, last_rec, bytes) in spans
        gz = zlib_gzip(bytes; level = 1)
        push!(entries, CDF.VVREntry(first_rec, last_rec, length(buffer), true))
        append!(buffer, zeros(UInt8, 16), reinterpret(UInt8, [hton(Int64(length(gz)))]), gz)
    end
    template = CDFDataset(data_path("a_cdf.cdf"))
    ds = CDFDataset{Int64}("", getfield(template, :cdr), getfield(template, :gdr), buffer, CDF.NoCompression, -1, Dict{Int,Tuple{Vector{CDF.VVREntry},CDF.CompressionType}}(), ReentrantLock())
    return ds, entries
end

# The gap's copy of the entry belongs at the gap's position, not at the entry's own.
@testset "previous-record gap after a one-record gzip entry" begin
    esz, rdims = 4, [2, 3]
    r1, r4 = rand(UInt8, esz * prod(rdims)), rand(UInt8, esz * prod(rdims))
    ds, entries = gzip_dataset([(1, 1, r1), (4, 4, r4)])
    stored = reshape([r1; r1; r1; r4], esz, rdims..., :)
    for ranges in ([1:2, 1:3], [2:2, 2:3])
        dst = zeros(UInt8, esz * prod(length, ranges) * 4)
        GC.@preserve dst begin
            sink = CDF.RecordSink(pointer(dst), esz, Tuple(rdims), Tuple(ranges), false)
            CDF._read_records!(sink, ds, entries, 1, 4, CDF.GzipCompression, CDF.VirtualRecords(true, UInt8[]))
        end
        @test dst == vec(stored[:, ranges..., :])
    end
end

@testset "threaded gzip reads through scratch" begin
    esz, rdims, per_entry, nentries = 8, [3, 4], 1000, 16
    record_bytes = esz * prod(rdims)
    raw = rand(UInt8, record_bytes * per_entry * nentries)
    ds, entries = gzip_dataset(map(1:nentries) do i
        last_rec = i * per_entry
        (last_rec - per_entry + 1, last_rec, raw[((last_rec - per_entry) * record_bytes + 1):(last_rec * record_bytes)])
    end)
    stored = reshape(raw, esz, rdims..., :)
    dst = Vector{UInt8}(undef, esz * 4 * per_entry * nentries)
    expected = vec(stored[:, 2:2, :, :])
    for _ in 1:20
        GC.@preserve dst begin
            sink = CDF.RecordSink(pointer(dst), esz, Tuple(rdims), (2:2, 1:4), false)
            CDF._read_records!(sink, ds, entries, 1, per_entry * nentries, CDF.GzipCompression, CDF.NO_VIRTUAL)
        end
        @test dst == expected
    end
end

@testset "iteration" begin
    for file in ("a_cdf.cdf", "ac_h0_mfi_20230102_v07.cdf") # z-only and r+z chains
        ds = CDFDataset(data_path(file))
        @test length(ds) == length(keys(ds))
        @test [v.name for v in ds] == keys(ds)
    end
    ds = CDFDataset(data_path("a_cdf.cdf"))
    @test haskey(ds, "var") && !haskey(ds, "nonexistent")
end

@testset "close" begin
    ds = CDFDataset(data_path("a_cdf.cdf"))
    v = ds["var"][:]
    @test isnothing(close(ds))
    cds = CDFDataset(data_path("a_compressed_cdf.cdf"))
    @test cds["var"][:] == v # compressed data lives in memory; close is a no-op
    @test isnothing(close(cds))
    @test cds["var"][:] == v
end

@testset "Uncompressed cdf file" begin
    file = data_path("a_cdf.cdf")
    ds = CDFDataset(file)
    @test ds.version == (3, 9, 0)
    @test ds.majority == CDF.Row
    @test ds.compression == CDF.NoCompression
    @test first(ds).name == "var"
    @test occursin("attributes: ", sprint(show, MIME("text/plain"), ds["var"]))
end

@testset "indexing" begin
    v = CDFDataset(data_path("a_cdf.cdf"))["var3d_counter"]
    A = Array(v)
    for I in ((2, :, 3), (1:2, 2, 2:4), (:, :, :), (3, 2, 4), (2:1, :, 1))
        @test v[I...] == A[I...]
    end
    @test v[:, end, end] == A[:, end, end]
    for i in (5, length(A))
        @test v[i] == A[i]
    end
    @test v[end] == A[end]
    @test_throws BoundsError v[4, 1, 1]
    @test_throws BoundsError v[0]
    @test_throws DimensionMismatch read!(v, zeros(eltype(v), 2), 1:3, 1:1, 1:1)

    # partial reads against whole-record reads: both majorities and encodings, spanning entries,
    # odd element size, virtual records, compression
    for (file, name) in (
            (download_test_data("https://cdaweb.gsfc.nasa.gov/pub/data/canopus/mari_mag/1995/cn_k0_mari_19950102_v01.cdf"), "Time_PB5"),
            (data_path("ac_h2_sis_20101105_v06.cdf"), "flux_He"),
            (data_path("elb_l2_epdef_20210914_v01.cdf"), "elb_pef_hs_Epat_eflux"),
            (data_path("a_cdf.cdf"), "var4d_string"),
            (data_path("sparse.cdf"), "pad2d"),
            (data_path("a_cdf_with_compressed_vars.cdf"), "var3d_counter"),
        )
        v = CDFDataset(file)[name]
        A = Array(v)
        N, sz = ndims(v), size(v)
        for I in (
                ntuple(d -> d == 1 ? 2 : Colon(), N),
                ntuple(d -> d == N ? (((sz[N] + 1) ÷ 2):sz[N]) : (2:sz[d]), N),
                ntuple(d -> d == N ? 1 : Colon(), N),
                sz,
            )
            @test isequal(v[I...], A[I...])
        end
    end
end

@testset "block cache LRU" begin
    c = CDF.BlockCache(10, 3)
    misses = Int[]
    get!(k, n) = CDF.cached_block!(() -> (push!(misses, k); fill(UInt8(k), n)), c, (0, k))
    foreach(k -> get!(k, 2), 1:3)
    @test get!(1, 2) == fill(0x01, 2)
    get!(4, 2)  # count limit evicts least recent: 2
    @test first.(c.entries) == [(0, 3), (0, 1), (0, 4)]
    get!(5, 5)  # byte limit evicts 3
    @test first.(c.entries) == [(0, 1), (0, 4), (0, 5)] && c.nbytes == 9
    get!(6, 11)  # larger than the budget: not cached
    @test (0, 6) ∉ first.(c.entries) && c.nbytes == 9
    @test misses == 1:6
    CDF.cached_block!(() -> UInt8[], c, (1, 1))
    CDF.evict_dataset!(c, 0)
    @test first.(c.entries) == [(1, 1)] && c.nbytes == 0
end

@testset "partial reads of compressed entries through block cache" begin
    dss = CDFDataset.(data_path.(("ac_h0_mfi_20230102_v07.cdf", "a_cdf_with_compressed_vars.cdf")))
    cases = [(ds, k) for ds in dss for k in keys(ds) if any(e -> e.compressed && length(e) > 1, CDF.read_vvrs(ds[k].vdr, ds))]
    @test length(unique(first, cases)) == 2
    full = Dict(c => Array(c[1][c[2]]) for c in cases)
    ranges = (10:20, 1:5, 5000:5400, 300:300)
    function check((ds, k), r)
        r = intersect(r, axes(full[(ds, k)], ndims(full[(ds, k)])))
        sel = (ntuple(_ -> :, ndims(full[(ds, k)]) - 1)..., r)
        return ds[k][sel...] == full[(ds, k)][sel...]
    end
    @test all(check(c, r) for cs in (cases, reverse(cases)) for c in cs for r in ranges)
    @test all(fetch, [Threads.@spawn(check(c, r)) for c in cases for r in ranges])
    close.(dss)
    @test !any(k -> first(k) in CDF.dataset_id.(dss), first.(CDF.BLOCK_CACHE.entries))
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
    @test Array(ds["var_string"]) == Array(reference["var_string"])

    @test occursin("compressed", string(ds["var"].vdr))
end

@testset "NOVARY z-variable dimension" begin
    v = CDFDataset(data_path("novary_z.cdf"))["novary"]  # row-major, declared (2,3,4), dim 2 NOVARY
    @test Array(v) == permutedims(reshape(Int32(0):Int32(39), 4, 2, 5), (2, 1, 3))
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

    @test @allocations(ds["BR"]) <= 50
end

@testset "CDF_CHAR" begin
    ds = CDFDataset(data_path("ge_h0_cpi_00000000_v01.cdf"))
    @test Array(ds["label_v3c"]) == ["Ion Vx GSE    " ; "Ion Vy GSE    " ; "Ion Vz GSE    ";;]
end

@testset "r-variables" begin
    file = data_path("ac_h0_mfi_20230102_v07.cdf")
    ds = CDFDataset(file)
    var = ds["BGSEc"]
    @test !var.vdr.zvar
    @test size(var) == (3, 5400)
end

@testset "CDF 2.4" begin
    file = download_test_data("https://cdaweb.gsfc.nasa.gov/pub/data/canopus/mari_mag/1995/cn_k0_mari_19950102_v01.cdf")
    ds = CDFDataset(file)
    @test ds.version == (2, 4, 1)
    @test keys(ds)[1:4] == ["Epoch", "Time_PB5", "DQF", "CU"]
    var = ds["Time_PB5"]
    @test size(var) == (3, 1440)
    @test var[:, 2] == [1995, 2, 60000]
    @test ds["CU"][1:3] == Float32[76.23, 78.16, 81.24]
end

@testset "global entries chained out of entry-number order" begin
    file = download_test_data("https://cdaweb.gsfc.nasa.gov/pub/software/cdawlib/0MASTERS/new-horizons_pepssi_triples-diff-intensity-bflux-b_00000000_v01.cdf")
    ds = CDFDataset(file)
    @test ds.attrib["TEXT"][(end - 3):(end - 2)] == ["The original datafiles:", "PEPSSI_Reduced_BFLUX_NNNN_M.csv"]
end

@testset "scalar r-variable" begin
    ds = CDFDataset(data_path("scalar_rvar.cdf"))
    var = ds["x"]
    @test !var.vdr.zvar
    @test var[:] == 0.0:4.0
end
