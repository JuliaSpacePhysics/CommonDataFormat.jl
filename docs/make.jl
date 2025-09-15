using CommonDataFormat
using Documenter

DocMeta.setdocmeta!(CommonDataFormat, :DocTestSetup, :(using CommonDataFormat); recursive=true)

makedocs(;
    modules=[CommonDataFormat],
    authors="Beforerr <zzj956959688@gmail.com> and contributors",
    sitename="CommonDataFormat.jl",
    format=Documenter.HTML(;
        canonical="https://juliaspacephysics.github.io/CommonDataFormat.jl",
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/JuliaSpacePhysics/CommonDataFormat.jl",
    devbranch="main",
)
