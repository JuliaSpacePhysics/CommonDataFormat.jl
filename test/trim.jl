# `juliac --trim` compatibility test.
#
# Builds a small static executable that opens a CDF and reads its metadata, then runs it.
# This guards the "open + inspect" path against regressions in static reachability: a
# stray dynamic dispatch (e.g. a record-size type passed as a value instead of `::Type{T}`,
# or `getproperty` dragging in the heterogeneous attribute machinery) fails the verifier.
#
# Data reading is covered through the typed entry point `read!(ds, name, dest)`, where
# eltype/ndims come from `dest` instead of the file. The generic `ds[name]` path stays
# out of scope: its element type is only known at runtime, so it cannot be statically
# resolved.

using Test

const TRIM_SUPPORTED = VERSION >= v"1.12.0-rc1"
const JULIAC_ENTRYPOINT_EXPR = "using JuliaC; if isdefined(JuliaC, :main); JuliaC.main(ARGS); else JuliaC._main_cli(ARGS); end"

function trim_project_path()
    active_project = Base.active_project()
    active_project !== nothing && isfile(active_project) && return dirname(active_project)
    return normpath(joinpath(@__DIR__, ".."))
end

function run_and_capture(cmd::Cmd)
    mktemp() do path, io
        exit_code = try
            run(pipeline(ignorestatus(cmd), stdout = io, stderr = io)).exitcode
        catch
            -1
        end
        close(io)
        return exit_code, read(path, String)
    end
end

function trim_verify_totals(output)
    m = match(r"Trim verify finished with\s+(\d+)\s+errors,\s+(\d+)\s+warnings\.", output)
    m !== nothing && return parse(Int, m.captures[1]), parse(Int, m.captures[2])
    errors = length(collect(eachmatch(r"Verifier error #\d+:", output)))
    warnings = length(collect(eachmatch(r"Verifier warning #\d+:", output)))
    return errors, warnings
end

if !TRIM_SUPPORTED
    @info "JuliaC trim compilation unavailable before Julia 1.12; skipping --trim build test"
    @test_skip false
else
    mktempdir() do dir
        juliac_project = trim_project_path()
        app_project = pkgdir(CommonDataFormat)
        data_file = data_path("a_cdf.cdf")
        probe = joinpath(@__DIR__, "cdf_trim_probe.jl")
        exe = "cdf_trim_probe"

        julia = joinpath(Sys.BINDIR, Base.julia_exename())
        build = `$julia --startup-file=no --history-file=no --code-coverage=none --project=$juliac_project -e $JULIAC_ENTRYPOINT_EXPR -- --output-exe $exe --project=$app_project --experimental --trim=safe $probe`
        build_exit, build_output = run_and_capture(Cmd(build; dir = dir))
        trim_errors, trim_warnings = trim_verify_totals(build_output)
        (build_exit == 0 && trim_errors == 0 && trim_warnings == 0) || print(build_output)
        @test build_exit == 0
        @test trim_errors == 0
        @test trim_warnings == 0

        if build_exit == 0
            exe_path = Sys.iswindows() ? joinpath(dir, "$exe.exe") : joinpath(dir, exe)
            run_cmd = Cmd(`$exe_path $data_file`; dir = dir)
            run_exit, run_output = run_and_capture(run_cmd)
            run_exit == 0 || print(run_output)
            @test run_exit == 0
        end
    end
end
