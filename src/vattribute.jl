# https://spdf.gsfc.nasa.gov/istp_guide/vattributes.html
# Variable attributes are linked with each individual variable, and provide additional information about each variable.

# https://spdf.gsfc.nasa.gov/istp_guide/vattributes.html#FILLVAL
# FILLVAL : the number inserted in the CDF in place of data values that are known to be bad or missing. Fill data are always non-valid data.
fillvalue(::Type{Float32}) = -1.0f31
fillvalue(::Type{Float64}) = -1.0e31
fillvalue(::Type{Int8}) = Int8(-128)
fillvalue(::Type{Int16}) = Int16(-32768)
fillvalue(::Type{Int32}) = Int32(-2147483648)
fillvalue(::Type{Int64}) = Int64(-9223372036854775808)
fillvalue(::Type{UInt8}) = UInt8(255)
fillvalue(::Type{UInt16}) = UInt16(65535)
fillvalue(::Type{UInt32}) = UInt32(4294967295)
