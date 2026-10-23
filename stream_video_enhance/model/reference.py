"""Independent float64 and integer models of spec.md sections 4/5.

Image inputs are 2D uint8 arrays, 16<=W<=640 and 16<=H<=480. Smaller
dimensions support unit/ROI tests; the formal hardware configuration is VGA.
All public ``gain`` arguments mean integer Q8 G (0..512), so real gain is
G/256. DENOISE requires G=256. Modes are the uppercase spec names.
Both filters return uint8 pixels at original coordinates [4:H-4, 4:W-4].
No boundary padding, cycle timing, or parameter-profile recommendation is made.
"""
from numbers import Integral

import numpy as np


EPSILONS = (16, 64, 256, 1024)
MODES = ("RAW", "BASE", "DENOISE", "ENHANCE")


def _integer(value, name, low, high=None):
    if isinstance(value, (bool, np.bool_)) or not isinstance(value, Integral):
        raise TypeError(f"{name} must be an integer")
    value = int(value)
    if value < low or (high is not None and value > high):
        raise ValueError(f"{name} outside [{low}, {high}]")
    return value


def _dimensions(width, height):
    return (_integer(width, "width", 16, 640),
            _integer(height, "height", 16, 480))


def _image(image):
    if not isinstance(image, np.ndarray) or image.dtype != np.uint8:
        raise TypeError("image must be a uint8 ndarray")
    if image.ndim != 2:
        raise ValueError("image must have exactly two dimensions")
    _dimensions(image.shape[1], image.shape[0])
    return image


def _epsilon(epsilon):
    epsilon = _integer(epsilon, "epsilon", 16, 1024)
    if epsilon not in EPSILONS:
        raise ValueError(f"epsilon must be one of {EPSILONS}")
    return epsilon


def _enhancement_config(threshold, gain, limit):
    threshold = _integer(threshold, "threshold", 0, 16)
    gain = _integer(gain, "gain (integer Q8 G)", 0, 512)
    limit = _integer(limit, "limit", 16, 16)
    return threshold, gain, limit


def _config(epsilon, threshold, gain, mode, limit):
    epsilon = _epsilon(epsilon)
    threshold, gain, limit = _enhancement_config(threshold, gain, limit)
    if not isinstance(mode, str) or mode not in MODES:
        raise ValueError(f"mode must be one of {MODES}")
    if mode == "DENOISE" and gain != 256:
        raise ValueError("DENOISE requires integer Q8 gain=256")
    return epsilon, threshold, gain, limit


def _bounded_int64(value, name, maximum):
    scalar = isinstance(value, Integral) and not isinstance(value, (bool, np.bool_))
    if scalar:
        return np.asarray(_integer(value, name, 0, maximum), dtype=np.int64)
    if not isinstance(value, np.ndarray) or value.dtype != np.int64:
        raise TypeError(f"{name} must be an integer or int64 ndarray")
    if np.any(value < 0) or np.any(value > maximum):
        raise ValueError(f"{name} outside [0, {maximum}]")
    return value


def div25_exact(n):
    """floor(n/25) for 0<=n<=1,632,012; callers add 12 for RN.

    Uses the specified U41 full reciprocal product and one-step correction.
    This is deliberately an *unrounded* public division primitive.
    """
    n = _bounded_int64(n, "n", 1_632_012)
    q0 = (n * 671089) >> 24
    return q0 - (25 * q0 > n).astype(np.int64)


