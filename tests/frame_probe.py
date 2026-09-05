#!/usr/bin/env python3
"""Decodes the Heartleaf sprite protocol off a viewer websocket.

There are no screenshots in CI and no model API key, so this is how a
frame gets inspected: connect to a viewer route, split the byte stream
back into per-tick packets, and report what the client would draw.

  python3 tests/frame_probe.py --url ws://localhost:8091/global --seconds 20

Reports per frame: the declared viewport, the map-layer bottom object
(position and sprite size), every object id present, and the bytes that
frame cost. Black bars are a viewport wider or taller than the map crop
that fills it; a stuck camera is a viewport that never changes; a resent
card is a sprite definition arriving again mid-conversation.

Byte layout comes from bitworld's spriteprotocol.nim (little endian):
  0x01 sprite  u16 id, u16 w, u16 h, u32 nbytes, bytes, u16 nlabel, label
  0x02 object  u16 id, i16 x, i16 y, i16 z, u8 layer, u16 sprite
  0x03 delete  u16 id
  0x04 clear   -
  0x05 viewport u8 layer, u16 w, u16 h
  0x06 layer   u8 layer, u8 kind, u8 flags
"""

import argparse
import asyncio
import json
import struct
import sys
from collections import defaultdict

SPRITE, OBJECT, DELETE, CLEAR, VIEWPORT, LAYER = 1, 2, 3, 4, 5, 6

MAP_LAYER = 0
BOTTOM_OBJECT_ID = 1
OVERHANG_OBJECT_ID = 2
BACKDROP_OBJECT_ID = 3
DIRECTOR_CARD_OBJECT_BASE = 28000
DIRECTOR_CARD_FACE_OBJECT_BASE = 28100
DIRECTOR_CARD_SPRITE_BASE = 9100
DIRECTOR_CARD_FACE_SPRITE_BASE = 9150
PLAYER_OBJECT_BASE = 1000
INSET_BOTTOM_OBJECT_ID = 21300
REPLAY_SCRUBBER_OBJECT_ID = 20401
REPLAY_CONTROLS_OBJECT_ID = 20402
REPLAY_CENTER_BOTTOM_LAYER = 4


def parse_messages(buf):
    """Yields (kind, dict, nbytes) for every complete message in buf."""
    off = 0
    n = len(buf)
    while off < n:
        kind = buf[off]
        if kind == SPRITE:
            if off + 11 > n:
                break
            sid, w, h = struct.unpack_from("<HHH", buf, off + 1)
            (nbytes,) = struct.unpack_from("<I", buf, off + 7)
            lab_off = off + 11 + nbytes
            if lab_off + 2 > n:
                break
            (nlabel,) = struct.unpack_from("<H", buf, lab_off)
            end = lab_off + 2 + nlabel
            if end > n:
                break
            label = buf[lab_off + 2:end].decode("utf-8", "replace")
            yield SPRITE, {"id": sid, "w": w, "h": h, "label": label}, end - off
            off = end
        elif kind == OBJECT:
            if off + 12 > n:
                break
            oid, x, y, z = struct.unpack_from("<Hhhh", buf, off + 1)
            layer = buf[off + 9]
            (spr,) = struct.unpack_from("<H", buf, off + 10)
            yield OBJECT, {"id": oid, "x": x, "y": y, "z": z,
                           "layer": layer, "sprite": spr}, 12
            off += 12
        elif kind == DELETE:
            if off + 3 > n:
                break
            (oid,) = struct.unpack_from("<H", buf, off + 1)
            yield DELETE, {"id": oid}, 3
            off += 3
        elif kind == CLEAR:
            yield CLEAR, {}, 1
            off += 1
        elif kind == VIEWPORT:
            if off + 6 > n:
                break
            layer = buf[off + 1]
            w, h = struct.unpack_from("<HH", buf, off + 2)
            yield VIEWPORT, {"layer": layer, "w": w, "h": h}, 6
            off += 6
        elif kind == LAYER:
            if off + 4 > n:
                break
            yield LAYER, {"layer": buf[off + 1], "kind": buf[off + 2],
                          "flags": buf[off + 3]}, 4
            off += 4
        else:
            raise ValueError("unknown message kind %d at offset %d" % (kind, off))


