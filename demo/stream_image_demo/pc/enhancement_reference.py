"""Integer reference model for the standalone two-scale enhancement pipeline."""
def fixture_pixel(frame, x, y, width):
    if frame == 0:
        return 80
    if frame == 1:
        return 255 if (x + y) % 2 else 0
    if frame == 3:
        return (40 if x < width // 2 else 220) + (x + y) % 3
    return (x * 17 + y * 31 + frame * 43) % 256


def fixture_controls(frame):
    return ((16, 16, 255), (48, 32, 255), (24, 20, 32),
            (0, 0, 0), (255, 255, 255))[frame]


def smooth(image, epsilon):
    height, width = len(image), len(image[0])
    result = []
    for y in range(1, height - 1):
        row = []
        for x in range(1, width - 1):
            values = [image[yy][xx] for yy in range(y - 1, y + 2)
                      for xx in range(x - 1, x + 2)]
            total = sum(values)
            mean = total // 9
            variance81 = 9 * sum(v * v for v in values) - total * total
            center = image[y][x]
            if variance81 <= epsilon * 81:
                value = mean
            elif variance81 <= epsilon * 324:
                value = (center + mean) // 2
            else:
                value = (3 * center + mean) // 4
            row.append(value)
        result.append(row)
    return result


def enhance(image, fine_gain=24, coarse_gain=16, limit=32,
            epsilon_fine=64, epsilon_coarse=256):
    fine = smooth(image, epsilon_fine)
    coarse = smooth(fine, epsilon_coarse)
    result = []
    for y, row in enumerate(coarse):
        output = []
        for x, base in enumerate(row):
            raw = image[y + 2][x + 2]
            middle = fine[y + 1][x + 1]
            df = max(-limit, min(limit, raw - middle))
            dc = max(-limit, min(limit, middle - base))
            value = base + (fine_gain * df + coarse_gain * dc) // 16
            output.append((raw, middle, base, max(0, min(255, value))))
        result.append(output)
    return result
