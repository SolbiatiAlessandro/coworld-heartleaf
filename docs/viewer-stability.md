# Viewer stability candidate

This change preserves the hand-drawn village, walk masks, house locations,
resources, replay format, and game rules.

- Light parchment (`#d5b072`) fills the surround. The map uses the existing
  pixel-art wooden and leafy border. A fixed frame masks overflow during zoom.
- The settled director shot shows the current speaker's card: one portrait,
  name, full recorded line, points, connection points, and relation to the listener.
  It sits beside the map in landscape, below it in portrait, clear of the
  leaderboard and transport. Wide shots and camera travel have no dialogue card.
- This restores the card contents from [director PR #35](https://github.com/Metta-AI/coworld-heartleaf/pull/35).
  The old two-portrait bottom banner is absent in director mode. Empty card
  frame, portrait, rule and letter sprites are reused; changing a line does not
  resend the whole card.
- A host plus one guest qualifies for a room shot. Eligible rooms rotate, with
  their own camera coordinates and a transparent circular exterior.
- The three emotion tiers use pixel faces anchored above names. Their placement
  clears nearby gnomes too. Whole pixel blocks dissolve during the fade:
  partial alpha in the pinned client's map layer could erase the map underneath.
- Live viewers report their actual size, including after reconnect. Saved
  replays retain pause, seek and speed controls; live had no pause/rewind before
  the earlier PRs.
- Native and static replays share queue, camera and dialogue stepping at 24 Hz.
  The static build uses the director and unsigned 32-bit visual noise arithmetic.

## Two surrounds

Open `/client/global` for parchment, or append `?background=forest` for the forest
comparison. Static URLs accept the same parameter alongside `replay`.

The optional forest has no extra houses and uses the map's day/night tint.
Its generated joins still need art review. Parchment is the proposed default.

`data/forest.png` and `data/forest-frame.png` were generated on September 8 using
OpenAI ImageGen with the existing `data/backdrop.png` and `docs/heartleafMap.png`
as references. Original village and home source art is unchanged. Forest
textures load only when selected.

## Validation

Baseline: master `ad3c138`, dependencies from `nimby.lock`.
Native Nim 2.2.10; static Nim 2.2.4 and Emscripten 4.0.15.

```sh
nim c src/heartleaf.nim
nim r tests/tests.nim
nim r tests/viewer_stability.nim
nim r tests/routes.nim
HEARTLEAF_SERVER=out/heartleaf nim r tests/integration.nim
nim c -d:emscripten wasm/replay_viewer.nim
nim r tools/render_viewer_review.nim out/viewer-review
```

Regressions cover party eligibility, room transparency through night tints,
unchanged gameplay hashes, portrait/landscape layout, one portrait with score
and connections, card-component reuse across changed text, absence of the old
banner, no card in wide shots or camera travel, every emoji animation phase
clearing both gnome bodies, opaque/dissolved icon pixels, and conversation
playback with pause/seek.

The archived two-day recording
[116ed90d-3374-4bc7-8152-0e79dfe8eee0](https://softmax-public.s3.amazonaws.com/replays/116ed90d-3374-4bc7-8152-0e79dfe8eee0.replay)
and a synthetic conversation fixture reached tick 9120 with matching hashes.
Before this visual refinement, the static fixture also completed in Chrome
without captured browser errors. CI includes the native tests and static bundle.

## Current visual evidence

These are **offline renders of actual sprite-protocol packets**, using a small
review tool that mirrors the pinned client's layer composition. They use a
controlled two-gnome scene. They are not browser screenshots. The Mac was locked
during this refinement, so a fresh browser/GPU check remains pending.

The reviewed frames cover wide view, outdoor zoom in progress and settled,
portrait view, and circular rooms at zoom start, settled, and night. No black
bars or opaque exterior room rectangle appeared in those renders. Intended
night shading inside the room is preserved.

![Zoomed director card and pixel emojis](viewer-stability/rendered-director-card.png)

![Circular room in portrait](viewer-stability/rendered-room-portrait.png)

![Circular room at night](viewer-stability/rendered-room-night.png)

## Review limits

Andre's original freeze recording is unavailable; completing other fixtures
does not diagnose or close that failure. Forest joins require art review.
Fresh browser/GPU validation and hosted testing remain pending. No merge or
deployment has been performed.
