## Route-level checks of the viewer front door against a real replay
## server: the routes the Softmax platform opens (`/client/global` for
## live spectating, `/client/replay` for hosted replays) and the local
## root all serve the director page, and every viewer websocket streams
## the director cut. There is one view; the `/plain` opt-in is gone.
##
## Runs the server binary named by HEARTLEAF_SERVER (default out/heartleaf,
## built with `nim c src/heartleaf.nim`) from the repository root.

import
  std/[httpclient, json, os, osproc, strutils, times],
  bitworld/spriteprotocol,
  whisky,
  heartleaf,
  replays

const
  Port = 18962
  Origin = "http://localhost:" & $Port
  WsOrigin = "ws://localhost:" & $Port
  DirectorMarker = "<!-- director -->"
  StockPageMarker = "function websocketPathForClientPage"
  DirectorPages = [
    "/", "/director", "/global",
    "/client/global", "/clients/global",
    "/client/replay", "/clients/replay", "/replay"
  ]
  RemovedPlainPages = ["/plain", "/client/plain"]
  DirectorSockets = ["/global", "/replay", "/clients/global", "/director"]
  FixtureSeed = 4242
  FixtureTicks = 120
  WatchSeconds = 30.0
    ## Long enough for the init packet -- the whole map at every day
    ## tint, tens of megabytes -- to land before the first rendered
    ## frame is counted.
  MapAspectNum = 16.0
  MapAspectDen = 9.0
  AspectTolerance = 0.01

proc serverExe(): string =
  let configured = getEnv("HEARTLEAF_SERVER")
  if configured.len > 0:
    return configured
  "out" / "heartleaf"

proc writeFixtureReplay(path: string) =
  ## Records a short two-gnome game so the server has a replay to serve.
  var
    sim = initSimServer(FixtureSeed)
    writer = openReplayWriter(path, $(%*{"seed": FixtureSeed}))
  doAssert sim.addPlayer("alice", -1) == 0
  writer.writeJoin(tickTime(0), 0, "alice", -1, "")
  writer.lastMasks.add(0)
  doAssert sim.addPlayer("bob", 3) == 1
  writer.writeJoin(tickTime(0), 1, "bob", 3, "")
  writer.lastMasks.add(0)
  for tick in 0 ..< FixtureTicks:
    let masks = [
      if tick < 60: ButtonRight else: ButtonUp,
      if tick mod 30 < 15: ButtonLeft else: ButtonDown
    ]
    for playerIndex in 0 ..< 2:
      writer.writeInputMaskChange(
        tickTime(sim.tickCount), playerIndex, masks[playerIndex]
      )
    sim.step(@[decodeInputMask(masks[0]), decodeInputMask(masks[1])])
    writer.writeHash(uint32(sim.tickCount), sim.gameHash())
  writer.closeReplayWriter()

proc waitForHealth() =
  ## Polls /healthz until the server answers; asset loading takes a while.
  let client = newHttpClient(timeout = 1000)
  defer: client.close()
  for _ in 0 ..< 300:
    try:
      if client.getContent(Origin & "/healthz") == "healthy":
        return
    except CatchableError:
      discard
    sleep(100)
  raise newException(CatchableError, "server never became healthy")

proc fetch(path: string): tuple[status: int, body: string] =
  let client = newHttpClient(timeout = 5000)
  defer: client.close()
  let response = client.get(Origin & path)
  (response.code.int, response.body)

proc hasScorePanelCard(frame: string): bool =
  ## True when one binary frame places the parchment score-panel card,
  ## which every rendered viewer frame carries. It replaces the forest
  ## underlay object this test used to pin director frames on: the
  ## forest is gone, and with the plain view gone too every viewer
  ## socket is a director watcher, so the card is the stable
  ## always-present object of a viewer frame.
  if frame.len == 0:
    return false
  for message in parseSpritePacket(frame.toOpenArrayByte(0, frame.high)):
    if message.kind == spkObject and
        message.objectDef.id == GlobalPanelCardObjectId and
        message.objectDef.spriteId == GlobalPanelCardSpriteId:
      return true
  false

proc hasReplayTransport(frame: string): bool =
  ## True when one binary frame places the replay transport row and the
  ## scrubber. In replay server mode every viewer route is a replay
  ## viewer, so every one of them gets the transport: a watcher on
  ## /global or /client/global can scrub and pause exactly like one on
  ## /replay.
  if frame.len == 0:
    return false
  var sawScrubber, sawControls = false
  for message in parseSpritePacket(frame.toOpenArrayByte(0, frame.high)):
    if message.kind != spkObject:
      continue
    if message.objectDef.id == ReplayScrubberObjectId:
      sawScrubber = true
    if message.objectDef.id == ReplayControlsObjectId:
      sawControls = true
  sawScrubber and sawControls

