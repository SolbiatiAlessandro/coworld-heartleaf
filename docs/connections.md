# Connections

This feature branch builds on viewer stability PR #50. Merge #50 first, then
rebase this branch onto master; the feature commits are separate from that work.

## What ships

- Each pair of seated gnomes has one shared bond in **[0, 1]**, initially **0.5**.
  Bonds persist across days in an episode and reset for a new game.
- At **9pm**, after the day's dinner outcomes have entered each gnome's memory,
  the score screen waits for one bedtime interview per gnome. The model ranks
  every other seated gnome and gives short reasons grounded in that day's events.
- The left leaderboard keeps the Heartleaf title and adds separate **game-point**
  and **connection** bars. The latter sums current bonds: initially 4, maximum 8
  with nine gnomes. Game points scale to the current leader; connections use the
  fixed number of partners. The existing game reward/winner rules are unchanged.
- Conversation cards retain their existing portrait, type size and layout. Their
  relationship strip shows the listener's name and **three pixel hearts**, with
  partial fill: a 0.5 bond is one full heart, one half heart, one empty heart.
- `send_emoji` is a deliberate model action targeting a nearby visible gnome:
  `happy`, `very_happy`, `sad`, or `very_sad`. Small pixel faces clear the gnome's
  portrait/body and disappear after their recorded animation. The recipient
  notices the reaction in its memory. Proximity and spoken-turn count no longer
  emit reactions or change the new bond score.
- Select a leaderboard gnome to inspect its graph of shared bonds, last recorded
  action and latest bedtime ranking/reasons. Longer interviews have reflection
  pages. Select the same gnome again to close. The inspector hides during the
  director's conversation shots, which still fill the window.
- Pair snapshots, interviews, actions and reactions travel inside the replay.
  Both native and static viewers derive them from the playhead, including backward
  seeks and concurrent-conversation rewinds. Old replays remain playable and show
  unavailable relationship data, rather than fabricated interviews.

## Daily arithmetic and edge cases

For a gnome ranking `m` other gnomes, rank 1 is most connected:

```text
contribution(rank, m) = 0.5 - (rank - 1) / (m - 1)
delta(A,B) = (A's contribution to B + B's contribution to A) / 2
new_bond(A,B) = clamp(old_bond(A,B) + delta(A,B), 0, 1)
```

Both first: +0.5. Both last: -0.5. First versus last: zero. Intermediate ranks
are evenly spaced. This is a relative ranking system: a low rank can decrease a
bond even without a deliberately harmful action. Clamping can change the village's
total connection score. There is no separate bonus for promises, dinners, or emoji;
models use those experiences as evidence in their rankings.

Rankings must contain every other seated gnome exactly once, with a nonempty reason
of at most 240 characters each. Ties are not part of this version. Unknown partners
must be ranked honestly as little/no interaction. With zero or one possible partner,
ordinal position provides no contrast, so the contribution is zero.

All changes commit together once per day. Missing, invalid, failed or timed-out
interviews contribute zero, without inventing a ranking. The other gnome's valid
contribution still supplies its half of the update. There is a **45-second overall
deadline**; requests receive a 1,200-token output budget. Stale responses, including
responses from a prior game, cannot be applied to a new request. Gnomes receive their
old/new pair strengths and the partner's recorded reason for discussion tomorrow.

## Review and validation

The committed fixture is an **authored two-day scenario with scripted model replies**,
not a paid/autonomous model run. It uses normal movement and the actual brain
interview/action handlers. It has nine gnomes, six conversations, eighteen valid
bedtime interviews, two daily commits and twelve deliberate reactions. All 9,120
simulation ticks replay with matching hashes; the full director playback is checked
for stalls. These hashes cover the simulation; recorded connection metadata is
validated and separately tested for correct playhead folding.

```sh
nim r tests/connections.nim
nim r tools/record_connection_scenario.nim out/connections-scenario.replay
nim r tests/connections_viewer.nim out/connections-scenario.replay out/connections-review
nim c -d:release src/heartleaf.nim
out/heartleaf --load-replay:docs/connections/two-day.replay --port:8084
# Open http://localhost:8084/
```

Also checked: core tests, native integration, viewer stability, navigation, ordered
control clicks, eight playback speeds and 64 pause/speed combinations, routes, and
the static WASM build. New viewer checks exercise selection, reflection pages,
pause, next/previous, speeds, end/restart, and forward/backward seeks across days.

The images below are **offline renders of actual replay sprite-protocol frames**.
The Mac was locked, so OS/browser click-through was unavailable. Real model ranking
quality, request latency and remote deployment have not been validated by this fixture.

![Day two leaderboard](connections/06-day-two-overview.png)
![Conversation with half-filled hearts and intentional reactions](connections/03-conversation.png)
![Selected gnome graph and bedtime reflections](connections/07-bedtime-results.png)

## Out of scope

Production deployment or merge; tournament reward changes; automatic promise
tracking or event-based point bonuses; ties/absolute ratings; relationship decay;
persistence across separate episodes; the removed right-side conversation list;
and automatic live-model quality evaluation. The existing replay controls, camera
timing, map geometry, font sizes, brick background and dialogue layout are preserved.