def ratio_q12(v, epsilon):
    """Exact RN(4096*V, V+625*epsilon), using integer full products.

    The offline oracle uses exact integer division; RTL implements the spec's
    12 fractional long-division stages plus rounding against this result.
    """
    epsilon = _epsilon(epsilon)
    v = _bounded_int64(v, "variance numerator", 10_143_900)
    denominator = v + 625 * epsilon
    return (4096 * v + denominator // 2) // denominator


def _sum5_int(values):
    """Valid 5x5 sums, with every prefix/full intermediate held in int64."""
    integral = np.zeros((values.shape[0] + 1, values.shape[1] + 1), dtype=np.int64)
    integral[1:, 1:] = values.cumsum(axis=0, dtype=np.int64).cumsum(axis=1, dtype=np.int64)
    return integral[5:, 5:] - integral[:-5, 5:] - integral[5:, :-5] + integral[:-5, :-5]


def fixed_layers(image, epsilon):
    """Integer checkpoints with exact two-window centering.

    s1/s2/variance_numerator/denominator/a_q12/mean_q8/b_q8/center are
    (H-4,W-4), centered at original (2,2). sum_a/sum_b/abar_q12/bbar_q8/
    base_q8/raw are (H-8,W-8), centered at original (4,4). All arithmetic
    checkpoint arrays are int64; center and raw are uint8 copies.
    """
    image = _image(image)
    epsilon = _epsilon(epsilon)
    pixels = image.astype(np.int64)
    s1 = _sum5_int(pixels)
    s2 = _sum5_int(pixels * pixels)
    variance = 25 * s2 - s1 * s1
    if np.any(variance < 0):
        raise ArithmeticError("negative exact variance numerator")
    denominator = variance + 625 * epsilon
    a = ratio_q12(variance, epsilon)
    if np.any(a > 4092):
        raise ArithmeticError("Q12 coefficient exceeds U12 ledger")
    mean = div25_exact(256 * s1 + 12)
    b = ((4096 - a) * mean + 2048) >> 12
    sum_a, sum_b = _sum5_int(a), _sum5_int(b)
    abar, bbar = div25_exact(sum_a + 12), div25_exact(sum_b + 12)
    raw = image[4:-4, 4:-4].copy()
    base = np.clip(((abar * raw.astype(np.int64) + 8) >> 4) + bbar, 0, 65280)
    return {"s1": s1, "s2": s2, "variance_numerator": variance,
            "denominator": denominator, "a_q12": a, "mean_q8": mean,
            "b_q8": b, "center": image[2:-2, 2:-2].copy(),
            "sum_a": sum_a, "sum_b": sum_b, "abar_q12": abar,
            "bbar_q8": bbar, "base_q8": base, "raw": raw}


def _pixel_q8(value):
    return ((np.clip(value, 0, 65280) + 128) >> 8).astype(np.uint8)


def enhance_fixed(raw, base_q8, threshold, gain, limit=16):
    """Apply spec steps 6/7 to aligned planes, including signed half ties.

    Aligned planes may be any nonempty 2D shape, including a single-pixel test;
    this function does not crop. base_q8 must already be within [0,65280].
    """
    threshold, gain, limit = _enhancement_config(threshold, gain, limit)
    if not isinstance(raw, np.ndarray) or raw.dtype != np.uint8:
        raise TypeError("raw must be a uint8 ndarray")
    if raw.ndim != 2 or raw.size == 0:
        raise ValueError("raw must be a nonempty 2D aligned plane")
    base = _bounded_int64(base_q8, "base_q8", 65280)
    if base.shape != raw.shape:
        raise ValueError("raw and base_q8 must have identical shapes")
    detail = raw.astype(np.int64) * 256 - base
    residual = np.sign(detail) * np.minimum(np.maximum(np.abs(detail) - threshold * 256, 0), limit * 256)
    # gain stays nonnegative int64 before multiplication; +/-half goes away from zero.
    product = gain * residual
    enhanced = np.sign(product) * ((np.abs(product) + 128) >> 8)
    return _pixel_q8(base + enhanced)


def filter_fixed(image, epsilon, threshold, gain, mode, limit=16):
    """Bit-exact numerical reference; gain is integer Q8 G, not real g."""
    epsilon, threshold, gain, limit = _config(epsilon, threshold, gain, mode, limit)
    layers = fixed_layers(image, epsilon)
    if mode == "RAW":
        return layers["raw"]
    if mode == "BASE":
        return _pixel_q8(layers["base_q8"])
    return enhance_fixed(layers["raw"], layers["base_q8"], threshold, gain, limit)


def _sum5_float(values):
    """Independent float64 valid-window accumulation (no integer path calls)."""
    integral = np.zeros((values.shape[0] + 1, values.shape[1] + 1), dtype=np.float64)
    integral[1:, 1:] = np.cumsum(np.cumsum(values, axis=0, dtype=np.float64), axis=1, dtype=np.float64)
    return integral[5:, 5:] - integral[:-5, 5:] - integral[5:, :-5] + integral[:-5, :-5]


def filter_float(image, epsilon, threshold, gain, mode, limit=16):
    """Float64 formula reference, quantizing only the final clipped pixel.

    Coefficients, both means, reconstruction and soft detail stay float64.
    Positive final half ties use floor(value+0.5), independent of Q8 helpers.
    """
    epsilon, threshold, gain, limit = _config(epsilon, threshold, gain, mode, limit)
    values = _image(image).astype(np.float64)
    sum1 = _sum5_float(values)
    sum2 = _sum5_float(values ** 2)
    variance = 25.0 * sum2 - sum1 ** 2
    if np.any(variance < 0.0):
        raise ArithmeticError("negative float64 variance numerator")
    a = variance / (variance + 625.0 * epsilon)
    b = (1.0 - a) * (sum1 / 25.0)
    abar = _sum5_float(a) / 25.0
    bbar = _sum5_float(b) / 25.0
    raw = values[4:-4, 4:-4]
    base = abar * raw + bbar
    if mode == "RAW":
        output = raw
    elif mode == "BASE":
        output = base
    else:
        detail = raw - base
        residual = np.sign(detail) * np.minimum(np.maximum(np.abs(detail) - threshold, 0.0), float(limit))
        output = base + (gain / 256.0) * residual
    return np.floor(np.clip(output, 0.0, 255.0) + 0.5).astype(np.uint8)


def pattern(width, height, frame_id, pattern_id=0):
    """Deterministic U8 source patterns; nonnegative frame IDs wrap modulo 2^32."""
    width, height = _dimensions(width, height)
    frame_id = _integer(frame_id, "frame_id", 0) % (1 << 32)
    pattern_id = _integer(pattern_id, "pattern_id", 0, 3)
    yy, xx = np.indices((height, width), dtype=np.int64)
    if pattern_id == 0:
        values = (xx + yy + frame_id) % 256
    elif pattern_id == 1:
        values = np.where((xx // 16 + yy // 16) % 2 == 0, 32, 224)
    elif pattern_id == 2:
        values = np.where(2 * xx < width, 32, 224)
    else:
        values = np.full((height, width), 128, dtype=np.int64)
    return values.astype(np.uint8)
