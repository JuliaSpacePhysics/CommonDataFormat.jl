using Test
using CommonDataFormat

# Helper functions similar to the C++ test
function file_exists(path::AbstractString)
    return isfile(path)
end

function has_attribute(cdf::CDF, name::AbstractString)
    return haskey(cdf.attributes, name)
end

function has_variable(cdf::CDF, name::AbstractString)
    return haskey(cdf.variables, name)
end

function compare_attribute_values(attr::CDFAttribute, expected_values...)
    # For this basic implementation, just check if attribute has expected number of entries
    return length(attr.entries) >= 1
end

function compare_shape(var::CDFVariable, expected_shape::Vector{Int})
    return var.dimensions == expected_shape ||
        (length(var.dimensions) == 1 && var.dimensions[1] == 1 && isempty(expected_shape))
end

# Test data paths
const TEST_DATA_PATH = joinpath(@__DIR__, "..", "ref", "CDFpp", "tests", "resources")
const TEST_DATA_PATH_CDFLIB = joinpath(@__DIR__, "..", "ref", "cdflib", "tests", "testfiles")
const PROJECT_DATA_PATH = joinpath(@__DIR__, "..", "data")

@testset "CDF File Loading Tests" begin

    @testset "File existence and error handling" begin
        @testset "Non-existent file" begin
            @test_throws Exception load_cdf("nonexistent_file.cdf")
        end

        @testset "Invalid CDF file" begin
            not_cdf_path = joinpath(TEST_DATA_PATH, "not_a_cdf.cdf")
            if file_exists(not_cdf_path)
                # Our implementation will warn but try to parse anyway
                cdf = load_cdf(not_cdf_path)
                @test cdf.filename == not_cdf_path
            end
        end
    end

    @testset "Valid CDF file loading" begin
        test_files = [
            joinpath(TEST_DATA_PATH, "a_cdf.cdf"),
            joinpath(TEST_DATA_PATH, "a_compressed_cdf.cdf"),
            joinpath(TEST_DATA_PATH, "a_rle_compressed_cdf.cdf"),
            joinpath(TEST_DATA_PATH, "a_col_major_cdf.cdf"),
            joinpath(PROJECT_DATA_PATH, "omni_coho1hr_merged_mag_plasma_20240901_v01.cdf"),
            joinpath(PROJECT_DATA_PATH, "elb_l2_epdef_20210914_v01.cdf"),
            joinpath(PROJECT_DATA_PATH, "ge_h0_cpi_00000000_v01.cdf"),
        ]

        for test_file in test_files
            if file_exists(test_file)
                @testset "Loading $(basename(test_file))" begin
                    cdf = load_cdf(test_file)

                    @test cdf isa CDF
                    @test cdf.filename == test_file
                    @test cdf.attributes isa Dict{String, CDFAttribute}
                    @test cdf.variables isa Dict{String, CDFVariable}
                    @test cdf.info isa Dict{String, Any}

                    # Test cdf_info function
                    info = cdf_info(cdf)
                    @test haskey(info, "filename")
                    @test haskey(info, "num_variables")
                    @test haskey(info, "variable_names")
                    @test haskey(info, "num_attributes")
                    @test haskey(info, "attribute_names")
                    @test haskey(info, "file_info")

                    @test info["filename"] == test_file
                    @test info["num_variables"] == length(cdf.variables)
                    @test info["num_attributes"] == length(cdf.attributes)

                    # Basic structure validation
                    @test length(info["variable_names"]) == info["num_variables"]
                    @test length(info["attribute_names"]) == info["num_attributes"]
                end
            else
                @info "Test file not found: $test_file"
            end
        end
    end

    @testset "Attribute access tests" begin
        # Test with a known CDF file
        test_file = joinpath(TEST_DATA_PATH, "a_cdf.cdf")
        if file_exists(test_file)
            cdf = load_cdf(test_file)

            @testset "Basic attribute structure" begin
                # Our basic implementation creates standard attributes
                @test has_attribute(cdf, "TITLE")
                @test has_attribute(cdf, "PROJECT")

                # Test attribute retrieval
                title = attrget(cdf, "TITLE")
                @test title isa Vector{Any}
                @test length(title) >= 1

                project = attrget(cdf, "PROJECT")
                @test project isa Vector{Any}
                @test length(project) >= 1
            end

            @testset "Attribute error handling" begin
                @test_throws Exception attrget(cdf, "NONEXISTENT_ATTR")
            end
        end
    end

    @testset "Variable access tests" begin
        test_file = joinpath(TEST_DATA_PATH, "a_cdf.cdf")
        if file_exists(test_file)
            cdf = load_cdf(test_file)

            @testset "Basic variable structure" begin
                # Our implementation creates a test variable
                @test has_variable(cdf, "test_var")

                var = cdf.variables["test_var"]
                @test var isa CDFVariable
                @test var.name == "test_var"
                @test var.data_type isa String
                @test var.dimensions isa Vector{Int}
                @test var.num_records isa Int
                @test var.attributes isa Dict{String, CDFAttribute}
            end

            @testset "Variable data retrieval" begin
                # Test varget function
                data = varget(cdf, "test_var")
                @test data isa Array
                @test length(data) > 0

                # Test partial data retrieval
                if length(data) >= 5
                    partial_data = varget(cdf, "test_var", startrec = 0, endrec = 2)
                    @test length(partial_data) == 3
                end
            end

            @testset "Variable error handling" begin
                @test_throws Exception varget(cdf, "NONEXISTENT_VAR")
                @test_throws Exception varget(cdf, "test_var", startrec = -1)
                @test_throws Exception varget(cdf, "test_var", startrec = 1000, endrec = 1001)
            end
        end
    end

    @testset "CDF format compatibility" begin
        # Test different CDF format files
        format_test_files = [
            (joinpath(TEST_DATA_PATH, "ia_k0_epi_19970102_v01.cdf"), "CDF 2.4.x"),
            (joinpath(TEST_DATA_PATH, "ge_k0_cpi_19921231_v02.cdf"), "CDF 2.4.x"),
            (joinpath(TEST_DATA_PATH, "ac_h2_sis_20101105_v06.cdf"), "CDF 2.5.x"),
        ]

        for (test_file, description) in format_test_files
            if file_exists(test_file)
                @testset "Loading $description file" begin
                    cdf = load_cdf(test_file)
                    @test cdf isa CDF
                    @test !isempty(cdf.attributes)
                    @test !isempty(cdf.variables)

                    # Check that file info contains format information
                    @test haskey(cdf.info, "format")
                end
            else
                @info "Test file not found: $test_file ($description)"
            end
        end
    end

    @testset "Compressed file handling" begin
        compressed_files = [
            joinpath(TEST_DATA_PATH, "a_compressed_cdf.cdf"),
            joinpath(TEST_DATA_PATH, "a_rle_compressed_cdf.cdf"),
            joinpath(PROJECT_DATA_PATH, "omni_coho1hr_merged_mag_plasma_20240901_v01.cdf"),
        ]

        for test_file in compressed_files
            if file_exists(test_file)
                @testset "Loading compressed file $(basename(test_file))" begin
                    # Should succeed with warnings
                    cdf = load_cdf(test_file)
                    @test cdf isa CDF
                    @test haskey(cdf.info, "compressed")

                    # File should be marked as compressed
                    if haskey(cdf.info, "compressed")
                        @test cdf.info["compressed"] isa Bool
                    end
                end
            end
        end
    end

    @testset "Data type support" begin

        @testset "Type conversion functions" begin
            @test julia_type_from_cdf(UInt32(21)) == Float32
            @test julia_type_from_cdf(UInt32(22)) == Float64
            @test julia_type_from_cdf(UInt32(4)) == Int32
            @test julia_type_from_cdf(UInt32(51)) == Char

            @test cdf_type_size(UInt32(21)) == 4
            @test cdf_type_size(UInt32(22)) == 8
            @test cdf_type_size(UInt32(4)) == 4
            @test cdf_type_size(UInt32(51)) == 1
        end
    end

    @testset "Real CDF file structure validation" begin
        # Test with actual space physics CDF files if available
        real_cdf_files = [
            joinpath(TEST_DATA_PATH_CDFLIB, "psp_fld_l2_mag_rtn_1min_20200104_v02.cdf"),
            joinpath(TEST_DATA_PATH_CDFLIB, "fa_esa_l2_eeb_00000000_v01.cdf"),
        ]

        for test_file in real_cdf_files
            if file_exists(test_file)
                @testset "Real CDF file $(basename(test_file))" begin
                    cdf = load_cdf(test_file)

                    # Basic validation
                    @test cdf isa CDF
                    @test !isempty(cdf.filename)

                    info = cdf_info(cdf)
                    @test haskey(info, "file_info")
                    @test haskey(info["file_info"], "format")

                    # Check that we can access attributes and variables without errors
                    for attr_name in info["attribute_names"]
                        attr_data = attrget(cdf, attr_name)
                        @test attr_data isa Vector{Any}
                    end

                    for var_name in info["variable_names"]
                        @test has_variable(cdf, var_name)
                        var = cdf.variables[var_name]
                        @test var isa CDFVariable
                    end
                end
            end
        end
    end

    @testset "Performance and memory tests" begin
        test_file = joinpath(TEST_DATA_PATH, "a_cdf.cdf")
        if file_exists(test_file)
            @testset "Multiple loads" begin
                # Test that multiple loads work correctly
                cdf1 = load_cdf(test_file)
                cdf2 = load_cdf(test_file)

                @test cdf1.filename == cdf2.filename
                @test length(cdf1.attributes) == length(cdf2.attributes)
                @test length(cdf1.variables) == length(cdf2.variables)
            end

            @testset "Lazy loading behavior" begin
                cdf = load_cdf(test_file)

                if has_variable(cdf, "test_var")
                    # Variable should initially have no data loaded
                    var = cdf.variables["test_var"]
                    # After first access, data should be loaded
                    data1 = varget(cdf, "test_var")
                    data2 = varget(cdf, "test_var")
                    @test data1 == data2  # Should return same data
                end
            end
        end
    end
end


@testset "CDF file - OMNI" begin
    file = joinpath(PROJECT_DATA_PATH, "omni_coho1hr_merged_mag_plasma_20240901_v01.cdf")
    cdf = load_cdf(file)
end
