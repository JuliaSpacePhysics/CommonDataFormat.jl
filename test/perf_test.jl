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
b1= @b sum(Array(ds["elb_pef_hs_Epat_eflux"])) evals=5
b2= @b full_load(elx_file)  evals=2

mms_file = data_path("mms1_scm_srvy_l2_scsrvy_20190301_v2.2.0.cdf")
ds = CDFDataset(mms_file)
sum(ds["mms1_scm_acb_gse_scsrvy_srvy_l2"])
b30 = @b ds["mms1_scm_acb_gse_scsrvy_srvy_l2"] evals=20
b3= @b sum(Array(ds["mms1_scm_acb_gse_scsrvy_srvy_l2"])) evals=2
b4= @b sum(ds["mms1_scm_acb_gse_scsrvy_srvy_l2"][:, 100:100000]) evals=5
b5= @b full_load(mms_file) evals=2

b = [b0, b1, b2, b30, b3, b4, b5]
@info "Benchmarks" b

# ┌ Info: Benchmarks
# │   b =
# │    7-element Vector{Chairmarks.Sample}:
# │     1.029 μs (26 allocs: 1.250 KiB)
# │     2.633 μs (42 allocs: 29.812 KiB)
# │     103.959 μs (4398 allocs: 184.547 KiB)
# │     2.785 μs (19 allocs: 27.109 KiB)
# │     10.674 ms (589 allocs: 31.693 MiB)
# │     468.342 μs (115 allocs: 1.382 MiB)
# └     290.209 μs (309 allocs: 47.938 KiB)