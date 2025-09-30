perf:
    #!/usr/bin/env -S julia --threads=auto --project=.
    @time using CommonDataFormat
    elx_file = "data/elb_l2_epdef_20210914_v01.cdf"
    @time ds = CDFDataset(elx_file)
    @time var = ds["elb_pef_hs_Epat_eflux"]
    @time Array(var)
    @time var2 = ds["elb_pef_hs_epa_spec"]
    @time Array(var2)
    @time Array(ds["elb_pef_fs_time"])

snoop:
    #!/usr/bin/env -S julia --threads=auto --project=. -i
    using SnoopCompileCore
    invs = @snoop_invalidations using CommonDataFormat
    using SnoopCompile, AbstractTrees
    trees = invalidation_trees(invs)