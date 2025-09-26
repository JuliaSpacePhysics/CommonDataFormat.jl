using CommonDataFormat

file = "/Users/zijin/.cdaweb/data/WI_H0_MFI/wi_h0_mfi_20210115_v05.cdf"
ds = CDFDataset(file)
keys(ds)
ds["BGSE"]