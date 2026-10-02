# https://github.com/ancapdev/UnixTimes.jl/blob/master/src/UnixTimes.jl
# CDF Epoch types as AbstractDateTime subtypes
# Based on C++ CDFpp implementation
# 1. CDF_EPOCH is milliseconds since Year 0 represented as a single double,
# 2. CDF_EPOCH16 is picoseconds since Year 0 represented as 2-doubles,
# 3. CDF_TIME_TT2000 (TT2000 as short) is nanoseconds since J2000 with leap seconds

import Base: promote_rule, -, +
using Dates: value, toms, tons
using Durations: Timestamp

include("leap_second.jl")

const EPOCH_OFFSET_MILLISECONDS = 62167219200000.0  # Milliseconds from year 0 to Unix epoch
const EPOCH_OFFSET_SECONDS = 62167219200.0  # Seconds from year 0 to Unix epoch

abstract type CDFDateTime <: Dates.AbstractDateTime end

struct Picosecond <: Period
    value::Float64
end

Picosecond(ns::Nanosecond) = convert(Picosecond, ns)
Picosecond(p::Period) = Picosecond(Nanosecond(p))
Base.convert(::Type{Nanosecond}, x::Picosecond) = Nanosecond(round(Int64, x.value / 1.0e3))
Base.convert(::Type{Picosecond}, x::Nanosecond) = Picosecond(x.value * 1.0e3)
Base.convert(::Type{Picosecond}, x::Dates.FixedPeriod) = Picosecond(Nanosecond(x))
Base.promote_rule(::Type{Picosecond}, ::Type{<:Dates.FixedPeriod}) = Picosecond

Dates._units(x::Picosecond) = " picosecond" * (abs(value(x)) == 1 ? "" : "s")


"""
    Epoch

Milliseconds since Year 0 (01-Jan-0000 00:00:00.000)
Represented as a single double.
"""
struct Epoch <: CDFDateTime
    instant::Float64
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
    instant::Nanosecond
end


TT2000(instant::Int64) = TT2000(Nanosecond(instant))

# ISTP FILLVAL
_isfill(x::Epoch) = x.instant == -1.0e31
_isfill(x::Epoch16) = x.seconds == -1.0e31
_isfill(x::TT2000) = x.instant.value == typemin(Int64)

(-)(epoch::Epoch, other::Epoch) = Millisecond(round(Int64, epoch.instant - other.instant))
(-)(epoch::Epoch16, other::Epoch16) = Picosecond((epoch.seconds - other.seconds) * 1.0e12 + epoch.picoseconds - other.picoseconds)
(+)(tt2000::TT2000, other::Period) = TT2000(value(tt2000) + tons(other))
(-)(tt2000::TT2000, other::Period) = TT2000(value(tt2000) - tons(other))
(+)(epoch::Epoch, other::Period) = Epoch(value(epoch) + toms(other))
(-)(epoch::Epoch, other::Period) = Epoch(value(epoch) - toms(other))
# Whole seconds are split off first: a Float64 picosecond count is only exact within ~2.5 hours.
function (+)(epoch::Epoch16, other::Period)
    s, ns = fldmod(tons(other), 1_000_000_000)
    carry, ps = fldmod(epoch.picoseconds + 1.0e3 * ns, 1.0e12)
    return Epoch16(epoch.seconds + s + carry, ps)
end
(-)(epoch::Epoch16, other::Period) = epoch + (-other)

Base.isless(x::Epoch16, y::Epoch16) = isless((x.seconds, x.picoseconds), (y.seconds, y.picoseconds))

# UTC nanoseconds since the Unix epoch. Int128: Epoch16 spans years 0-9999 and TT2000 reaches
# 2292, both beyond an Int64 nanosecond count.
_unix_ns(x::TT2000) = utc_from_tt(Int128(x.instant.value) + TT2000_OFFSET)
_unix_ns(x::Epoch16) = (Int128(x.seconds) - Int128(EPOCH_OFFSET_SECONDS)) * 1_000_000_000 + fld(Int128(x.picoseconds), 1000)
_unix_ns(dt::Timestamp{P}) where {P} = Int128(value(dt)) * tons(P(1))
_unix_ns(dt::TimeType) = (Int128(value(DateTime(dt))) - Dates.UNIXEPOCH) * 1_000_000

# Int128 division is a slow library call, and nearly every instant fits an Int64.
_fld(ns::Int128, d::Int64) = typemin(Int64) <= ns <= typemax(Int64) ? fld(ns % Int64, d) : Int64(fld(ns, d))

# Floored to the millisecond, so calendar fields never run ahead of the instant.
Dates.DateTime(x::Union{TT2000, Epoch16}) = DateTime(Dates.UTM(_fld(_unix_ns(x), 1_000_000) + Dates.UNIXEPOCH))
Dates.DateTime(epoch::Epoch) = DateTime(0) + Millisecond(round(Int64, epoch.instant))

Timestamp{P}(x::CDFDateTime) where {P} = convert(Timestamp{P}, x)
Base.convert(::Type{Timestamp}, x::CDFDateTime) = convert(Timestamp{Nanosecond}, x)
Base.convert(::Type{Timestamp{P}}, x::Union{TT2000, Epoch16}) where {P} = convert(Timestamp{P}, Nanosecond(Int64(_unix_ns(x))))
Base.convert(::Type{Timestamp{P}}, x::Epoch) where {P} = convert(Timestamp{P}, DateTime(x))
Base.convert(::Type{DateTime}, x::CDFDateTime) = DateTime(x)

