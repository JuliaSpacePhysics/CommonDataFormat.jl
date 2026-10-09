module CommonDataFormat

using Dates
using Mmap
using DiskArrays
using Base.Threads
using LibDeflate
using PrecompileTools

export CDFDataset, CDFVariable
export Majority, CompressionType, CDFDataType
export Epoch, Epoch16, TT2000
export CDF_EPOCH, CDF_EPOCH16, CDF_TIME_TT2000, CDF_CHAR, CDF_UCHAR
export is_record_varying

@static if isdefined(Base, :OncePerProcess)
    const decompressors = Base.OncePerProcess{Channel{Decompressor}}() do
        n_ch = nthreads()
        chnl = Channel{Decompressor}(n_ch)
        foreach(i -> put!(chnl, Decompressor()), 1:n_ch)
        return chnl
    end
else
    # First called inside `@threads`; unlocked, racing workers each build a pool and one
    # deadlocks returning its decompressor to the other, already full, pool.
    const _decompressors = Ref{Union{Channel{Decompressor},Nothing}}(nothing)
    const _decompressors_lock = ReentrantLock()
    function decompressors()
        @lock _decompressors_lock begin
            if _decompressors[] === nothing
                n_ch = nthreads()
                chnl = Channel{Decompressor}(n_ch)
                foreach(i -> put!(chnl, Decompressor()), 1:n_ch)
                _decompressors[] = chnl
            end
            return _decompressors[]
        end
    end
    __init__() = _decompressors[] = nothing
end

include("epochs.jl")
include("enums.jl")
include("types.jl")
include("parsing.jl")
include("decompress.jl")
include("records/records.jl")
include("variable.jl")
include("vattribute.jl")
include("dataset.jl")
include("loading/attribute.jl")
include("loading/variable.jl")
include("precompile.jl")

end
