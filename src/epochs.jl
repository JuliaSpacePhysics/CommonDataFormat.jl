# https://github.com/ancapdev/UnixTimes.jl/blob/master/src/UnixTimes.jl
# CDF Epoch types as AbstractDateTime subtypes
# Based on C++ CDFpp implementation
# 1. CDF_EPOCH is milliseconds since Year 0 represented as a single double,
# 2. CDF_EPOCH16 is picoseconds since Year 0 represented as 2-doubles,
# 3. CDF_TIME_TT2000 (TT2000 as short) is nanoseconds since J2000 with leap seconds

import Base: promote_rule

include("leap_second.jl")

const EPOCH_OFFSET_MILLISECONDS = 62167219200000.0  # Milliseconds from year 0 to Unix epoch
const EPOCH_OFFSET_SECONDS = 62167219200.0  # Seconds from year 0 to Unix epoch

abstract type CDFDateTime <: Dates.AbstractDateTime end

"""
    Epoch

Milliseconds since Year 0 (01-Jan-0000 00:00:00.000)
Represented as a single double.
"""
struct Epoch <: CDFDateTime
    value::Float64
end

"""
    Epoch16

Picoseconds since Year 0 (01-Jan-0000 00:00:00.000.000.000.000)
Represented as two doubles (seconds and picoseconds).
"""
struct Epoch16 <: CDFDateTime
    seconds::Float64     # Seconds since year 0
    picoseconds::Float64 # Picoseconds component
end

"""
    TT2000

Nanoseconds since J2000 (01-Jan-2000 12:00:00.000.000.000)
with leap seconds, represented as an 8-byte integer.
"""
struct TT2000 <: CDFDateTime
    value::Int64
end

# Conversion to DateTime
function Dates.DateTime(epoch::Epoch)
    return DateTime(0) + Millisecond(round(Int64, epoch.value))
end

function Dates.DateTime(epoch::Epoch16)
    s_since_unix = epoch.seconds - EPOCH_OFFSET_SECONDS
    total_ns = s_since_unix * 1.0e9 + epoch.picoseconds / 1000.0
    return DateTime(1970) + Nanosecond(round(Int64, total_ns))
end

function Dates.DateTime(epoch::TT2000)
    # TT2000 to Unix time with leap second correction
    ns_from_1970 = epoch.value + TT2000_OFFSET
    leap_seconds_ns = leap_second(ns_from_1970)
    return DateTime(1970) + Nanosecond(ns_from_1970 - leap_seconds_ns)
end

# Conversion from DateTime
function Epoch(dt::DateTime)
    ms_since_unix = (dt - DateTime(1970, 1, 1)).value
    return Epoch(ms_since_unix + EPOCH_OFFSET_MILLISECONDS)
end

function Epoch16(dt::DateTime)
    ns_since_unix = (dt - DateTime(1970, 1, 1)).value * 1_000_000  # DateTime precision is milliseconds
    s_since_unix = ns_since_unix / 1.0e9
    s_total = s_since_unix + EPOCH_OFFSET_SECONDS
    ps_component = (ns_since_unix % 1.0e9) * 1000.0  # Convert nanoseconds remainder to picoseconds
    return Epoch16(s_total, ps_component)
end

function TT2000(dt::DateTime)
    ns_since_unix = (dt - DateTime(1970, 1, 1)).value * 1_000_000
    leap_seconds_ns = leap_second(ns_since_unix)
    tt2000_value = ns_since_unix - TT2000_OFFSET + leap_seconds_ns
    return TT2000(tt2000_value)
end

for f in (:year, :month, :day, :hour, :minute, :second, :millisecond)
    @eval Dates.$f(epoch::CDFDateTime) = Dates.$f(DateTime(epoch))
end

Base.show(io::IO, epoch::CDFDateTime) = print(io, typeof(epoch), "(", DateTime(epoch), ")")
Base.promote_rule(::Type{<:CDFDateTime}, ::Type{Dates.DateTime}) = Dates.DateTime
Base.convert(::Type{Dates.DateTime}, x::CDFDateTime) = Dates.DateTime(x)
Base.bswap(x::T) where {T <: CDFDateTime} = T(Base.bswap(x.value))