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
var = ds["mms1_scm_acb_gse_scsrvy_srvy_l2"]
sum(var)
sum(var[:, 100:100000]) 
b30 = @b ds["mms1_scm_acb_gse_scsrvy_srvy_l2"] evals=20
b3= @b sum(Array(ds["mms1_scm_acb_gse_scsrvy_srvy_l2"])) evals=2
b4= @b sum(ds["mms1_scm_acb_gse_scsrvy_srvy_l2"][:, 100:100000]) evals=5
b5= @b full_load(mms_file) evals=2

b = [b0, b1, b12, b2, b30, b3, b4, b5]
@info "Benchmarks" b

# ┌ Info: Benchmarks
# │   b =
# │    8-element Vector{Chairmarks.Sample}:
# │     537.500 ns (6 allocs: 544 bytes)
# │     1.425 μs (6 allocs: 28.219 KiB)
# │     1.317 μs (6 allocs: 28.219 KiB)
# │     95.062 μs (3777 allocs: 163.078 KiB)
# │     387.500 ns (7 allocs: 560 bytes)
# │     10.175 ms (567 allocs: 31.647 MiB, 5.34% gc time)
# │     462.467 μs (93 allocs: 1.337 MiB)
# └     23.209 μs (250 allocs: 12.656 KiB)