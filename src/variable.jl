struct CDFVariable{A, DT}
    name::String
    data::A
    data_type::DT
    dimensions::Vector{Int}
    num_records::Int
end
