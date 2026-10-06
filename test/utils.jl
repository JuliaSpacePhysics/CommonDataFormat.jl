using Downloads

if !@isdefined(data_path)
    data_path(name) = joinpath(@__DIR__, "..", "data", name)
end

# Download test data from URL and cache locally
if !@isdefined(download_test_data)
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
end
