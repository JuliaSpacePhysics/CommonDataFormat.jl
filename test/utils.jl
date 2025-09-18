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