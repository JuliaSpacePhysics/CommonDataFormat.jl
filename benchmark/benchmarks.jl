using BenchmarkTools
using CommonDataFormat
using Downloads

const SUITE = BenchmarkGroup()

const ELX_FILE = joinpath(pkgdir(CommonDataFormat), "data", "elb_l2_epdef_20210914_v01.cdf")

function download_data(url, filename = basename(url))
    dir = joinpath(tempdir(), "CommonDataFormat_benchmark_data")
    mkpath(dir)
    path = joinpath(dir, filename)
    isfile(path) || Downloads.download(url, path)
    return path
end

const MMS_FILE = download_data("https://github.com/JuliaSpacePhysics/CommonDataFormat.jl/releases/download/v0.1.16/mms1_scm_srvy_l2_scsrvy_20190301_v2.2.0.cdf")
full_load(fname) = collect(CDFDataset(fname))

let ds = CDFDataset(ELX_FILE), var = ds["elb_pef_hs_Epat_eflux"]
    g = SUITE["elx"] = BenchmarkGroup()
    g["var_access"] = @benchmarkable $ds["elb_pef_hs_Epat_eflux"]
    g["sum_array"] = @benchmarkable sum(Array($var))
    g["sum_lazy"] = @benchmarkable sum($var)
    g["sum_var_access"] = @benchmarkable sum($ds["elb_pef_hs_Epat_eflux"])
    g["full_load"] = @benchmarkable full_load(ELX_FILE)
end

let ds = CDFDataset(MMS_FILE), var = ds["mms1_scm_acb_gse_scsrvy_srvy_l2"]
    g = SUITE["mms"] = BenchmarkGroup()
    g["var_access"] = @benchmarkable $ds["mms1_scm_acb_gse_scsrvy_srvy_l2"]
    g["sum_array"] = @benchmarkable sum(Array($var))
    g["sum_slice"] = @benchmarkable sum($var[:, 100:100000])
    g["sum_var_access"] = @benchmarkable sum($var[:, 100:100000])
    g["full_load"] = @benchmarkable full_load(MMS_FILE)
end
