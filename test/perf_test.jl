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
# │     1.010 μs (26 allocs: 1.172 KiB)
# │     2.617 μs (42 allocs: 29.734 KiB)
# │     104.104 μs (4395 allocs: 181.781 KiB)
# │     2.746 μs (18 allocs: 27.000 KiB)
# │     9.829 ms (588 allocs: 31.692 MiB)
# │     469.183 μs (114 allocs: 1.382 MiB)
# └     290.812 μs (304 allocs: 47.203 KiB)