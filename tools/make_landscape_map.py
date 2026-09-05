#!/usr/bin/env python3
"""Rebuilds data/map.aseprite as a 16:9 map and shifts data/map.resource.

The director frames a 16:9 window. The village as drawn is 748x941 --
portrait -- so every wide shot either letterboxed into black bars or had
to be faked out over a painted backdrop. This widens the map itself
instead, so the wide shot is the whole map and no frame ever shows
anything that is not map.

Nothing about the village is redrawn. The 748x941 artwork is copied
verbatim into the middle of a 1680x945 canvas -- every house, garden,
plaza, well, path, fence and flower lands exactly where it was drawn,
relative to everything else -- and the new margins are filled with the
map's own tree canopy, sampled from patches of the existing forest and
stamped with random flips and offsets so the fill reads as more of the
same wood rather than a tiled pattern. No external image and no
generated noise: every pixel of the fill came off this map.

The walkable and overhang layers are copied with the same offset, and
the new margin is left non-walkable, so the walk mask, every path, and
every door keep exactly the connectivity they had.

  python3 tools/make_landscape_map.py

Rewrites data/map.aseprite and data/map.resource in place. Re-render
docs/heartleafMap.png afterwards with tools/gen_banner.nim.
"""

import os
import random
import re
import sys
from collections import deque

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from asefile import Aseprite, Layer, read_aseprite, write_aseprite, write_png

DATA = os.path.join(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))), "data")
MAP = os.path.join(DATA, "map.aseprite")
RESOURCE = os.path.join(DATA, "map.resource")

# 945 is the first height at or above the drawn map that divides by 9, so
# the canvas is exactly 16:9 and the director's crop never has to round.
NEW_H = 945
NEW_W = NEW_H // 9 * 16
# Patch edges are hard, never blended: the map is drawn in a strict
# 16-colour palette and any blend would invent colours outside it.
FEATHER = 0
SEED = 20260904


def parse_rects(text):
    """Reads the CSS-ish rectangle blocks out of a .resource file."""
    out = []
    for m in re.finditer(r"/\* *([A-Za-z0-9_]+) *\*/(.*?)(?=/\*|\Z)",
                         text, re.S):
        body = m.group(2)

        def field(key):
            hit = re.search(key + r":\s*(-?\d+)px", body)
            return int(hit.group(1)) if hit else None

        w, h, l, t = (field("width"), field("height"),
                      field("left"), field("top"))
        if None not in (w, h, l, t):
            out.append((m.group(1), l, t, w, h))
    return out


def shift_resource(text, dx, dy):
    """Shifts every left/top in a .resource file by a fixed offset.

    Only the coordinates move; widths, heights, names, colours and the
    file's shape are untouched, so the rectangles still name exactly the
    pixels they named before.
    """
    lines = text.split("\n")
    out = []
    for line in lines:
        m = re.match(r"^(\s*)(left|top):\s*(-?\d+)px;(.*)$", line)
        if m:
            delta = dx if m.group(2) == "left" else dy
            out.append("%s%s: %dpx;%s" % (m.group(1), m.group(2),
                                          int(m.group(3)) + delta, m.group(4)))
        else:
            out.append(line)
    return "\n".join(out)


def forest_masks(ase):
    """Splits the map into outside forest, house mounds, and clean canopy.

    Outside forest is the non-walkable region the map border reaches;
    the mounds are the non-walkable blobs the paths enclose. Clean
    canopy is outside forest held well clear of any mound, any walkable
    pixel and any named rectangle -- foliage and nothing else.
    """
    w, h = ase.width, ase.height
    walk = ase.layer("walkable")
    solid = bytearray(w * h)
    for i in range(w * h):
        solid[i] = 1 if walk.pixels[i * 4 + 3] == 0 else 0

    outside = bytearray(w * h)
    queue = deque()

    def seed(i):
        if solid[i] and not outside[i]:
            outside[i] = 1
            queue.append(i)

    for x in range(w):
        seed(x)
        seed((h - 1) * w + x)
    for y in range(h):
        seed(y * w)
        seed(y * w + w - 1)
    while queue:
        i = queue.popleft()
        x, y = i % w, i // w
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h:
                j = ny * w + nx
                if solid[j] and not outside[j]:
                    outside[j] = 1
                    queue.append(j)

    mound = bytearray(w * h)
    for i in range(w * h):
        if solid[i] and not outside[i]:
            mound[i] = 1

    rects = parse_rects(open(RESOURCE).read())
    dist = [-1] * (w * h)
    queue = deque()

    def push(i):
        if dist[i] != 0:
            dist[i] = 0
            queue.append(i)

    for i in range(w * h):
        if mound[i] or not solid[i]:
            push(i)
    for name, l, t, rw, rh in rects:
        if name in ("houses", "resources"):
            continue
        for y in range(max(0, t - 2), min(h, t + rh + 2)):
            for x in range(max(0, l - 2), min(w, l + rw + 2)):
                push(y * w + x)
    while queue:
        i = queue.popleft()
        x, y = i % w, i // w
        d = dist[i]
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h:
                j = ny * w + nx
                if dist[j] < 0:
                    dist[j] = d + 1
                    queue.append(j)

    clean = bytearray(w * h)
    for i in range(w * h):
        clean[i] = 1 if (outside[i] and dist[i] >= 26) else 0
    return outside, mound, clean


