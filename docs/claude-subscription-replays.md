# Local Claude subscription playtests

The optional bridge runs gnomes through the installed Claude Code CLI and its
existing Claude.ai subscription login. It binds to localhost, disables Claude's
tools/customizations, and converts Heartleaf's model requests into print-mode
prompts. No Bedrock credentials are needed for this route.

The game still owns every action, observation, conversation, interview and replay.
This is a local development transport, not the production model backend.

## Start a game

First verify that `claude auth status` reports a Claude.ai subscription login.
Build/install the repository's locked Nim dependencies as usual. From the repository
root, start the bridge in one terminal:

```sh
python3 tools/claude_subscription_bridge.py \
  --model haiku --port 8099 --max-parallel 3 --timeout 300 \
  --trace out/claude-playtest/bridge-trace.jsonl
```

In a second terminal:

```sh
env -u HEARTLEAF_MOCK_REPLY \
  AWS_ENDPOINT_URL_BEDROCK_RUNTIME=http://127.0.0.1:8099 \
  BEDROCK_TIMEOUT_SECONDS=300 \
  HEARTLEAF_INTERVIEW_TIMEOUT_SECONDS=300 \
  HEARTLEAF_CONVERSATION_TICK_SECONDS=120 \
  HEARTLEAF_PLAN_TURN_MINUTES=180 \
  HEARTLEAF_CONVERSATION_GAP_MINUTES=60 \
  nim r tools/play.nim --days:2 --seed:20260912 --port:8084 \
    --no-browser --log-dir:out/claude-playtest
```

The game seats the nine normal example souls, then writes `game.log`, per-gnome
logs and `heartleaf.bitreplay` under the log directory. The bridge records model
results, provider/model IDs, call durations and failures separately. Stop the bridge
with Ctrl-C after the game finishes. The map seed is repeatable; model replies are
not deterministic.

To watch a completed recording without calling a model:

```sh
out/heartleaf --load-replay:out/claude-playtest/heartleaf.bitreplay --port:8084
```

Open `http://localhost:8084/` on that machine. The same replay can be copied to
another machine running the PR's viewer.

## Timing and interpretation

These are deliberately slower decision settings for the local CLI transport:
planning every three game hours and conversation slots every game hour. The normal
game defaults are hourly planning and four game minutes between conversation slots.
Conversation slots remain enabled: gnomes already talking skip ordinary planning
calls, so disabling conversation slots would prevent normal replies.

Our first attempt used short waits. Every first-night interview missed the 45-second
deadline and the neutral fallback kept every pair at 0.5. CLI request time can be
much longer than model generation time, and old requests can still occupy the
request budget after the game stops waiting for them. The profile above gives local
conversation turns up to 120 seconds and bedtime interviews up to 300 seconds,
with at most three CLI calls running concurrently. The ordinary interview default
stays 45 seconds; its override is bounded to 5–300 seconds.

The CLI does not expose an equivalent to the Bedrock output-token cap. The bridge
records the requested cap and `max_tokens_enforced: false`; it does not pretend to
enforce it. Transcripts are passed as labelled messages in a print-mode prompt.
These differences, sparse decision timing and a small sample limit what this
playtest establishes about normal league behavior.

Tests for the bridge use mocked subprocess results and do not spend subscription
usage: `python3 tests/claude_subscription_bridge_test.py`.

The recorded two-day evaluation, its failure cases and behavioral observations are
[available here](connections/claude-observations.md). Reproduce its offline viewer
frames with `nim r tools/render_connection_replay.nim docs/connections/claude/two-day.bitreplay out/claude-review`.
