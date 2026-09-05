# Director front door: a landscape map, cards as parts, pixel emotes

Answers Andre's review. **PR #41 was merged into `Metta-AI/master` before
this work started** (`ad3c138`, "Merge pull request #41 from
SolbiatiAlessandro/director-front-door"), so none of this could be added
to #41 — a merged PR cannot track new work. This is a follow-up branch
off master with the same scope.

## Andre's eight comments

| Comment | What it got |
| --- | --- |
| "I can't see the chat" | Reproduced by decoding frames off each socket. Cards were in fact reaching every route already; what made the chat unreadable was the camera being stuck on one shot and the shot being letterboxed. Both fixed, and `tests/director_frames.nim` now asserts cards are present on `/global`, `/replay` and `/clients/global`. |
| "I don't have the scrubber so I can't play/pause it" | The transport is served to every viewer route in replay server mode. Verified and pinned in `tests/routes.nim` for `/global`, `/replay`, `/clients/global` and `/director`. |
| "I have the ugly forest, the extra house and black bars still" | `data/backdrop.png` and all backdrop code deleted. `grep -inE 'forest|backdrop|veil' src/` returns nothing. Black bars gone (below). |
| "I am not a fan of the emoji icons. They are smooth and don't fit the style" | Pixel faces ported from `connection-score`: `data/emote_tier{0,1,2}.png`, 20x20 and 24x24 hard-edged art. Live in 2294 of 2395 frames across all three tiers. |
| "you are resending cards as is, you should resend them as parts. press F2" | Cards are now assembled from init-packet parts. No sprite is defined while a card is on screen. Numbers below. |
| "The houses chat and night is broken with the forest background" | The forest background is gone. The house interior was placed at a fixed offset that assumed the padded viewport; it is now centered on the viewport the frame declares. All five dusk tints verified on the map bottom **and** the overhang. |
| "replay got stuck here: there is a green sliver and no action" | Root-caused and fixed. The camera held one shot for 5595 consecutive frames. |
| "I get black bars on top and bottom, even though we have the graphics for that" | The map is 16:9 and the viewport is the crop. 0 black-bar frames out of 5747, and 0 out of 6793 on a second replay. |

## Features in

**A 16:9 map, no backdrop, no black anywhere.** `data/map.aseprite` is
1680x945 instead of 748x941. The village artwork is copied into the
middle of the canvas unchanged — every house, garden, plaza, well, path,
fence and flower in the same place relative to every other — and the new
margins are filled with the map's own tree canopy, sampled from patches
of its existing forest. Patch edges are hard, never blended: the map is
drawn in a strict 16-colour palette and the new bottom layer still has
exactly those 16 colours and no others. The walkable and overhang layers
are copied with the same offset and the margin left non-walkable, so
their opaque pixel counts are unchanged (238648 and 28986) and every
path, spawn, garden and door keeps the connectivity it had.
`data/map.resource` shifts by (466, 2). Rebuilt by
`tools/make_landscape_map.py` on top of `tools/asefile.py`, which reads
and writes the aseprite subset bitworld parses; `docs/heartleafMap.png`
re-rendered.

The director declares the crop itself as the viewport, keeps the map's
aspect, and clamps the crop inside the map, so a 16:9 window fits it
edge to edge and no frame can show anything that is not map. Cards moved
inside the crop's own margins.

**Dialogue cards as parts.** The parchment background is a fixed-size
init-packet sprite per body-line count with the footer rule drawn in;
portraits are init-packet sprites; all text is glyph objects over the
Tiny5 glyph sprites, in three inks (the chat banner's for body and
stats, plus name-ink and relation-ink sets).

**Pixel emotes and the Connection rule.** Commits `4a596d0`, `f2a405a`,
`037fdb9`, `f7803a5` cherry-picked from `connection-score` with one
small conflict in `conversationSpans`. Their tests came along and pass.
No emoji rasterising remains — `loadEmoteSprite` now only reads the
pixel-face PNGs.

**Replay and director fixes.** A conversation with no exit record used
to die at the end of the recording; recordings often have no exit rows
at all, so every conversation overlapped and the director committed to
the first and could never be released. Such a conversation now dies a
short tail after its last spoken turn. That alone was not enough — all
three of luna's conversations really do run the whole day — so a
commitment that has held the camera for the dwell now rotates to another
conversation live at the same tick, with no rewind. A dinner outranks a
conversation, because the house interior only draws from the wide shot.

## Features out

Audio/voices/music (#38) and encoded sprites (#46) untouched.
`nimby.lock` and `bitworld` untouched. CI workflows unchanged. No
GitHub comments posted, no other PRs opened.

## Numbers

Measured on `tests/fixtures/luna_9gnomes.bitreplay` over a 240s window
with `tests/frame_probe.py`, which decodes the sprite protocol off a
viewer socket.

| | before | after |
| --- | --- | --- |
| black-bar frames | 396 of 524 | 0 of 5747 |
| distinct camera positions | 1 | 345 |
| longest constant shot | 5595 frames | 315 frames (the dwell) |
| card sprite definitions | 87 frames, 3377073 bytes, 30.6% of the stream | 0 |
| biggest frame with cards | 70650 bytes | 10746 bytes |
| median frame | 1298 bytes | 4166 bytes |
| mean frame | 1919 bytes | 3771 bytes |
| init packet | 6763681 bytes | 11690081 bytes |

On the recorded mock game (2 days, 9 gnomes, no conversations at all):
0 black-bar frames of 6793; all five dusk tints appear on the bottom
(sprite ids 10..14) and the overhang (15..19); with no conversation the
shot is the whole map, 1680x945, not a sliver; bytes/frame min 1300,
median 1660, max 2630.

### Two costs worth naming

**The init packet grew 73%, and takes about 7s to reach a cold viewer.**
That is not compression: a 16:9 map of this height has 2.26x the pixels
and ships at six day tints, and the per-pixel cost is unchanged. The
cheap fix, if the download matters, is to ship the forest margin as one
tiled sprite per tint instead of baking it into the full-map sprite:
roughly 3.3MB back, at the cost of splitting the map draw across three
views. Not done here — it is not one of the eight comments and it adds
risk I could not check visually.

**The steady byte rate roughly doubles while the spikes go away.** The
protocol clears and re-sends every object every frame, so a card's ~130
inked characters cost 12 bytes each on every frame, where the old
composed card cost 40KB once per spoken line. At 24fps that is about
0.7 Mbit/s against 0.37 Mbit/s. The spikes are gone and no card is ever
re-sent, which is what F2 was showing. If the steady rate matters more,
the cheaper shape is one sprite per wrapped text line rather than per
glyph: ~900 bytes/frame, at the cost of a small sprite definition when a
line changes.

## Test plan

```sh
# toolchain (what .github/workflows/build.yml does)
sudo apt-get update && sudo apt-get install -y libudev-dev libevdev-dev
# nimby 0.2.x + nim 2.2.10, workspace in the PARENT of the checkout
cd .. && nimby create && nimby sync coworld-heartleaf/nimby.lock && cd -

nim check src/heartleaf.nim
nim c -o:out/heartleaf src/heartleaf.nim
nim r tests/tests.nim          # includes the staged dinner-cut shot
nim r tests/routes.nim         # every route: director page, transport, 16:9
nim r tests/integration.nim

# frame-level checks need a recorded replay, which the repo does not carry
git fetch origin test-fixtures
git checkout origin/test-fixtures -- tests/fixtures/
nim r tests/director_frames.nim

# look at a stream by hand
out/heartleaf --port:8091 --load-replay:tests/fixtures/luna_9gnomes.bitreplay &
python3 -m pip install websockets
python3 tests/frame_probe.py --url ws://localhost:8091/global --seconds 60
python3 tests/frame_probe.py --url ws://localhost:8091/replay --seconds 60 --keys '++++'

# rebuild the map from the old one (idempotent; refuses if already 16:9)
python3 tools/make_landscape_map.py && nim r tools/gen_banner.nim
```

`tests/director_frames.nim` prints, per route, the rendered frame count,
distinct crops, frames with cards, and the map size; it exits cleanly
with a message when no fixture is present, so CI stays green.

## Known caveats

- **Replays recorded before this map will warn about a hash mismatch.**
  Moving the village inside a bigger canvas moves every absolute
  coordinate, and the replay hash covers those. Playback itself is
  correct — gnomes land inside the village, x 514..1147 of the 466..1214
  village band — and new recordings hash clean. There is no way to widen
  the map and keep old hashes.
- **The dinner cut is unit-tested, not verified on a recording.** No
  replay available here contains one: the luna fixture stops at 3:45pm,
  before the 4pm table, and a mock game has every gnome eat at home. The
  test in `tests/tests.nim` seats four gnomes in one house and checks the
  built director packet carries the house interior, centered in the shot.
- **The luna fixture is a partial day**: 9:00am to 3:45pm, three
  conversations that all run the whole recording, no dinner and no dusk
  — so dusk and the party had to be checked on the mock recording and in
  a unit test instead.
- **The map was widened, not re-arranged.** Spreading the nine houses
  horizontally was assessed against the walkable layer and rejected: the
  walk mask is a hand-drawn web of paths that *is* the connective tissue
  between the house mounds, so moving a house means drawing ~900px of new
  path — generating art, which the brief rules out — and risking spawn,
  garden and door reachability. The margins are filled with the map's own
  canopy instead, which is the documented fallback.