def canopy_patches(ase, clean, limit=8):
    """Finds the largest rectangles that are nothing but canopy."""
    w, h = ase.width, ase.height
    heights = [0] * w
    found = []
    for y in range(h):
        for x in range(w):
            heights[x] = heights[x] + 1 if clean[y * w + x] else 0
        stack = []
        for x in range(w + 1):
            cur = heights[x] if x < w else 0
            start = x
            while stack and stack[-1][1] >= cur:
                sx, sh = stack.pop()
                if sh > 0:
                    found.append((sh * (x - sx), sx, y - sh + 1, x - sx, sh))
                start = sx
            stack.append((start, cur))
    found.sort(reverse=True)
    chosen = []
    for area, x, y, pw, ph in found:
        if pw < 40 or ph < 40:
            continue
        if any(not (x + pw <= px or px + qw <= x or
                    y + ph <= py or py + qh <= y)
               for px, py, qw, qh in chosen):
            continue
        chosen.append((x, y, pw, ph))
        if len(chosen) >= limit:
            break
    return chosen


def sample(src, sw, x, y, flip_x, flip_y, pw, ph, px, py):
    """Reads one patch pixel with optional mirroring."""
    sx = px + (pw - 1 - x if flip_x else x)
    sy = py + (ph - 1 - y if flip_y else y)
    o = (sy * sw + sx) * 4
    return src[o:o + 4]


def edge_noise(x, y):
    """A stable 0..255 hash, so a rebuild reproduces the same map."""
    h = (x * 73856093) ^ (y * 19349663) ^ 0x9E3779B9
    h ^= (h >> 13)
    h = (h * 1274126177) & 0xFFFFFFFF
    h ^= (h >> 16)
    return h & 0xFF


def stamp(dst, dw, dh, src, sw, patch, dx, dy, flip_x, flip_y, allow,
          feather=FEATHER):
    """Drops one mirrored canopy patch onto the canvas.

    Every written pixel is copied verbatim from the map's own artwork --
    never blended. Blending would invent colours that are not in the
    palette the map was drawn in, which reads as mush next to pixel art
    and, because it explodes the colour count, also makes the sprite far
    more expensive to ship. So the patch edge is dithered instead: near
    the border a pixel is either taken whole or left alone, on a stable
    hash, which gives a ragged foliage edge in the map's own colours.

    `allow` decides which destination pixels may be written, which is
    how the fill leans over the seam onto the village's own outer
    foliage without ever touching a path, a fence or a roof.
    """
    px, py, pw, ph = patch
    for y in range(ph):
        ty = dy + y
        if ty < 0 or ty >= dh:
            continue
        ey = min(y, ph - 1 - y)
        for x in range(pw):
            tx = dx + x
            if tx < 0 or tx >= dw:
                continue
            if allow is not None and not allow(tx, ty):
                continue
            ex = min(x, pw - 1 - x)
            edge = min(ex, ey)
            if feather > 0 and edge < feather:
                if edge_noise(tx, ty) >= 255 * edge // feather:
                    continue
            s = sample(src, sw, x, y, flip_x, flip_y, pw, ph, px, py)
            if s[3] == 0:
                continue
            o = (ty * dw + tx) * 4
            dst[o:o + 4] = s


