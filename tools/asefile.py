#!/usr/bin/env python3
"""Reads and writes the subset of the Aseprite format this repo uses.

bitworld's aseprite.nim is the reader that has to accept whatever we
write, so this stays inside what it parses: RGBA colour depth, one
frame, normal layers, and zlib-compressed cels. Nothing here needs
Aseprite itself to be installed, which is the point -- the map is
regenerated headlessly.

Also carries a tiny PNG codec (RGBA8, non-interlaced) because the
sandbox has no PIL and the map layers have to be eyeballed as images.
"""

import struct
import zlib

HEADER_MAGIC = 0xA5E0
FRAME_MAGIC = 0xF1FA
CHUNK_LAYER = 0x2004
CHUNK_CEL = 0x2005
HEADER_BYTES = 128
FRAME_HEADER_BYTES = 16


class Layer:
    def __init__(self, name, pixels, width, height, flags=1, blend=0,
                 opacity=255):
        self.name = name
        self.pixels = pixels  # bytearray, RGBA8, width*height*4
        self.width = width
        self.height = height
        self.flags = flags
        self.blend = blend
        self.opacity = opacity

    def at(self, x, y):
        o = (y * self.width + x) * 4
        return tuple(self.pixels[o:o + 4])

    def put(self, x, y, rgba):
        o = (y * self.width + x) * 4
        self.pixels[o:o + 4] = bytes(rgba)


class Aseprite:
    def __init__(self, width, height, layers):
        self.width = width
        self.height = height
        self.layers = layers

    def layer(self, name):
        for l in self.layers:
            if l.name.lower() == name.lower():
                return l
        raise KeyError(name)


def read_aseprite(path):
    """Parses one RGBA aseprite file into flattened per-layer images."""
    data = open(path, "rb").read()
    pos = 0
    _size, magic, frames, width, height, depth = struct.unpack_from(
        "<IHHHHH", data, pos)
    if magic != HEADER_MAGIC:
        raise ValueError("not an aseprite file: %s" % path)
    if depth != 32:
        raise ValueError("only RGBA aseprite files are supported, got %d"
                         % depth)
    pos = HEADER_BYTES

    layer_meta = []
    cels = []
    for _frame in range(frames):
        f_start = pos
        f_bytes, f_magic, old_chunks, _duration = struct.unpack_from(
            "<IHHH", data, pos)
        if f_magic != FRAME_MAGIC:
            raise ValueError("bad frame magic")
        new_chunks = struct.unpack_from("<I", data, pos + 12)[0]
        n_chunks = new_chunks if new_chunks != 0 else old_chunks
        pos += FRAME_HEADER_BYTES
        for _c in range(n_chunks):
            c_start = pos
            c_size, c_type = struct.unpack_from("<IH", data, pos)
            c_end = c_start + c_size
            p = pos + 6
            if c_type == CHUNK_LAYER:
                flags, kind, _child, _dw, _dh, blend = struct.unpack_from(
                    "<HHHHHH", data, p)
                p += 12
                opacity = data[p]
                p += 4
                nlen = struct.unpack_from("<H", data, p)[0]
                p += 2
                name = data[p:p + nlen].decode("utf-8")
                layer_meta.append((name, flags, blend, opacity, kind))
            elif c_type == CHUNK_CEL:
                (layer_index,) = struct.unpack_from("<H", data, p)
                x, y = struct.unpack_from("<hh", data, p + 2)
                opacity = data[p + 6]
                (cel_kind,) = struct.unpack_from("<H", data, p + 7)
                p += 9 + 2 + 5  # cel type, z-index, 5 reserved
                if cel_kind in (0, 2):
                    cw, ch = struct.unpack_from("<HH", data, p)
                    p += 4
                    if cel_kind == 0:
                        raw = data[p:p + cw * ch * 4]
                    else:
                        raw = zlib.decompress(data[p:c_end])
                    cels.append((layer_index, x, y, cw, ch, bytearray(raw)))
            pos = c_end
        pos = f_start + f_bytes

    layers = []
    for index, (name, flags, blend, opacity, _kind) in enumerate(layer_meta):
        buf = bytearray(width * height * 4)
        for (li, cx, cy, cw, ch, raw) in cels:
            if li != index:
                continue
            for yy in range(ch):
                dy = cy + yy
                if dy < 0 or dy >= height:
                    continue
                src = yy * cw * 4
                for xx in range(cw):
                    dx = cx + xx
                    if dx < 0 or dx >= width:
                        continue
                    o = src + xx * 4
                    if raw[o + 3] > 0:
                        d = (dy * width + dx) * 4
                        buf[d:d + 4] = raw[o:o + 4]
        layers.append(Layer(name, buf, width, height, flags, blend, opacity))
    return Aseprite(width, height, layers)


