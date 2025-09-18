# https://github.com/SciQLop/CDFpp/blob/main/include/cdfpp/chrono/cdf-chrono.hpp
# https://github.com/SciQLop/CDFpp/blob/main/include/cdfpp/chrono/cdf-leap-seconds.h#L36
# http://maia.usno.navy.mil/ser7/tai-utc.dat
# https://github.com/MAVENSDC/cdflib/blob/main/cdflib/CDFLeapSeconds.txt
# TT2000 offset constant from C++ implementation
const TT2000_OFFSET = Int64(946727967816000000)  # nanoseconds from 1970 to J2000 with corrections
const UNIX_EPOCH = DateTime(1970, 1, 1)
const PRE1972_CUTOFF = DateTime(1972, 1, 1)
const MJD_BASE = 2_400_000.5
const NS_IN_SECOND = Int64(1_000_000_000)

# Leap seconds table from C++ implementation
# https://www.wikiwand.com/en/articles/Leap_second
# Stores (nanoseconds_since_1970, leap_seconds_in_nanoseconds)
const LEAP_SECONDS_TT2000 = [
    (63072000000000000, 10000000000),   # 1-Jan-1972
    (78796800000000000, 11000000000),   # 1-Jul-1972
    (94694400000000000, 12000000000),   # 1-Jan-1973
    (126230400000000000, 13000000000),  # 1-Jan-1974
    (157766400000000000, 14000000000),  # 1-Jan-1975
    (189302400000000000, 15000000000),  # 1-Jan-1976
    (220924800000000000, 16000000000),  # 1-Jan-1977
    (252460800000000000, 17000000000),  # 1-Jan-1978
    (283996800000000000, 18000000000),  # 1-Jan-1979
    (315532800000000000, 19000000000),  # 1-Jan-1980
    (362793600000000000, 20000000000),  # 1-Jul-1981
    (394329600000000000, 21000000000),  # 1-Jul-1982
    (425865600000000000, 22000000000),  # 1-Jul-1983
    (489024000000000000, 23000000000),  # 1-Jul-1985
    (567993600000000000, 24000000000),  # 1-Jan-1988
    (631152000000000000, 25000000000),  # 1-Jan-1990
    (662688000000000000, 26000000000),  # 1-Jan-1991
    (709948800000000000, 27000000000),  # 1-Jul-1992
    (741484800000000000, 28000000000),  # 1-Jul-1993
    (773020800000000000, 29000000000),  # 1-Jul-1994
    (820454400000000000, 30000000000),  # 1-Jan-1996
    (867715200000000000, 31000000000),  # 1-Jul-1997
    (915148800000000000, 32000000000),  # 1-Jan-1999
    (1136073600000000000, 33000000000), # 1-Jan-2006
    (1230768000000000000, 34000000000), # 1-Jan-2009
    (1341100800000000000, 35000000000), # 1-Jul-2012
    (1435708800000000000, 36000000000), # 1-Jul-2015
    (1483228800000000000, 37000000000), # 1-Jan-2017
]

const PRE1972_LEAP_SECONDS = [
    (DateTime(1960, 1, 1), 1.417818, 37300.0, 0.001296),
    (DateTime(1961, 1, 1), 1.422818, 37300.0, 0.001296),
    (DateTime(1961, 8, 1), 1.372818, 37300.0, 0.001296),
    (DateTime(1962, 1, 1), 1.845858, 37665.0, 0.0011232),
    (DateTime(1963, 11, 1), 1.945858, 37665.0, 0.0011232),
    (DateTime(1964, 1, 1), 3.24013, 38761.0, 0.001296),
    (DateTime(1964, 4, 1), 3.34013, 38761.0, 0.001296),
    (DateTime(1964, 9, 1), 3.44013, 38761.0, 0.001296),
    (DateTime(1965, 1, 1), 3.54013, 38761.0, 0.001296),
    (DateTime(1965, 3, 1), 3.64013, 38761.0, 0.001296),
    (DateTime(1965, 7, 1), 3.74013, 38761.0, 0.001296),
    (DateTime(1965, 9, 1), 3.84013, 38761.0, 0.001296),
    (DateTime(1966, 1, 1), 4.31317, 39126.0, 0.002592),
    (DateTime(1968, 2, 1), 4.21317, 39126.0, 0.002592),
]

@inline function julian_day_number(y::Int, m::Int, d::Int)
    a = (14 - m) ÷ 12
    y′ = y + 4800 - a
    m′ = m + 12 * a - 3
    return d + ((153 * m′ + 2) ÷ 5) + 365 * y′ + y′ ÷ 4 - y′ ÷ 100 + y′ ÷ 400 - 32045
end

function leap_seconds_pre1972(date)
    idx = findlast(entry -> date >= entry[1], PRE1972_LEAP_SECONDS)
    idx === nothing && return 0.0
    entry = PRE1972_LEAP_SECONDS[idx]
    mjd = Float64(julian_day_number(year(date), month(date), day(date))) - MJD_BASE
    return entry[2] + (mjd - entry[3]) * entry[4]
end

function leap_second(ns_from_1970::Int64)
    dt = UNIX_EPOCH + Nanosecond(ns_from_1970)
    if dt >= PRE1972_CUTOFF
        idx = findlast(x -> x[1] <= ns_from_1970, LEAP_SECONDS_TT2000)
        return LEAP_SECONDS_TT2000[idx][2]
    else
        seconds = leap_seconds_pre1972(dt)
        return floor(Int64, seconds * NS_IN_SECOND)
    end
end
