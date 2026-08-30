using CommonDataFormat
import CommonDataFormat as CDF

function (@main)(args::Vector{String})
    ds = CDFDataset(args[1])
    ok = ds.version == (3, 9, 0) &&
         ds.majority == CDF.Row &&
         ds.compression == CDF.NoCompression &&
         length(keys(ds)) > 0
    return ok ? 0 : 1
end