def _chunk(chunk_type, payload):
    return struct.pack("<IH", 6 + len(payload), chunk_type) + payload


def write_aseprite(path, ase):
    """Writes an RGBA, one-frame aseprite with zlib-compressed cels."""
    chunks = []
    for layer in ase.layers:
        name = layer.name.encode("utf-8")
        payload = struct.pack(
            "<HHHHHH", layer.flags, 0, 0, 0, 0, layer.blend)
        payload += bytes([layer.opacity]) + b"\0\0\0"
        payload += struct.pack("<H", len(name)) + name
        chunks.append(_chunk(CHUNK_LAYER, payload))
    for index, layer in enumerate(ase.layers):
        payload = struct.pack("<Hhh", index, 0, 0)
        payload += bytes([255])
        payload += struct.pack("<H", 2)      # compressed image cel
        payload += struct.pack("<h", 0)      # z-index
        payload += b"\0" * 5
        payload += struct.pack("<HH", ase.width, ase.height)
        payload += zlib.compress(bytes(layer.pixels), 9)
        chunks.append(_chunk(CHUNK_CEL, payload))

    body = b"".join(chunks)
    frame = struct.pack(
        "<IHHHHI", FRAME_HEADER_BYTES + len(body), FRAME_MAGIC,
        len(chunks) if len(chunks) < 0x10000 else 0, 100, 0, len(chunks))
    frame += body

    header = bytearray(HEADER_BYTES)
    struct.pack_into("<I", header, 0, HEADER_BYTES + len(frame))
    struct.pack_into("<HHHHH", header, 4, HEADER_MAGIC, 1,
                     ase.width, ase.height, 32)
    struct.pack_into("<I", header, 14, 0)       # flags
    struct.pack_into("<H", header, 18, 100)     # speed
    header[28] = 0                              # transparent index
    struct.pack_into("<H", header, 32, 0)       # colour count
    header[34] = 1                              # pixel width
    header[35] = 1                              # pixel height
    with open(path, "wb") as fh:
        fh.write(bytes(header) + frame)


def write_png(path, width, height, pixels):
    """Writes an RGBA8 non-interlaced PNG."""
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)
        raw += pixels[y * stride:(y + 1) * stride]
    def chunk(tag, payload):
        data = tag + payload
        return (struct.pack(">I", len(payload)) + data +
                struct.pack(">I", zlib.crc32(data) & 0xffffffff))
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    open(path, "wb").write(png)


def read_png(path):
    """Reads an RGBA8 or RGB8 non-interlaced PNG into (w, h, bytearray)."""
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a png: %s" % path)
    pos = 8
    idat = b""
    width = height = depth = color = 0
    while pos < len(data):
        (length,) = struct.unpack_from(">I", data, pos)
        tag = data[pos + 4:pos + 8]
        payload = data[pos + 8:pos + 8 + length]
        if tag == b"IHDR":
            width, height, depth, color = struct.unpack_from(
                ">IIBB", payload, 0)
        elif tag == b"IDAT":
            idat += payload
        elif tag == b"IEND":
            break
        pos += 12 + length
    if depth != 8 or color not in (2, 6):
        raise ValueError("only 8-bit RGB/RGBA PNGs are supported")
    channels = 4 if color == 6 else 3
    raw = zlib.decompress(idat)
    stride = width * channels
    out = bytearray(width * height * 4)
    prev = bytearray(stride)
    pos = 0
    for y in range(height):
        filt = raw[pos]
        pos += 1
        line = bytearray(raw[pos:pos + stride])
        pos += stride
        if filt == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xff
        elif filt == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xff
        elif filt == 3:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xff
        elif filt == 4:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                b = prev[i]
                c = prev[i - channels] if i >= channels else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xff
        for x in range(width):
            o = (y * width + x) * 4
            s = x * channels
            out[o] = line[s]
            out[o + 1] = line[s + 1]
            out[o + 2] = line[s + 2]
            out[o + 3] = line[s + 3] if channels == 4 else 255
        prev = line
    return width, height, out
