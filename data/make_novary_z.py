# z-var "novary": declared (2,3,4) with dim 2 NOVARY, so each record stores 2x4 values.
# cdflib/CDFpp writers ignore Dim_Vary, so write (2,1,4) and patch the zVDR's dim 2 to size 3, NOVARY.
import sys, struct, numpy as np
from cdflib.cdfwrite import CDF
out = sys.argv[1]
c = CDF(out, cdf_spec={"Majority": "row_major"}, delete=True)
data = np.arange(5 * 2 * 4, dtype=np.int32).reshape(5, 2, 1, 4)
c.write_var({"Variable": "novary", "Data_Type": 4, "Num_Elements": 1, "Rec_Vary": True,
             "Var_Type": "zVariable", "Dim_Sizes": [2, 1, 4]}, var_attrs={}, var_data=data)
c.close()
b = bytearray(open(out, "rb").read())
p = b.find(b"novary".ljust(256, b"\0")) + 256  # zNumDims follows the 256-byte name
assert b.count(b"novary") == 1 and struct.unpack(">i", b[p:p + 4])[0] == 3
b[p + 8:p + 12] = struct.pack(">i", 3)   # zDimSizes[2]
b[p + 20:p + 24] = struct.pack(">i", 0)  # DimVarys[2]
open(out, "wb").write(b)
