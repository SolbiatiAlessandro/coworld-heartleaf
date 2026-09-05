## Frame-level checks of the director cut against a recorded replay.
##
## There is no screenshot here and no model key, so a shot is judged by
## decoding the sprite protocol off a viewer socket and reading what the
## client would have been told to draw: the viewport it declared, where
## the map bottom sits under it, and which objects are in the frame.
##
## What it pins, on every viewer route:
##
##   - every rendered frame declares a viewport with the map's 16:9
##     aspect, so a 16:9 window fits it edge to edge and no frame is
##     letterboxed or pillarboxed into black bars;
##   - every crop lies inside the map, so no frame shows anything that
##     is not map;
##   - the camera actually moves, so a replay whose conversations all
##     overlap cannot park the shot for the whole recording;
##   - conversation cards reach every route, and while they are on
##     screen the server defines no sprites: the cards are assembled
##     from parts that shipped in the init packet.
##
## Needs a recorded replay, which the repository does not carry. Get one
## with:
##
##   git fetch origin test-fixtures
##   git checkout origin/test-fixtures -- tests/fixtures/
##
## and build the server first (`nim c -o:out/heartleaf src/heartleaf.nim`).
## Without the fixture the test says so and exits cleanly, so CI, which
## has neither, stays green.

import
  std/[httpclient, os, osproc, strutils, tables, times],
  bitworld/spriteprotocol,
  whisky,
  heartleaf,
  heartleaf/[common, protocol]

const
  Port = 18963
  Origin = "http://localhost:" & $Port
  WsOrigin = "ws://localhost:" & $Port
  FixturePath = "tests" / "fixtures" / "luna_9gnomes.bitreplay"
  ViewerSockets = ["/global", "/replay", "/clients/global"]
  WatchSeconds = 45.0
    ## The init packet carries the whole map at every day tint and takes
    ## several seconds to land; rendered frames only follow it.
  MinRenderedFrames = 40
  AspectTolerance = 0.01
  MapAspectNum = 16.0
  MapAspectDen = 9.0

type Seen = object
  rendered: int
  crops: Table[string, int]
  cardFrames: int
  spriteDefsWithCards: int
  spriteLabelsWithCards: seq[string]
  mapWidth: int
  mapHeight: int

proc serverExe(): string =
  let configured = getEnv("HEARTLEAF_SERVER")
  if configured.len > 0:
    return configured
  "out" / "heartleaf"

proc waitForHealth() =
  let client = newHttpClient(timeout = 1000)
  defer: client.close()
  for _ in 0 ..< 600:
    try:
      if client.getContent(Origin & "/healthz") == "healthy":
        return
    except CatchableError:
      discard
    sleep(100)
  raise newException(CatchableError, "server never became healthy")

