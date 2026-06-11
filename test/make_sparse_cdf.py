# Generate data/a_sparse_cdf.cdf: sparse-record fixtures (pad & prev semantics).
# Run: uv run --with cdflib python test/make_sparse_cdf.py
from pathlib import Path

import numpy as np
from cdflib import cdfwrite

out = Path(__file__).parent.parent / "data" / "a_sparse_cdf.cdf"
out.unlink(missing_ok=True)
f = cdfwrite.CDF(out)

# physical records 0-2, 6-7, 10 (0-based); virtual gaps at 3-5, 8-9
phys = np.array([0, 1, 2, 6, 7, 10])
data = np.array([10.0, 11.0, 12.0, 16.0, 17.0, 20.0])

base = {
    "Data_Type": 45,  # CDF_DOUBLE
    "Num_Elements": 1,
    "Rec_Vary": True,
    "Dim_Sizes": [],
    "Compress": 0,
    "Block_Factor": 3,  # force multiple VVR blocks
}
f.write_var({**base, "Variable": "pad_default", "Sparse": "pad_sparse"}, var_data=[phys, data])
f.write_var(
    {**base, "Variable": "pad_explicit", "Sparse": "pad_sparse", "Pad": np.array([-99.0])},
    var_data=[phys, data],
)
f.write_var({**base, "Variable": "prev", "Sparse": "prev_sparse"}, var_data=[phys, data])

data2d = np.arange(12.0).reshape(6, 2)
f.write_var(
    {**base, "Variable": "pad2d", "Dim_Sizes": [2], "Sparse": "pad_sparse", "Pad": np.array([-99.0])},
    var_data=[phys, data2d],
)
f.close()

# sanity-check with the cdflib reader
import cdflib

r = cdflib.CDF(out)
print("pad_default:", r.varget("pad_default"))
print("pad_explicit:", r.varget("pad_explicit"))
print("prev:", r.varget("prev"))
print("pad2d:", r.varget("pad2d").tolist())
