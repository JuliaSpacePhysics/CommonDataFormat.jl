# Sparse-record variables: physical records 0-2, 6-7, 10 (0-based) in 3-record VVR blocks.
# Run: uv run --with cdflib python data/make_sparse_cdf.py data/sparse.cdf
import sys
import numpy as np
from cdflib.cdfwrite import CDF

c = CDF(sys.argv[1], delete=True)
phys = np.array([0, 1, 2, 6, 7, 10])
base = {"Data_Type": 45, "Num_Elements": 1, "Rec_Vary": True, "Dim_Sizes": [], "Block_Factor": 3}
data = np.array([10.0, 11.0, 12.0, 16.0, 17.0, 20.0])
c.write_var({**base, "Variable": "pad_default", "Sparse": "pad_sparse"}, var_data=[phys, data])
c.write_var({**base, "Variable": "pad_explicit", "Sparse": "pad_sparse", "Pad": np.array([-99.0])}, var_data=[phys, data])
c.write_var({**base, "Variable": "prev", "Sparse": "prev_sparse"}, var_data=[phys, data])
c.write_var({**base, "Variable": "pad2d", "Dim_Sizes": [2], "Sparse": "pad_sparse", "Pad": np.array([-99.0])},
            var_data=[phys, np.arange(12.0).reshape(6, 2)])
c.close()