class Frame:
    """One tick's worth of messages: everything between two clears."""

    def __init__(self):
        self.bytes = 0
        self.viewport = {}
        self.objects = {}
        self.sprites = []
        self.layers = []

    def add(self, kind, msg, size):
        self.bytes += size
        if kind == VIEWPORT:
            self.viewport[msg["layer"]] = (msg["w"], msg["h"])
        elif kind == OBJECT:
            self.objects[msg["id"]] = msg
        elif kind == SPRITE:
            self.sprites.append(msg)
        elif kind == LAYER:
            self.layers.append(msg)

    def sprite_size(self, sprite_id, known):
        return known.get(sprite_id)

    def summary(self, known):
        """The compact per-frame line: what the client would draw."""
        vp = self.viewport.get(MAP_LAYER)
        bottom = self.objects.get(BOTTOM_OBJECT_ID)
        bottom_sprite = known.get(bottom["sprite"]) if bottom else None
        cards = sorted(oid for oid in self.objects
                       if DIRECTOR_CARD_OBJECT_BASE <= oid
                       < DIRECTOR_CARD_OBJECT_BASE + 100)
        faces = sorted(oid for oid in self.objects
                       if DIRECTOR_CARD_FACE_OBJECT_BASE <= oid
                       < DIRECTOR_CARD_FACE_OBJECT_BASE + 100)
        card_sprites = [s for s in self.sprites
                        if DIRECTOR_CARD_SPRITE_BASE <= s["id"]
                        < DIRECTOR_CARD_SPRITE_BASE + 100]
        return {
            "bytes": self.bytes,
            "viewport": vp,
            "bottom_xy": (bottom["x"], bottom["y"]) if bottom else None,
            "bottom_sprite_wh": bottom_sprite,
            "backdrop": BACKDROP_OBJECT_ID in self.objects,
            "house_inset": INSET_BOTTOM_OBJECT_ID in self.objects,
            "scrubber": REPLAY_SCRUBBER_OBJECT_ID in self.objects,
            "transport": REPLAY_CONTROLS_OBJECT_ID in self.objects,
            "players": [
                # Object coordinates are viewport-relative and the map
                # bottom sits at -camera, so world = object - bottom.
                (o["x"] - bottom["x"], o["y"] - bottom["y"])
                for oid, o in sorted(self.objects.items())
                if bottom and PLAYER_OBJECT_BASE <= oid
                < PLAYER_OBJECT_BASE + 32
            ],
            "cards": len(cards),
            "faces": len(faces),
            "card_sprite_defs": len(card_sprites),
            "sprite_defs": len(self.sprites),
            "objects": len(self.objects),
        }


def black_bars(summary, win_num=16, win_den=9):
    """How the declared viewport letterboxes in a 16:9 window.

    The client fits the viewport into the window, so a viewport wider
    than the window bars the top and bottom, and a narrower one bars the
    sides. Returns (kind, viewport_aspect) or (None, aspect).
    """
    vp = summary["viewport"]
    if not vp:
        return None, None
    w, h = vp
    if h == 0:
        return "degenerate", None
    aspect = w / h
    target = win_num / win_den
    if abs(aspect - target) < 0.005:
        return None, aspect
    return ("top/bottom" if aspect > target else "left/right"), aspect


def chat_packet(text):
    """The 0x81 client text message the replay transport reads keys from.

    Transport commands ride in as chat text: '+'/'-' change speed, ' '
    toggles play, 'r' re-enables looping. Sending '+' is how this probe
    fast-forwards a replay to a part worth looking at, since the show
    pacing that runs at 1X would take minutes to get there.
    """
    raw = text.encode("utf-8")
    return bytes([0x81]) + struct.pack("<H", len(raw)) + raw


