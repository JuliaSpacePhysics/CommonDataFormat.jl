using Test
using CommonDataFormat

@testset "CommonDataFormat Basic Tests" begin

    @testset "Module loading" begin
        @test isa(CDF, Type)
        @test isa(CDFAttribute, Type)
        @test isa(CDFVariable, Type)
    end

    @testset "CDF Constants" begin
        @test julia_type_from_cdf(UInt32(21)) == Float32
        @test cdf_type_size(UInt32(21)) == 4
    end

    @testset "Basic CDF structure" begin
        # Test creating CDF objects manually
        attr = CDFAttribute("TEST_ATTR", ["test_value"])
        @test attr.name == "TEST_ATTR"
        @test attr.entries == ["test_value"]

        var = CDFVariable("test_var", "CDF_REAL4", [10], 100,
                         Dict{String, CDFAttribute}(), nothing)
        @test var.name == "test_var"
        @test var.data_type == "CDF_REAL4"
        @test var.dimensions == [10]
        @test var.num_records == 100
        @test var.data === nothing

        attributes = Dict("TEST_ATTR" => attr)
        variables = Dict("test_var" => var)
        info = Dict("filename" => "test.cdf")

        cdf = CDF("test.cdf", attributes, variables, info)
        @test cdf.filename == "test.cdf"
        @test length(cdf.attributes) == 1
        @test length(cdf.variables) == 1
    end

    @testset "CDF info function" begin
        # Create a mock CDF object
        attr = CDFAttribute("TITLE", ["Test CDF"])
        var = CDFVariable("data", "CDF_REAL8", [3], 10,
                         Dict{String, CDFAttribute}(), nothing)

        cdf = CDF("mock.cdf",
                 Dict("TITLE" => attr),
                 Dict("data" => var),
                 Dict("format" => "cdf30001"))

        info = cdf_info(cdf)
        @test info["filename"] == "mock.cdf"
        @test info["num_variables"] == 1
        @test info["num_attributes"] == 1
        @test "data" in info["variable_names"]
        @test "TITLE" in info["attribute_names"]
    end

    @testset "Attribute access" begin
        attr = CDFAttribute("PROJECT", ["CommonDataFormat.jl"])
        cdf = CDF("test.cdf",
                 Dict("PROJECT" => attr),
                 Dict{String, CDFVariable}(),
                 Dict{String, Any}())

        result = attrget(cdf, "PROJECT")
        @test result == ["CommonDataFormat.jl"]

        # Test error for non-existent attribute
        @test_throws ErrorException attrget(cdf, "NONEXISTENT")
    end

end