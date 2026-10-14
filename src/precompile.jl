# Only `Array` (straight to `readblock!`) is seeded: CDFDatasets reads through `readblock!` too.
PrecompileTools.@setup_workload begin
    files = joinpath.(@__DIR__, "../data", ("elb_l2_epdef_20210914_v01.cdf", "a_cdf_with_compressed_vars.cdf", "ac_h2_sis_20101105_v06.cdf"))

    PrecompileTools.@compile_workload begin
        for file in files
            ds = CDFDataset(file)
            ds.attrib
            for var in ds
                isempty(var) && continue
                Dict(var.attrib)
                A = Array(var)
                eltype(var) <: CDFDateTime && (DateTime.(A); string(A[1]))
            end
        end
    end
end
