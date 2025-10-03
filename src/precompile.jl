precompile(Array, (CDFVariable{TT2000, 1, VDR{Int64}, CDFDataset{NoCompression, Int64}},))
for T in (Float32, Float64), i in 1:3
    precompile(Array, (CDFVariable{T, i, VDR{Int64}, CDFDataset{NoCompression, Int64}},))
end

PrecompileTools.@setup_workload begin
    elx_file = joinpath(@__DIR__, "../data/elb_l2_epdef_20210914_v01.cdf")

    PrecompileTools.@compile_workload begin
        ds = CDFDataset(elx_file)
    end
end
