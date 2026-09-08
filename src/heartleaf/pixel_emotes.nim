## Small, hand-authored pixel faces using the game's parchment palette.
## Each source pixel is a 2x2 block. No font emoji or interpolation.
import pixie, bitworld/sprites

proc pixelEmote*(tier: int): RgbaSprite =
  const face = [
    ".....oooooo.....",
    "...ooYYYYYYoo...",
    "..oYYyyyyyyyyo..",
    ".oYYyyyyyyyyyyo.",
    ".oYyyyyyyyyyyyo.",
    "oYyyyyyyyyyyyyyo",
    "oYyyyyyyyyyyyyyo",
    "oYyyyyyyyyyyyyyo",
    "oyyyyyyyyyyyyyyo",
    "oyyyyyyyyyyyyyyo",
    ".oyyyyyyyyyyyyo.",
    ".oyyyyyyyyyyyyo.",
    "..oyyyyyyyyyyo..",
    "...ooyyyyyyoo...",
    ".....oooooo.....",
    "................"
  ]
  let
    outline = rgba(94, 58, 22, 255)
    fill = rgba(224, 175, 72, 255)
    light = rgba(248, 220, 136, 255)
  result = newRgbaSprite(32, 32)
  proc dot(sprite: var RgbaSprite, x, y: int, color: ColorRGBA) =
    for dy in 0 .. 1:
      for dx in 0 .. 1:
        sprite.putPixel(x * 2 + dx, y * 2 + dy, color)
  for y, row in face:
    for x, ch in row:
      case ch
      of 'o': result.dot(x, y, outline)
      of 'y': result.dot(x, y, fill)
      of 'Y': result.dot(x, y, light)
      else: discard
  for x in [5, 10]:
    result.dot(x, 5, outline)
    result.dot(x, 6, outline)
    if tier >= 2:
      result.dot(x - 1, 5, outline)
      result.dot(x + 1, 5, outline)
      result.dot(x, 4, outline)
  if tier <= 0:
    for x in 5 .. 10: result.dot(x, 10, outline)
  else:
    result.dot(4, 9, outline)
    result.dot(11, 9, outline)
    result.dot(5, 10, outline)
    result.dot(10, 10, outline)
    for x in 6 .. 9: result.dot(x, 11, outline)