async def probe(url, seconds, quiet, dump, keys=""):
    import websockets

    frames = []
    known_sprites = {}
    current = None
    pending = b""
    first_packet_bytes = 0
    init_sprite_bytes = []
    async with websockets.connect(url, max_size=None) as ws:
        loop = asyncio.get_event_loop()
        if keys:
            await ws.send(chat_packet(keys))
        deadline = loop.time() + seconds
        while loop.time() < deadline:
            try:
                data = await asyncio.wait_for(
                    ws.recv(), timeout=max(0.1, deadline - loop.time()))
            except asyncio.TimeoutError:
                break
            if isinstance(data, str):
                continue
            pending += data
            consumed = 0
            try:
                for kind, msg, size in parse_messages(pending):
                    consumed += size
                    if kind == SPRITE:
                        known_sprites[msg["id"]] = (msg["w"], msg["h"])
                    if kind == CLEAR:
                        if current is not None:
                            frames.append(current)
                        current = Frame()
                        continue
                    if current is None:
                        # Everything before the first clear is the init
                        # packet: sprite definitions and layer setup.
                        first_packet_bytes += size
                        if kind == SPRITE:
                            init_sprite_bytes.append(
                                (size, msg["id"], msg["w"], msg["h"],
                                 msg["label"]))
                        continue
                    current.add(kind, msg, size)
            except ValueError as e:
                print("decode error: %s" % e, file=sys.stderr)
                break
            pending = pending[consumed:]
    if current is not None:
        frames.append(current)

    summaries = [f.summary(known_sprites) for f in frames]
    report = {
        "url": url,
        "init_packet_bytes": first_packet_bytes,
        "init_sprite_defs": len(known_sprites),
        "init_biggest_sprites": [
            {"bytes": b, "id": i, "w": w, "h": h, "label": l}
            for (b, i, w, h, l) in sorted(init_sprite_bytes, reverse=True)[:12]
        ],
        "frames": len(summaries),
    }
    if summaries:
        body = summaries[1:] or summaries
        byte_counts = sorted(s["bytes"] for s in body)
        report["bytes_per_frame"] = {
            "min": byte_counts[0],
            "median": byte_counts[len(byte_counts) // 2],
            "max": byte_counts[-1],
            "mean": round(sum(byte_counts) / len(byte_counts), 1),
            "total": sum(byte_counts),
        }
        viewports = [s["viewport"] for s in summaries if s["viewport"]]
        report["distinct_viewports"] = len(set(viewports))
        report["viewport_examples"] = [list(v) for v in
                                       sorted(set(viewports))[:8]]
        bars = defaultdict(int)
        for s in summaries:
            kind, _ = black_bars(s)
            bars[kind or "none"] += 1
        report["black_bars"] = dict(bars)
        report["frames_with_cards"] = sum(1 for s in summaries if s["cards"])
        report["frames_with_backdrop"] = sum(
            1 for s in summaries if s["backdrop"])
        report["frames_with_house_inset"] = sum(
            1 for s in summaries if s["house_inset"])
        report["frames_with_scrubber"] = sum(
            1 for s in summaries if s["scrubber"])
        report["frames_with_transport"] = sum(
            1 for s in summaries if s["transport"])
        report["card_sprite_redefinitions"] = sum(
            s["card_sprite_defs"] for s in summaries)
        card_frames = [s for s in summaries if s["cards"]]
        if card_frames:
            cb = sorted(s["bytes"] for s in card_frames)
            report["bytes_per_frame_during_cards"] = {
                "min": cb[0],
                "median": cb[len(cb) // 2],
                "max": cb[-1],
                "mean": round(sum(cb) / len(cb), 1),
                "frames": len(cb),
            }
    print(json.dumps(report, indent=2))
    if dump:
        with open(dump, "w") as fh:
            json.dump(summaries, fh, indent=1)
        print("per-frame detail written to %s" % dump, file=sys.stderr)
    if not quiet:
        for i, s in enumerate(summaries[:40]):
            kind, aspect = black_bars(s)
            print("frame %3d vp=%s bottom=%s cards=%d cardDefs=%d "
                  "sprites=%d bytes=%6d bars=%s aspect=%s"
                  % (i, s["viewport"], s["bottom_xy"], s["cards"],
                     s["card_sprite_defs"], s["sprite_defs"], s["bytes"],
                     kind or "none",
                     "%.3f" % aspect if aspect else "-"), file=sys.stderr)
    return report


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="ws://localhost:8091/global")
    ap.add_argument("--seconds", type=float, default=15.0)
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("--dump", default="")
    ap.add_argument("--keys", default="",
                    help="transport keys to send on connect, e.g. '++++'")
    args = ap.parse_args()
    asyncio.run(probe(args.url, args.seconds, args.quiet, args.dump,
                      args.keys))


if __name__ == "__main__":
    main()
