"""Independent direct 25-point window oracle, cross-checked against fixed_layers."""
import importlib.util
from pathlib import Path
import numpy as np


def generate_window_vectors(path, width, height, quick=False):
    root = Path(__file__).resolve().parents[1]
    spec = importlib.util.spec_from_file_location("reference", root / "model/reference.py")
    reference = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(reference)
    y, x = np.indices((height, width))
    rng = np.random.default_rng(20261024 + width)
    impulse = np.zeros((height, width), dtype=np.int64)
    impulse[height//2, width//2] = 255
    patterns = [("structured", (17*x + 31*y + (x*y)%19) % 256),
                ("impulse", impulse), ("row_ramp", (13*y + x) % 256),
                ("random", rng.integers(0,256,(height,width))),
                ("zero", np.zeros((height,width),dtype=np.int64)),
                ("maximum", np.full((height,width),255,dtype=np.int64)),
                ("checker", ((x+y)%2)*255)]
    if quick or width == 640:
        patterns = patterns[:1]

    def direct25(v):
        # Add all 25 spatial slices independently; no integral or recurrence.
        result = np.zeros((v.shape[0]-4,v.shape[1]-4),dtype=np.int64)
        for dy in range(5):
            for dx in range(5):
                result += v[dy:dy+result.shape[0], dx:dx+result.shape[1]]
        return result

    counts = []
    names = []
    for number, (name,pixels) in enumerate(patterns):
        p = pixels.astype(np.int64)
        epsilon = (16,64,256,1024)[number%4]
        s1, s2 = direct25(p), direct25(p*p)
        variance = 25*s2-s1*s1
        den = variance+625*epsilon
        a = (4096*variance+den//2)//den
        mean = (256*s1+12)//25
        b = ((4096-a)*mean+2048)//4096
        abar, bbar = (direct25(a)+12)//25, (direct25(b)+12)//25
        checkpoints = reference.fixed_layers(p.astype(np.uint8),epsilon)
        for key, value in [("s1",s1),("s2",s2),("a_q12",a),("b_q8",b),
                           ("abar_q12",abar),("bbar_q8",bbar)]:
            np.testing.assert_array_equal(value,checkpoints[key])
        if name == "maximum":
            assert (s1[0,0],s2[0,0],a[0,0],b[0,0],abar[0,0],bbar[0,0]) == (6375,1625625,0,65280,0,65280)
        if name == "zero":
            assert all(not np.any(v) for v in [s1,s2,a,b,abar,bbar])
        planes = [p]
        for v, crop in [(s1,2),(s2,2),(a,2),(b,2),(abar,4),(bbar,4)]:
            padded=np.zeros_like(p)
            padded[crop:-crop,crop:-crop]=v
            planes.append(padded)
        filename=f"{name}.txt"
        np.savetxt(path/filename,np.stack(planes,axis=-1).reshape(-1,7),fmt="%d")
        names.append(filename)
        counts.append({"pattern":name,"epsilon":epsilon,"moments":s1.size,"box":abar.size})
    (path/"cases.txt").write_text("\n".join(names)+"\n")
    return {"width":width,"height":height,"cases":counts,"oracle":"direct25 plus fixed_layers crosscheck"}
