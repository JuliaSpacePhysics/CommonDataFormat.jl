using Test
using CommonDataFormat
import CommonDataFormat as CDF
using Dates

include("utils.jl")

"""
Comprehensive test based on the Python CDFpp test.py
Tests all variables in a_cdf.cdf for expected shapes, types, values, and attributes
"""

# Expected variable definitions (translated from Python test.py)
const EXPECTED_VARIABLES = IdDict(
    "epoch" => (
        shape = (101,),
        data_type = "CDF_EPOCH",
        values = DateTime(1970, 1, 1) .+ Day.(180 * (0:100)),
        attributes = Dict("attr1" => "attr1_value", "epoch_attr" => "a variable attribute"),
    ),
    "tt2000" => (
        shape = (101,),
        data_type = "CDF_TIME_TT2000",
        values = DateTime(1970, 1, 1) .+ Day.(180 * (0:100)),
        attributes = Dict{String, Any}(),
    ),
    "epoch16" => (
        shape = (101,),
        data_type = "CDF_EPOCH16",
        values = DateTime(1970, 1, 1) .+ Day.(180 * (0:100)),
        attributes = Dict{String, Any}(),
    ),
    "var" => (
        shape = (101,),
        data_type = "CDF_DOUBLE",
        # Values: cos(arange(0., 101/100*2*π, 2*π/100))
        values = cos.(0:(2π / 100):((101) * 2π / 100)),
        attributes = Dict("var_attr" => "a variable attribute", "DEPEND0" => "epoch"),
    ),
    "zeros" => (
        shape = (2048,),
        data_type = "CDF_DOUBLE",
        values = zeros(2048),
        attributes = Dict("attr1" => "attr1_value"),
    ),
    "bytes" => (
        shape = (10,),
        data_type = "CDF_BYTE",
        values = ones(Int8, 10),
        attributes = Dict("attr1" => "attr1_value"),
    ),
    "var2d" => (
        shape = (4, 3),  # Note: Julia uses column-major, Python uses row-major
        data_type = "CDF_DOUBLE",
        values = ones(4, 3),
        attributes = Dict("attr1" => "attr1_value", "attr2" => "attr2_value"),
    ),
    "var2d_counter" => (
        shape = (10, 10),
        data_type = "CDF_DOUBLE",
        values = reshape(0.0:99.0, 10, 10),
        attributes = Dict{String, Any}(),
    ),
    "var3d_counter" => (
        shape = (3, 5, 10),  # Shape adjusted for Julia column-major
        data_type = "CDF_DOUBLE",
        values = reshape(0.0:(3 * 5 * 10 - 1), 3, 5, 10),
        attributes = Dict("attr1" => "attr1_value", "attr2" => "attr2_value"),
    ),
    "var5d_counter" => (
        shape = (5, 4, 3, 2, 6),  # Shape adjusted for Julia column-major
        data_type = "CDF_DOUBLE",
        values = reshape(0.0:(5 * 4 * 3 * 2 * 6 - 1), 5, 4, 3, 2, 6),
        attributes = Dict{String, Any}(),
    ),
    "var3d" => (
        shape = (3, 2, 4),  # Shape adjusted for Julia column-major
        data_type = "CDF_DOUBLE",
        values = ones(3, 2, 4),
        attributes = Dict("var3d_attr_multi" => [10, 11]),
    ),
    "empty_var_recvary_string" => (
        shape = (0,),  # Adjusted for Julia
        data_type = "CDF_CHAR",
        attributes = Dict{String, Any}(),
        values = [],
    ),
    "var_recvary_string" => (
        shape = (3,),
        data_type = "CDF_CHAR",
        attributes = Dict{String, Any}(),
        values = ["001", "002", "003"],
    ),
    "var_string" => (
        shape = (1,),  # Adjusted for Julia
        data_type = "CDF_CHAR",
        values = ["This is a string"],
        attributes = Dict{String, Any}(),
    ),
    "var_string_uchar" => (
        shape = (1,),  # Adjusted for Julia
        data_type = "CDF_UCHAR",
        attributes = Dict{String, Any}(),
        values = ["This is a string"],
    ),
    "var2d_string" => (
        shape = (2, 1),  # Adjusted for Julia
        data_type = "CDF_CHAR",
        values = ["This is a string 1"; "This is a string 2";;],
        attributes = Dict{String, Any}(),
    ),
    "var3d_string" => (
        shape = (2, 2, 1),
        data_type = "CDF_CHAR",
        attributes = Dict{String, Any}(),
        values = ["value[00]"; "value[01]";; "value[10]"; "value[11]";;;],
    ),
    "var4d_string" => (
        shape = (3, 2, 2, 1),
        data_type = "CDF_CHAR",
        values = ["value[000]" "value[011]"; "value[001]" "value[100]"; "value[010]" "value[101]";;; "value[110]" "value[201]"; "value[111]" "value[210]"; "value[200]" "value[211]";;;;],
        attributes = Dict{String, Any}(),
    )
)

file = data_path("a_cdf.cdf")
ds = CDFDataset(file)
@testset "All Expected Variables Present" begin
    @test Set(keys(ds)) == Set(keys(EXPECTED_VARIABLES))
end

@testset "DateTime Conversions" begin
    for var in ("epoch", "epoch16", "tt2000")
        @testset "Variable: $var" begin
            var_name = var
            expected = EXPECTED_VARIABLES[var]
            @test haskey(ds, var_name)
            var = ds[var_name]
            @test size(var) == expected.shape
            @test string(var.datatype) == expected.data_type
            @test var == expected.values
            @test var.attrib == expected.attributes
        end
    end
end

@testset "Variable Properties and Values" begin
    for (var_name, expected) in EXPECTED_VARIABLES
        @testset "Variable: $var_name" begin
            @test haskey(ds, var_name)
            var = ds[var_name]
            @test size(var) == expected.shape
            @test string(var.datatype) == expected.data_type
            # Test values (if specified)
            if eltype(var) <: Number
                @test var ≈ expected.values
            else
                @test var == expected.values
            end
            @test var.attrib == expected.attributes
        end
    end
end

# Expected global attributes (translated from Python test.py)
const EXPECTED_GLOBAL_ATTRIBUTES = Dict{String, Any}(
    "attr" => ["a cdf text attribute"],
    "attr_float" => [[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]],
    "attr_int" => [[1, 2, 3]],
    "attr_multi" => [[1, 2], [2.0, 3.0], "hello"],
    "empty" => Any[]
)

@testset "Global Attributes" begin
    for (attr_name, expected_value) in EXPECTED_GLOBAL_ATTRIBUTES
        actual_value = ds.attrib[attr_name]
        @test actual_value == expected_value
    end
end
