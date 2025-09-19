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
b1= @b sum(Array(ds["elb_pef_hs_Epat_eflux"]))
b2= @b full_load(elx_file)

mms_file = data_path("mms1_scm_srvy_l2_scsrvy_20190301_v2.2.0.cdf")
ds = CDFDataset(mms_file)
sum(ds["mms1_scm_acb_gse_scsrvy_srvy_l2"])
b3= @b sum(Array(ds["mms1_scm_acb_gse_scsrvy_srvy_l2"]))
b4= @b sum(ds["mms1_scm_acb_gse_scsrvy_srvy_l2"][:, 100:100000])
b5= @b full_load(mms_file)

b = [b1, b2, b3, b4, b5]
@info "Benchmarks" b

# ┌ Info: Benchmarks
# │   b =
# │    5-element Vector{Chairmarks.Sample}:
# │     2.583 μs (42 allocs: 29.812 KiB)
# │     104.834 μs (4398 allocs: 184.547 KiB)
# │     9.445 ms (606 allocs: 31.694 MiB)
# │     457.750 μs (131 allocs: 1.383 MiB)
# └     271.417 μs (309 allocs: 47.938 KiB)