proc mapViewport(frame: string): tuple[found: bool, w, h: int] =
  ## The map-layer viewport one binary frame declares, if any.
  if frame.len == 0:
    return
  for message in parseSpritePacket(frame.toOpenArrayByte(0, frame.high)):
    if message.kind == spkViewport and message.viewport.layer == MapLayerId:
      return (true, message.viewport.width, message.viewport.height)

proc watch(path: string, seconds: float): tuple[
  frames: int,
  scorePanel: bool,
  transport: bool,
  viewports: seq[(int, int)]
] =
  ## Watches one viewer socket for a window and reports what it drew.
  ##
  ## The window has to outlast the init packet, which carries the whole
  ## map at every day tint and takes several seconds to arrive on a
  ## cold socket; the first rendered frame only follows it.
  var ws = newWebSocket(WsOrigin & path)
  defer: ws.close()
  let deadline = epochTime() + seconds
  while epochTime() < deadline:
    let message = ws.receiveMessage(200)
    if message.isNone:
      continue
    case message.get().kind
    of BinaryMessage:
      inc result.frames
      let frame = message.get().data
      if frame.hasScorePanelCard():
        result.scorePanel = true
      if frame.hasReplayTransport():
        result.transport = true
      # Only rendered frames are shots. The init packet declares the
      # stock viewer's own viewport once, before any frame; that one is
      # not a director crop and must not be read as one. A rendered
      # frame is the one carrying the score-panel card.
      if frame.hasScorePanelCard():
        let view = frame.mapViewport()
        if view.found:
          result.viewports.add((view.w, view.h))
      if result.scorePanel and result.transport and result.viewports.len > 0:
        return
    of Ping:
      ws.send(message.get().data, Pong)
    else:
      discard

proc main() =
  doAssert fileExists(serverExe()), "build the server first: " & serverExe()
  let replayPath = getTempDir() / "heartleaf-routes-replay.bitreplay"
  writeFixtureReplay(replayPath)
  let server = startProcess(
    serverExe(),
    args = ["--load-replay:" & replayPath, "--port:" & $Port],
    options = {poStdErrToStdOut, poUsePath}
  )
  defer:
    server.terminate()
    discard server.waitForExit(5000)
    removeFile(replayPath)
  waitForHealth()

  echo "Testing the director page on the platform's routes"
  for path in DirectorPages:
    let (status, body) = fetch(path)
    doAssert status == 200, path & " should answer 200, got " & $status
    doAssert StockPageMarker in body, path & " should serve the viewer page"
    doAssert DirectorMarker in body, path & " should carry the fit snippet"

  echo "Testing the removed plain routes no longer serve a viewer"
  # The plain view is gone, so these are just unknown paths now. The
  # server has no 404 branch: unknown paths fall through to its
  # catch-all, which answers 200 with a plain-text banner. What this
  # pins is that neither path serves a viewer page any more.
  for path in RemovedPlainPages:
    let (status, body) = fetch(path)
    doAssert status == 200, path & " should answer 200, got " & $status
    doAssert StockPageMarker notin body,
      path & " must no longer serve the viewer page"
    doAssert DirectorMarker notin body,
      path & " must no longer serve the director page"

  echo "Testing the viewer websockets stream the director cut"
  echo "Testing every viewer route gets the replay transport and scrubber"
  echo "Testing every director frame fits a 16:9 window with no black bars"
  let mapAspect = MapAspectNum / MapAspectDen
  for path in DirectorSockets:
    let seen = watch(path, WatchSeconds)
    doAssert seen.frames > 0, path & " should stream at least one frame"
    doAssert seen.scorePanel, path & " should place the score-panel card"
    # "I don't have the scrubber so I can't play/pause it": in replay
    # server mode the transport belongs to every viewer route, not just
    # /replay.
    doAssert seen.transport,
      path & " should place the replay transport row and scrubber"
    doAssert seen.viewports.len > 0, path & " should declare a map viewport"
    for (w, h) in seen.viewports:
      # The client fits the declared viewport into its window. The map
      # is 16:9 and every director crop keeps the map's aspect, so a
      # 16:9 window fits the frame edge to edge. Any other aspect is a
      # letterbox or a pillarbox: black bars.
      doAssert w > 0 and h > 0,
        path & " declared a degenerate viewport " & $w & "x" & $h
      let aspect = w / h
      doAssert abs(aspect - mapAspect) <= AspectTolerance,
        path & " viewport " & $w & "x" & $h & " is " & $aspect &
          ", not the map's " & $mapAspect & ": a 16:9 window would bar it"

  echo "Route tests passed"

main()
