"""Writes PNG test files in every colour type, bit depth, filter and
interlace mode, plus the RGBA pixels each one must decode to (.rgba).
    python3 tests/make_png_fixtures.py tests/fixtures/png
"""
import os, struct, sys, zlib

W, H = 13, 9  # odd sizes exercise partial bytes and Adam7 edges


def chunk(kind, data):
    c = struct.pack(">I", len(data)) + kind + data
    return c + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


def paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    return a if pa <= pb and pa <= pc else (b if pb <= pc else c)


def filter_rows(rows, bpp):
    out, prev = b"", bytes(len(rows[0])) if rows else b""
    for i, row in enumerate(rows):
        f = i % 5
        enc = bytearray()
        for j, x in enumerate(row):
            a = row[j - bpp] if j >= bpp else 0
            b = prev[j]
            c = prev[j - bpp] if j >= bpp else 0
            pred = [0, a, b, (a + b) >> 1, paeth(a, b, c)][f]
            enc.append((x - pred) & 0xFF)
        out += bytes([f]) + bytes(enc)
        prev = row
    return out


def pack_row(samples, depth):
    if depth == 8:
        return bytes(samples)
    if depth == 16:
        return b"".join(struct.pack(">H", s) for s in samples)
    out, acc, n = bytearray(), 0, 0
    for s in samples:
        acc = (acc << depth) | s
        n += depth
        if n == 8:
            out.append(acc)
            acc, n = 0, 0
    if n:
        out.append(acc << (8 - n))
    return bytes(out)


ADAM7 = [(0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4), (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2)]


def write(path, ctype, depth, pixels, plte=None, trns=None, interlace=False, level=9):
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ctype]
    bpp = max(1, channels * depth // 8)
    raw = b""
    passes = ADAM7 if interlace else [(0, 0, 1, 1)]
    for x0, y0, dx, dy in passes:
        xs = list(range(x0, W, dx))
        ys = list(range(y0, H, dy))
        if not xs or not ys:
            continue
        rows = [pack_row([s for x in xs for s in pixels[y][x]], depth) for y in ys]
        raw += filter_rows(rows, bpp)
    z = zlib.compress(raw, level)
    ihdr = struct.pack(">IIBBBBB", W, H, depth, ctype, 0, 0, 1 if interlace else 0)
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
    if plte:
        data += chunk(b"PLTE", plte)
    if trns:
        data += chunk(b"tRNS", trns)
    for i in range(0, len(z), 40):  # several IDAT chunks
        data += chunk(b"IDAT", z[i:i + 40])
    data += chunk(b"IEND", b"")
    open(path, "wb").write(data)


def expected(path, rgba):
    open(path, "wb").write(bytes(v for y in range(H) for x in range(W) for v in rgba(x, y)))


def main(out):
    os.makedirs(out, exist_ok=True)
    seed = lambda x, y, k: (x * 37 + y * 101 + k * 53 + x * y * 7) & 0xFFFF
    cases = []
    for depth in (1, 2, 4, 8, 16):
        maxv = (1 << depth) - 1
        g = [[(seed(x, y, 0) % (maxv + 1),) for x in range(W)] for y in range(H)]
        def e(x, y, g=g, depth=depth, maxv=maxv):
            v = g[y][x][0]
            v8 = v >> 8 if depth == 16 else (v if depth == 8 else v * 255 // maxv)
            return (v8, v8, v8, 255)
        cases.append((f"gray{depth}", 0, depth, g, None, None, e))
    # grey with a transparent key colour
    g = [[((x + y) % 4 * 85,) for x in range(W)] for y in range(H)]
    cases.append(("gray8_trns", 0, 8, g, None, struct.pack(">H", 170),
                  lambda x, y: (0, 0, 0, 0) if g[y][x][0] == 170 else (g[y][x][0],) * 3 + (255,)))
    for depth in (8, 16):
        mx = (1 << depth) - 1
        rgb = [[tuple(seed(x, y, k) % (mx + 1) for k in range(3)) for x in range(W)] for y in range(H)]
        hi = (lambda v: v >> 8) if depth == 16 else (lambda v: v)
        cases.append((f"rgb{depth}", 2, depth, rgb, None, None,
                      lambda x, y, rgb=rgb, hi=hi: tuple(hi(v) for v in rgb[y][x]) + (255,)))
        rgba = [[tuple(seed(x, y, k) % (mx + 1) for k in range(4)) for x in range(W)] for y in range(H)]
        cases.append((f"rgba{depth}", 6, depth, rgba, None, None,
                      lambda x, y, rgba=rgba, hi=hi: tuple(hi(v) for v in rgba[y][x])))
        ga = [[tuple(seed(x, y, k) % (mx + 1) for k in range(2)) for x in range(W)] for y in range(H)]
        cases.append((f"graya{depth}", 4, depth, ga, None, None,
                      lambda x, y, ga=ga, hi=hi: (hi(ga[y][x][0]),) * 3 + (hi(ga[y][x][1]),)))
    rgb = [[((x * 40) % 256, (y * 60) % 256, 30) for x in range(W)] for y in range(H)]
    key = rgb[2][3]
    cases.append(("rgb8_trns", 2, 8, rgb, None, struct.pack(">HHH", *key),
                  lambda x, y: (0, 0, 0, 0) if rgb[y][x] == key else rgb[y][x] + (255,)))
    for depth in (1, 2, 4, 8):
        n = 1 << depth
        pal = [((i * 47) % 256, (i * 91) % 256, (i * 13) % 256) for i in range(n)]
        alpha = [(i * 60) % 256 for i in range(n // 2 + 1)]  # shorter than the palette
        idx = [[(seed(x, y, 3) % n,) for x in range(W)] for y in range(H)]
        def e(x, y, idx=idx, pal=pal, alpha=alpha):
            i = idx[y][x][0]
            return pal[i] + ((alpha[i] if i < len(alpha) else 255),)
        cases.append((f"palette{depth}", 3, depth, idx, bytes(v for c in pal for v in c), bytes(alpha), e))
    for name, ctype, depth, pixels, plte, trns, exp in cases:
        write(os.path.join(out, name + ".png"), ctype, depth, pixels, plte, trns)
        expected(os.path.join(out, name + ".rgba"), exp)
        if name in ("rgba8", "palette4", "gray16"):
            write(os.path.join(out, name + "_interlaced.png"), ctype, depth, pixels, plte, trns, interlace=True)
            expected(os.path.join(out, name + "_interlaced.rgba"), exp)
        if name == "rgba8":
            write(os.path.join(out, "rgba8_stored.png"), ctype, depth, pixels, plte, trns, level=0)
            expected(os.path.join(out, "rgba8_stored.rgba"), exp)
    print(f"wrote {len(os.listdir(out)) // 2} PNG fixtures to {out}")


main(sys.argv[1])
