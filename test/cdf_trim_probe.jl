using CommonDataFormat
import CommonDataFormat as CDF

function (@main)(args::Vector{String})
    ds = CDFDataset(args[1])
    ok = ds.version == (3, 9, 0) &&
         ds.majority == CDF.Row &&
         ds.compression == CDF.NoCompression &&
         length(keys(ds)) > 0
    # Typed data reads: z-variable (VDR) 1D + 2D with row-major swap.
    v = read!(ds, "var", Vector{Float64}(undef, 101))
    ok &= v[1] == 1.0
    m = read!(ds, "var2d_counter", Matrix{Float64}(undef, 10, 10))
    ok &= m[1, 1] == 0.0 && m[2, 1] == 1.0 && m[10, 10] == 99.0
    ok &= read(ds, "var2d_counter", Matrix{Float64}) == m
    return ok ? 0 : 1
end
