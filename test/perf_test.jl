using CommonDataFormat
using Test
import CommonDataFormat as CDF
using Chairmarks

include("utils.jl")

full_load(fname) = collect(CDFDataset(fname))

elx_file = data_path("elb_l2_epdef_20210914_v01.cdf")
ds = CDFDataset(elx_file)
var = ds["elb_pef_hs_Epat_eflux"]
sum(var)
full_load(elx_file)
b0 = @b ds["elb_pef_hs_Epat_eflux"] evals=20
b1= @b sum(Array(var)) evals=5
b12= @b sum(var) evals=5
b2= @b full_load(elx_file)  evals=2

mms_file = data_path(".mms1_scm_srvy_l2_scsrvy_20190301_v2.2.0.cdf")
ds = CDFDataset(mms_file)
sum(ds["mms1_scm_acb_gse_scsrvy_srvy_l2"])
sum(ds["mms1_scm_acb_gse_scsrvy_srvy_l2"][:, 100:100000]) 
b30 = @b ds["mms1_scm_acb_gse_scsrvy_srvy_l2"] evals=20
b3= @b sum(Array(ds["mms1_scm_acb_gse_scsrvy_srvy_l2"])) evals=2
b4= @b sum(ds["mms1_scm_acb_gse_scsrvy_srvy_l2"][:, 100:100000]) evals=5
b5= @b full_load(mms_file) evals=2

b = [b0, b1, b12, b2, b30, b3, b4, b5]
@info "Benchmarks" b

# ┌ Info: Benchmarks
# │   b =
# │    8-element Vector{Chairmarks.Sample}:
# │     539.550 ns (6 allocs: 528 bytes)
# │     2.083 μs (20 allocs: 29.172 KiB)
# │     2.000 μs (24 allocs: 29.328 KiB)
# │     83.896 μs (3777 allocs: 162.469 KiB)
# │     385.400 ns (7 allocs: 528 bytes)
# │     9.586 ms (574 allocs: 31.655 MiB)
# │     467.275 μs (100 allocs: 1.344 MiB)
# └     20.855 μs (250 allocs: 12.484 KiB)