a = rand(3, 100000)

f1(a) = map!(ntoh, a, a)
f2(a) = a .= ntoh.(a)

using Polyester

function f3(a)
    return @inbounds @simd for i in eachindex(a)
        a[i] = ntoh(a[i])
    end
end

function f4(a)
    @batch for i in eachindex(a)
        a[i] = ntoh(a[i])
    end
    return a
end

using Base.Threads

function f5(a)
    Threads.@threads  for i in eachindex(a)
        a[i] = ntoh(a[i])
    end
    return a
end

a = rand(3, 10000000)

b1 = @b f1(a) evals = 10
b2 = @b f2(a) evals = 10
b3 = @b f3(a) evals = 10
b4 = @b f4(a) evals = 10
b5 = @b f5(a) evals = 10


ds = CDFDataset("/Users/zijin/.cdaweb/data/THB_L2_FGM/thb_fgl_gseQ_thb_l2s_fgm_20210120000000_20210120235959_cdaweb.cdf")
var = ds["thb_fgl_epoch16"]
@b Array(var)
