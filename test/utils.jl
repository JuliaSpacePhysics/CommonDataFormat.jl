using Downloads

function data_path(name)
    for dir in [
            joinpath(@__DIR__, "..", "ref", "CDFpp", "tests", "resources"),
            joinpath(@__DIR__, "..", "ref", "cdflib", "tests", "testfiles"),
            joinpath(@__DIR__, "..", "data")
        ]
        path = joinpath(dir, name)
        isfile(path) && return path
    end
    error("Data file not found: $name")
end

# Download test data from URL and cache locally
function download_test_data(url, filename = basename(url))
    cache_dir = joinpath(pkgdir(CommonDataFormat), "data")
    mkpath(cache_dir)
    filepath = joinpath(cache_dir, filename)
    if !isfile(filepath)
        @info "Downloading test data: $filename"
        Downloads.download(url, filepath)
    end
    return filepath
end
