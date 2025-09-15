# CDR (CDF Descriptor Record) loading functionality
# Handles structured loading of the main CDF file header

"""
    CDR(io::IO, RecordSizeType) -> CDR

Load a CDF Descriptor Record from the IO stream at the specified offset.
This follows the CDF specification for CDR record structure.
"""
@inline function CDR(io::IO, RecordSizeType)
    # Read header
    header = Header(io, RecordSizeType)
    @assert header.record_type == 1 "Invalid CDR record type"
    # Read remaining CDR fields in order as per CDF specification
    gdr_offset = read_be(io, RecordSizeType)
    fields = read_be(io, 9, Int32)
    return CDR(header, gdr_offset, fields...)
end