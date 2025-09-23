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
@info "Sum" @b sum(var)
@info "Full load" @b full_load(elx_file)

mms_file = data_path("mms1_scm_srvy_l2_scsrvy_20190301_v2.2.0.cdf")
ds = CDFDataset(mms_file)
sum(ds["mms1_scm_acb_gse_scsrvy_srvy_l2"])
@info "Sum" @b sum(ds["mms1_scm_acb_gse_scsrvy_srvy_l2"])
@info "Slice sum" @b sum(ds["mms1_scm_acb_gse_scsrvy_srvy_l2"][:, 100:100000])
@info "Full load" @b full_load(mms_file)
