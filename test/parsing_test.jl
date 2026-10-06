using CommonDataFormat: read_be_fields, write_be_fields, field_layout, RInt32, CDR, GDR

@testset "write_be_fields round-trip" begin
    buf = zeros(UInt8, 64)
    vals = (
        Int64(0x1122334455667788), Int32(3), Int32(9), Int32(2), Int32(15),
        RInt32(), RInt32(), Int32(0), Int32(1),
    )
    endw = write_be_fields(buf, 1, CDR{Int64}, Val(1:9), vals)
    fields, endr = read_be_fields(buf, 1, CDR{Int64}, Val(1:9))
    @test endw == endr
    @test fields == vals

    # read fields from a real file, re-emit, compare bytes (reserved fields are
    # skipped by the writer, so mask them out using the schema itself)
    ds = CDFDataset(data_path("a_cdf.cdf"))
    buffer = parent(ds)
    for SType in (CDR{Int64}, GDR{Int64})
        offset = SType <: CDR ? 8 : Int(ds.cdr.gdr_offset)
        pos = offset + 1 + 8 + 4 # past record size + record type
        fields, endpos = read_be_fields(buffer, pos, SType, Val(1:9))
        out = zeros(UInt8, endpos - pos)
        @test write_be_fields(out, 1, SType, Val(1:9), fields) == length(out) + 1
        offsets, types, total = field_layout(SType, 1:9)
        mask = trues(total)
        for (o, T) in zip(offsets, types)
            T == RInt32 && (mask[(o + 1):(o + 4)] .= false)
        end
        @test out[mask] == buffer[pos:(endpos - 1)][mask]
    end
end

# r- and z-variables are numbered independently: rVar `Epoch` and zVar `label_BGSE` are both 0.
@testset "Variable attributes in a file with r- and z-variables" begin
    ds = CDFDataset(data_path("ac_k0_mfi_00000000_v01.cdf"))
    @test ds["Epoch"].vdr.num == ds["label_BGSE"].vdr.num
    @test ds["Epoch"].attrib["FIELDNAM"] == "Time"
    la = ds["label_BGSE"].attrib
    @test la["FIELDNAM"] == "Label for B in Cartesian GSE"
    @test !haskey(la, "FILLVAL")
    @test Dict(la)["VAR_TYPE"] == "metadata"
    @test length(ds.vattrib["FIELDNAM"]) == length(ds)
end

@testset "CHAR null padding" begin
    bytes = UInt8['a', 'b', 0, 0, 'c', 0, 'd', 0]
    @test CommonDataFormat._fill_strings!(Vector{String}(undef, 2), bytes, 4) == ["ab", "c\0d"]
end