# Calendar fields and printing. Epoch and Epoch16 span years 0-9999, far beyond
# Timestamp{Nanosecond} (1677-2262), so only TT2000 gets nanosecond fields.
_calendar(x::TT2000) = Timestamp{Nanosecond}(x)
_calendar(x::CDFDateTime) = DateTime(x)

TT2000(dt::TimeType) = convert(TT2000, dt)
Epoch(dt::TimeType) = convert(Epoch, dt)
Epoch16(dt::TimeType) = convert(Epoch16, dt)

function Base.convert(::Type{TT2000}, dt::TimeType)
    ns_since_unix = _unix_ns(dt)
    return TT2000(Int64(ns_since_unix - TT2000_OFFSET + leap_second(ns_since_unix)))
end

function Base.convert(::Type{Epoch16}, dt::TimeType)
    s, ns = fldmod(_unix_ns(dt), 1_000_000_000)
    return Epoch16(Float64(s + Int128(EPOCH_OFFSET_SECONDS)), Float64(ns * 1000))
end

# Int64 path for the common case; the Int128 division above is several times slower.
function Base.convert(::Type{Epoch16}, dt::DateTime)
    s, ms = fldmod(value(dt) - Dates.UNIXEPOCH, 1000)
    return Epoch16(s + EPOCH_OFFSET_SECONDS, ms * 1.0e9)
end

function Base.convert(::Type{Epoch}, dt::TimeType)
    ms_since_unix = (DateTime(dt) - DateTime(1970, 1, 1)).value
    return Epoch(ms_since_unix + EPOCH_OFFSET_MILLISECONDS)
end

for t in (:Epoch, :Epoch16, :TT2000)
    @eval Base.convert(::Type{$t}, dt::$t) = dt
end

for f in (:Date, :Time, :days, :year, :month, :day, :hour, :minute, :second, :millisecond)
    @eval Dates.$f(epoch::CDFDateTime) = Dates.$f(_calendar(epoch))
end
for f in (:microsecond, :nanosecond)
    @eval Dates.$f(epoch::TT2000) = Dates.$f(_calendar(epoch))
end

# Callers guarantee `r` is in bounds.
@inline function _parse_int(b, r)
    x = 0
    for i in r
        d = @inbounds(b[i]) - 0x30
        d <= 0x09 || throw(ArgumentError("invalid digit in date string"))
        x = 10x + d
    end
    return x
end

# Returns the whole seconds as a DateTime (full year range, unlike Timestamp{Nanosecond}) and the
# fraction in picoseconds. "yyyy-mm-ddTHH:MM:SS[.f...]" is read straight from the bytes so no
# fractional digit is dropped; any other shape goes to the Dates parser.
function _parse_epoch(s::AbstractString)
    b = codeunits(s)
    n = length(b)
    iso = @inbounds (n == 19 || 21 <= n <= 32 && b[20] == UInt8('.')) && b[5] == b[8] == UInt8('-') &&
        b[11] == UInt8('T') && b[14] == b[17] == UInt8(':')
    iso || return DateTime(s), 0
    dt = DateTime(
        _parse_int(b, 1:4), _parse_int(b, 6:7), _parse_int(b, 9:10),
        _parse_int(b, 12:13), _parse_int(b, 15:16), _parse_int(b, 18:19)
    )
    return dt, _parse_int(b, 21:n) * 10^(32 - n)
end

Epoch(s::AbstractString) = Epoch(DateTime(s))
function Epoch16(s::AbstractString)
    dt, ps = _parse_epoch(s)
    epoch = Epoch16(dt)
    return Epoch16(epoch.seconds, epoch.picoseconds + ps)
end
function TT2000(s::AbstractString)
    dt, ps = _parse_epoch(s)
    ns, r = divrem(ps, 1000)
    iszero(r) || throw(InexactError(:TT2000, TT2000, s))
    return TT2000(dt) + Nanosecond(ns)
end

Dates.value(epoch::Epoch) = epoch.instant
Dates.value(epoch::Epoch16) = ComplexF64(epoch.seconds, epoch.picoseconds)
Dates.value(epoch::TT2000) = epoch.instant.value

function Base.floor(x::T, p::Union{DatePeriod, TimePeriod}) where {T <: CDFDateTime}
    return convert(T, floor(_calendar(x), p))
end

Base.show(io::IO, epoch::CDFDateTime) = _isfill(epoch) ? print(io, "FILLVAL") : print(io, _calendar(epoch))

# Promote towards the CDF type: UTC -> TT2000 is injective, whereas TT2000 -> UTC folds each
# inserted leap second onto the following second, so comparing in UTC would equate distinct instants.
Base.promote_rule(::Type{T}, ::Type{<:Union{Date, DateTime}}) where {T <: CDFDateTime} = T
Base.promote_rule(::Type{T}, ::Type{<:Timestamp}) where {T <: Union{TT2000, Epoch16}} = T
Base.promote_rule(::Type{Epoch}, ::Type{T}) where {T <: Timestamp} = promote_type(DateTime, T)
Base.promote_rule(::Type{TT2000}, ::Type{<:Union{Epoch, Epoch16}}) = TT2000
Base.promote_rule(::Type{Epoch16}, ::Type{Epoch}) = Epoch16
Base.bswap(x::Epoch) = Epoch(Base.bswap(x.instant))
Base.bswap(x::Epoch16) = Epoch16(Base.bswap(x.seconds), Base.bswap(x.picoseconds))
Base.bswap(x::TT2000) = TT2000(Base.bswap(x.instant.value))
