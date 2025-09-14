# CDR (CDF Descriptor Record) loading functionality
# Handles structured loading of the main CDF file header

"""
    load_cdr(io::IO, offset::Int, is_v3::Bool) -> CDR

Load a CDF Descriptor Record from the IO stream at the specified offset.
This follows the CDF specification for CDR record structure.

# Arguments
- `io`: IO stream to read from
- `offset`: Byte offset where CDR starts (typically 8)
- `is_v3`: Whether this is a CDF v3 file (affects field sizes)

# Returns
- `CDR`: Parsed CDR structure with all fields
"""
@inline function load_cdr(io::IO, offset, RecordSizeType)
    seek(io, offset)
    # Read header
    header = Header(io, RecordSizeType)
    @assert header.record_type == 1 "Invalid CDR record type"
    # Read remaining CDR fields in order as per CDF specification
    gdr_offset = read_be(io, RecordSizeType)
    fields = read_be(io, 9, Int32)
    return CDR(header, gdr_offset, fields...)
end

"""
    parse_cdf_header(io::IO, magic_bytes::Vector{UInt8}, compression_bytes::Vector{UInt8}) -> FileHeader

Parse the CDF file header using a structured approach.
This is the main entry point for reading CDF file metadata.
    
# Returns
- `FileHeader`: Parsed file header with version, majority, compression, and CDR
"""
function parse_cdf_header(io::IO, RecordSizeType, compression)
    # Load CDR record starting at offset 8
    cdr = load_cdr(io, 8, RecordSizeType)
    # Extract file properties from CDR
    version, majority = extract_file_properties(cdr)

    return FileHeader(version, majority, compression, cdr)
end
