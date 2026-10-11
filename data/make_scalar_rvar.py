# Scalar r-variable: rNumDims = 0 in the GDR.
# Run: uv run --with cdflib python data/make_scalar_rvar.py data/scalar_rvar.cdf
import sys
import numpy as np
from cdflib.cdfwrite import CDF

c = CDF(sys.argv[1], cdf_spec={"rDim_sizes": []}, delete=True)
spec = {"Variable": "x", "Var_Type": "rvariable", "Data_Type": 45, "Num_Elements": 1, "Rec_Vary": True, "Dim_Sizes": [], "Dim_Vary": []}
c.write_var(spec, var_data=np.arange(5.0))
c.close()
