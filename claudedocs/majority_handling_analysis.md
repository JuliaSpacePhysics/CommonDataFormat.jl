# CDF Majority Handling Analysis

## Summary

This document explains how CDF files handle row-major vs column-major data layout and how different implementations (cdflib, CDFpp) handle this difference.

## Background: Row-Major vs Column-Major

### Data Layout
- **Row-Major** (C-style): Elements of each row are stored contiguously in memory
  - Used by: C, C++, Python (NumPy default), Row
  - For array `A[i,j,k]`, index `k` varies fastest

- **Column-Major** (Fortran-style): Elements of each column are stored contiguously
  - Used by: Fortran, MATLAB, Julia, R
  - For array `A[i,j,k]`, index `i` varies fastest

### CDF Specification
CDF files can be created with either:
- **Row-Major** (flag bit 0 = 1): Row-majority storage
- **Column-Major** (flag bit 0 = 0): Column-majority storage

The majority is stored in the CDR (CDF Descriptor Record) flags field:
- Bit 0: Majority (1 = row-major, 0 = column-major)

## Python cdflib Implementation

### Dimension Reversal for Column-Major
File: `ref/cdflib/cdflib/cdfread.py:1655-1656`
```python
if self._majority == "Column_major":
    dimensions = list(reversed(dimensions))
```

### Array Transposition After Loading
File: `ref/cdflib/cdflib/cdfread.py:1749-1754`
```python
if self._majority == "Column_major":
    if dimensions is not None:
        axes = [0] + list(range(len(dimensions), 0, -1))
    else:
        axes = None
    ret = np.transpose(ret, axes=axes)
```

### Logic
1. **Before loading**: Reverse dimension sizes if column-major
2. **After loading**: Transpose the array to match Python's row-major layout
3. **Record dimension**: First dimension (axis 0) is always the record count and is NOT reversed

Example for column-major CDF with dims `[3, 4, 5]` and 10 records:
1. Read dims as `[3, 4, 5]`
2. Reverse to `[5, 4, 3]` for loading
3. Shape becomes `(10, 5, 4, 3)` after adding records
4. Transpose with `axes=[0, 3, 2, 1]` → final shape `(10, 3, 4, 5)`

## C++ CDFpp Implementation

### Majority Swap Function
File: [ref/CDFpp/include/cdfpp/cdf-io/majority-swap.hpp](../ref/CDFpp/include/cdfpp/cdf-io/majority-swap.hpp)

The implementation uses an in-place element reordering strategy:

```cpp
template <bool is_string, typename shape_t, typename data_t>
void swap(data_t& data, const shape_t& shape)
{
    // Only swap if dimensions > 2 (excluding record dimension)
    if ((dimensions > 2 && !is_string) or (is_string and dimensions > 3))
    {
        // Generate access pattern for index mapping
        const auto access_patern = _private::generate_access_pattern(record_shape);

        // For each record, reorder elements according to access pattern
        for (auto record = 0UL; record < records_count; record++)
        {
            for (const auto& swap_pair : access_patern)
            {
                temporary_record[swap_pair.src] = data[offset + swap_pair.dest];
            }
            std::memcpy(data.data() + offset, temporary_record.data(), bytes_per_record);
            offset += elements_per_record;
        }
    }
}
```

### When Swap is Applied
File: [ref/CDFpp/include/cdfpp/variable.hpp:93-96](../ref/CDFpp/include/cdfpp/variable.hpp#L93-L96)

```cpp
Variable(const std::string& name, std::size_t number, data_t&& data, shape_t&& shape,
    cdf_majority majority = cdf_majority::row, ...)
{
    if (this->majority() == cdf_majority::column)
    {
        majority::swap(_data(), p_shape);  // Swap for column-major files
    }
}
```

### Logic
1. **Load data as-is** from the file
2. **If column-major**: Apply in-place element reordering
3. **Result**: Data layout matches the C++ row-major convention

### Index Calculation
The key is the `flat_index` calculation:

- **Row-major index**: `i*shape[1]*shape[2] + j*shape[2] + k`
- **Column-major index**: `k*shape[1]*shape[0] + j*shape[0] + i`

The swap function creates a mapping between these two indexing schemes.

## References

- CDF Internal Format Specification: https://cdf.gsfc.nasa.gov/
- Python cdflib: [ref/cdflib/cdflib/cdfread.py](../ref/cdflib/cdflib/cdfread.py)
- CDFpp: [ref/CDFpp/include/cdfpp/cdf-io/majority-swap.hpp](../ref/CDFpp/include/cdfpp/cdf-io/majority-swap.hpp)