def build():
    ase = read_aseprite(MAP)
    w, h = ase.width, ase.height
    if w == NEW_W and h == NEW_H:
        raise SystemExit("map.aseprite is already %dx%d" % (NEW_W, NEW_H))
    print("village %dx%d -> canvas %dx%d (%.4f)"
          % (w, h, NEW_W, NEW_H, NEW_W / NEW_H))

    off_x = (NEW_W - w) // 2
    off_y = (NEW_H - h) // 2
    print("village placed at (%d, %d)" % (off_x, off_y))

    outside, _mound, clean = forest_masks(ase)
    patches = canopy_patches(ase, clean)
    if not patches:
        raise SystemExit("no clean canopy patches found")
    print("canopy patches: %s" % (patches,))

    bottom = ase.layer("bottom")
    rng = random.Random(SEED)

    fill = bytearray(NEW_W * NEW_H * 4)

    def in_village(x, y):
        return off_x <= x < off_x + w and off_y <= y < off_y + h

    def village_forest(x, y):
        """True where the village canvas holds plain outside foliage."""
        return outside[(y - off_y) * w + (x - off_x)] == 1

    def allow(x, y):
        # The margin is free; inside the village footprint only its own
        # outside foliage may be overpainted, so the seam disappears
        # without a single drawn feature being touched.
        if not in_village(x, y):
            return True
        return village_forest(x, y)

    # A base coat first, so no pixel is ever left transparent: lay the
    # patches down in a grid, each cell a randomly chosen patch under a
    # random mirror, which already breaks up any single patch's outline.
    base = patches[0]
    bw, bh = base[2], base[3]
    for ty in range(-bh, NEW_H + bh, bh):
        for tx in range(-bw, NEW_W + bw, bw):
            patch = patches[rng.randrange(len(patches))]
            stamp(fill, NEW_W, NEW_H, bottom.pixels, w, patch, tx, ty,
                  rng.random() < 0.5, rng.random() < 0.5, allow)
            # A second, offset pass covers the gaps left where a chosen
            # patch is smaller than the cell.
            stamp(fill, NEW_W, NEW_H, bottom.pixels, w, base,
                  tx + bw // 2, ty + bh // 2,
                  rng.random() < 0.5, rng.random() < 0.5, allow)

    # Then bury the grid under stamps at random offsets, so no straight
    # run of patch edge survives long enough to read as a tile.
    margin_area = NEW_W * NEW_H - w * h
    stamps = margin_area // 500
    print("scattering %d canopy stamps" % stamps)
    for _ in range(stamps):
        patch = patches[rng.randrange(len(patches))]
        dx = rng.randrange(-patch[2] // 2, NEW_W)
        dy = rng.randrange(-patch[3] // 2, NEW_H)
        stamp(fill, NEW_W, NEW_H, bottom.pixels, w, patch, dx, dy,
              rng.random() < 0.5, rng.random() < 0.5, allow)

    # The two joins where fill meets village get their own dense pass,
    # straddling the seam so the change of source is not a visible line.
    # `allow` still protects every drawn feature; only the village's own
    # outer foliage is painted over.
    for seam_x in (off_x, off_x + w):
        for _ in range(NEW_H // 4):
            patch = patches[rng.randrange(len(patches))]
            dx = seam_x - patch[2] // 2 + rng.randrange(-24, 25)
            dy = rng.randrange(-patch[3] // 2, NEW_H)
            stamp(fill, NEW_W, NEW_H, bottom.pixels, w, patch, dx, dy,
                  rng.random() < 0.5, rng.random() < 0.5, allow)

    # Anything the stamps missed keeps the base coat; nothing may stay
    # transparent, or the client would draw black there.
    holes = sum(1 for i in range(3, len(fill), 4) if fill[i] == 0
                and not in_village((i // 4) % NEW_W, (i // 4) // NEW_W))
    if holes:
        raise SystemExit("fill left %d transparent pixels" % holes)

    layers = []
    for layer in ase.layers:
        buf = bytearray(NEW_W * NEW_H * 4)
        if layer.name.lower() == "bottom":
            buf[:] = fill
        for y in range(h):
            src = y * w * 4
            dst = ((y + off_y) * NEW_W + off_x) * 4
            row = layer.pixels[src:src + w * 4]
            if layer.name.lower() == "bottom":
                buf[dst:dst + w * 4] = row
            else:
                # Walkable and overhang keep their own alpha: the new
                # margin stays empty, so it is forest you cannot enter.
                for x in range(w):
                    o = x * 4
                    if row[o + 3] > 0:
                        buf[dst + o:dst + o + 4] = row[o:o + 4]
        layers.append(Layer(layer.name, buf, NEW_W, NEW_H, layer.flags,
                            layer.blend, layer.opacity))

    write_aseprite(MAP, Aseprite(NEW_W, NEW_H, layers))
    print("wrote %s (%d bytes)" % (MAP, os.path.getsize(MAP)))

    text = open(RESOURCE).read()
    open(RESOURCE, "w").write(shift_resource(text, off_x, off_y))
    print("shifted %s by (%d, %d)" % (RESOURCE, off_x, off_y))

    write_png("/tmp/new_map_bottom.png", NEW_W, NEW_H,
              layers[[l.name.lower() for l in layers].index("bottom")].pixels)
    print("preview: /tmp/new_map_bottom.png")


if __name__ == "__main__":
    build()