proc watch(path: string, seconds: float): Seen =
  ## Decodes one viewer socket for a window and folds what it drew.
  var ws = newWebSocket(WsOrigin & path)
  defer: ws.close()
  result.crops = initTable[string, int]()
  let deadline = epochTime() + seconds
  while epochTime() < deadline and result.rendered < 600:
    let message = ws.receiveMessage(200)
    if message.isNone:
      continue
    if message.get().kind == Ping:
      ws.send(message.get().data, Pong)
      continue
    if message.get().kind != BinaryMessage:
      continue
    let frame = message.get().data
    if frame.len == 0:
      continue
    var
      viewportW, viewportH = 0
      haveViewport = false
      bottomX, bottomY = 0
      haveBottom = false
      cards = 0
      spriteDefs: seq[string]
      scorePanel = false
    for msg in parseSpritePacket(frame.toOpenArrayByte(0, frame.high)):
      case msg.kind
      of spkSprite:
        # The map bottom's own definition tells the test how big the
        # map is, without the test having to load the asset itself.
        if msg.sprite.label.startsWith("heartleaf bottom") and
            not msg.sprite.label.contains("tint"):
          result.mapWidth = msg.sprite.width
          result.mapHeight = msg.sprite.height
        # Only card parts matter here. The replay transport legitimately
        # redraws its tick counter and scrubber every tick.
        if msg.sprite.label.startsWith("director card"):
          spriteDefs.add(msg.sprite.label)
      of spkViewport:
        if msg.viewport.layer == MapLayerId:
          viewportW = msg.viewport.width
          viewportH = msg.viewport.height
          haveViewport = true
      of spkObject:
        if msg.objectDef.id == BottomObjectId:
          bottomX = msg.objectDef.x
          bottomY = msg.objectDef.y
          haveBottom = true
        if msg.objectDef.id == GlobalPanelCardObjectId and
            msg.objectDef.spriteId == GlobalPanelCardSpriteId:
          scorePanel = true
        if msg.objectDef.id >= DirectorCardObjectBase and
            msg.objectDef.id < DirectorCardObjectBase + HouseCount:
          inc cards
      else:
        discard
    # A rendered frame is one that placed the score-panel card. The init
    # packet declares the stock viewer's own viewport before any frame;
    # that one is not a director crop and must not be read as one.
    if not scorePanel:
      continue
    inc result.rendered
    doAssert haveViewport,
      path & " rendered a frame with no map viewport"
    doAssert haveBottom,
      path & " rendered a frame with no map bottom object"
    doAssert viewportW > 0 and viewportH > 0,
      path & " declared a degenerate viewport " & $viewportW & "x" & $viewportH
    let aspect = viewportW / viewportH
    doAssert abs(aspect - MapAspectNum / MapAspectDen) <= AspectTolerance,
      path & " viewport " & $viewportW & "x" & $viewportH & " has aspect " &
        $aspect & ", not the map's 16:9: a 16:9 window would show black bars"
    # The bottom object is placed at minus the camera, so the camera is
    # minus its position, and the crop must sit inside the map.
    let
      cameraX = -bottomX
      cameraY = -bottomY
    doAssert cameraX >= 0 and cameraY >= 0,
      path & " camera at " & $cameraX & "," & $cameraY & " is off the map"
    if result.mapWidth > 0:
      doAssert cameraX + viewportW <= result.mapWidth,
        path & " crop runs " & $(cameraX + viewportW - result.mapWidth) &
          "px past the right edge of the map"
      doAssert cameraY + viewportH <= result.mapHeight,
        path & " crop runs " &
          $(cameraY + viewportH - result.mapHeight) &
          "px past the bottom edge of the map"
    result.crops[$cameraX & "," & $cameraY & "," & $viewportW] =
      result.crops.getOrDefault(
        $cameraX & "," & $cameraY & "," & $viewportW) + 1
    if cards > 0:
      inc result.cardFrames
      # Cards are assembled from init-packet parts. A card sprite
      # definition arriving while a card is on screen means the card is
      # being composed and re-sent again.
      # The very first packet a viewer gets carries the init packet and
      # the first frame together, so the card parts legitimately arrive
      # alongside it. Everything after that must define nothing.
      if result.rendered > 1:
        result.spriteDefsWithCards += spriteDefs.len
        for label in spriteDefs:
          if result.spriteLabelsWithCards.len < 8:
            result.spriteLabelsWithCards.add(label)

proc main() =
  if not fileExists(FixturePath):
    echo "director_frames: no ", FixturePath, "; skipping."
    echo "  git fetch origin test-fixtures && " &
      "git checkout origin/test-fixtures -- tests/fixtures/"
    return
  doAssert fileExists(serverExe()), "build the server first: " & serverExe()
  let server = startProcess(
    serverExe(),
    args = ["--load-replay:" & FixturePath, "--port:" & $Port],
    options = {poStdErrToStdOut, poUsePath}
  )
  defer:
    server.terminate()
    discard server.waitForExit(5000)
  waitForHealth()

  var totalCardFrames = 0
  for path in ViewerSockets:
    echo "Watching ", path
    let seen = watch(path, WatchSeconds)
    doAssert seen.rendered >= MinRenderedFrames,
      path & " rendered only " & $seen.rendered & " frames"
    doAssert seen.mapWidth > 0, path & " never defined the map bottom"
    doAssert seen.mapWidth * 9 == seen.mapHeight * 16,
      "the map is " & $seen.mapWidth & "x" & $seen.mapHeight & ", not 16:9"
    # A director that commits to one conversation and cannot be released
    # holds a single crop for the whole replay: the stuck shot Andre hit.
    doAssert seen.crops.len > 1,
      path & " held one crop for all " & $seen.rendered &
        " frames: the camera is stuck"
    doAssert seen.cardFrames > 0,
      path & " never placed a conversation card, so the chat is invisible"
    doAssert seen.spriteDefsWithCards == 0,
      path & " defined " & $seen.spriteDefsWithCards &
        " card sprites while cards were on screen (" &
        seen.spriteLabelsWithCards.join(", ") &
        "): cards should be assembled from init-packet parts"
    totalCardFrames += seen.cardFrames
    echo "  ", seen.rendered, " rendered frames, ", seen.crops.len,
      " distinct crops, ", seen.cardFrames, " with cards, map ",
      seen.mapWidth, "x", seen.mapHeight
  doAssert totalCardFrames > 0
  echo "Director frame tests passed"

main()
