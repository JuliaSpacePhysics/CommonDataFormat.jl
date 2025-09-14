using CommonDataFormat
using Documenter

DocMeta.setdocmeta!(CommonDataFormat, :DocTestSetup, :(using CommonDataFormat); recursive=true)

makedocs(;
    modules=[CommonDataFormat],
    authors="Beforerr <zzj956959688@gmail.com> and contributors",
    sitename="CommonDataFormat.jl",
    format=Documenter.HTML(;
        canonical="https://Beforerr.github.io/CommonDataFormat.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/Beforerr/CommonDataFormat.jl",
    devbranch="main",
)
