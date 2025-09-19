using CommonDataFormat
using CommonDataModel

include("utils.jl")

file = data_path("omni_coho1hr_merged_mag_plasma_20240901_v01.cdf")
ds = CDFDataset(file)
var = CommonDataModel.variable(ds, "BR")

for f in (:path, :varnames, :attribnames, :attrib)
    @eval CommonDataModel.$f(ds)
end

for f in (:name, :dataset, :attribnames, :attrib)
    @eval CommonDataModel.$f(var)
end

@test CommonDataModel.dimnames(var, 1) == "Epoch"