module CommonDataFormatCommonDataModelExt

using CommonDataFormat
import CommonDataFormat as CDF
import CommonDataModel
import CommonDataModel as CDM
using CommonDataFormat: CDFDataset, CDFVariable
import CommonDataModel: path, varnames, variable, attribnames, attrib
import CommonDataModel: name, dataset, dimnames

const SymbolOrString = Union{Symbol, AbstractString}

# Dataset level -----------------------------------------------------------------

CDM.path(ds::CDFDataset) = CDF.filename(ds)
CDM.varnames(ds::CDFDataset) = keys(ds)

function CDM.variable(ds::CDFDataset, name::SymbolOrString)
    return CDF.variable(ds, String(name))
end

CDM.attribnames(ds::CDFDataset) = CDF.attribnames(ds)
CDM.attrib(ds::CDFDataset, args...) = CDF.attrib(ds, args...)

# Variable level ----------------------------------------------------------------

CDM.name(var::CDFVariable) = var.name
CDM.dataset(var::CDFVariable) = var.parentdataset
CDM.attribnames(var::CDFVariable) = keys(CDF.attrib(var))
CDM.attrib(var::CDFVariable, args...) = CDF.attrib(var, args...)
function CDM.dimnames(var::CDFVariable, i)
    N = ndims(var)
    @assert i <= N
    key = if i == N
        "DEPEND_0"
    elseif i == 1
        "DEPEND_1"
    elseif i == 2
        "DEPEND_2"
    else
        "DEPEND_$i"
    end
    return CDF.attrib(var, key)::Union{String, Nothing}
end

end
