# Seed one variable per common (eltype, ndims) shape, per CDF v2/v3 offset width. Every new combination costs DiskArrays indexing compiles, so rarer
# shapes (integers, Epoch16, >3-D, extra string widths) are left out.
_workload_key(var) = (eltype(var) <: StaticString ? StaticString : eltype(var), ndims(var), recordsize_type(var.parentdataset))
_workload_maxdims(T) = T <: AbstractFloat ? 3 : T <: StaticString ? 2 : T in (TT2000, Epoch) ? 1 : 0

PrecompileTools.@setup_workload begin
    files = joinpath.(@__DIR__, "../data", ("elb_l2_epdef_20210914_v01.cdf", "a_cdf_with_compressed_vars.cdf", "ac_h2_sis_20101105_v06.cdf"))
    seen = Set{Tuple{Any, Int, DataType}}()

    PrecompileTools.@compile_workload begin
        for (i, file) in enumerate(files)
            ds = CDFDataset(file)
            ds.attrib
            for var in ds
                key = _workload_key(var)
                (isempty(var) || key[2] > _workload_maxdims(key[1]) || key in seen) && continue
                push!(seen, key)
                Dict(var.attrib)
                Array(var)
                var[1]
                var[ntuple(_ -> Colon(), ndims(var) - 1)..., 1:1]
                eltype(var) <: CDFDateTime && (DateTime.(var[1:1]); Timestamp.(var[1:1]); string(var[1]))
            end
        end
    end
end
