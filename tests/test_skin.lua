-- Player skins and the player model, shading on/off and face outlines.
--   aseprite -b --script-param src=<src dir> --script-param fixtures=<tests/fixtures>
--     [--script-param online=1] --script tests/test_skin.lua
-- With online=1 it also downloads a real skin from Mojang.
package.path = app.params.src .. "/?.lua;" .. package.path
local layout = require("mca_layout")
local render = require("mca_render")
local skin = require("mca_skin")
local ok = true
local function check(cond, msg) print((cond and "ok   " or "FAIL ") .. msg); ok = ok and cond end

local function read(path)
  local f = assert(io.open(path, "rb"))
  local data = f:read("a")
  f:close()
  return data
end
local fixtures = app.params.fixtures

-- Player names
check(skin.isValidName("Notch") and skin.isValidName("jeb_"), "valid player names accepted")
check(not skin.isValidName("ab") and not skin.isValidName("no such!")
      and not skin.isValidName("seventeen_chars_x"), "invalid player names rejected")

-- Modern 64x64 skin
local modern = skin.textureFromPNG(read(app.fs.joinPath(fixtures, "skins", "test_skin.png")))
check(modern and modern.w == 64 and modern.h == 64, "64x64 skin loads")
local boxes = skin.playerBoxes(modern, false)
check(#boxes == 12, "64x64 skin: 6 inner + 6 outer boxes (got " .. #boxes .. ")")
local slim = skin.playerBoxes(modern, true)
check(slim[3].size[1] == 3 and slim[3].from[1] == -7, "slim arms are 3 pixels wide")
check(boxes[3].size[1] == 4 and boxes[3].from[1] == -8, "classic arms are 4 pixels wide")

-- Old 64x32 skin: mirrored limbs, hat only, solid hat area cleared
local legacy = skin.textureFromPNG(read(app.fs.joinPath(fixtures, "skins", "test_skin_legacy.png")))
check(legacy and legacy.h == 32, "64x32 skin loads")
local lboxes = skin.playerBoxes(legacy, false)
check(#lboxes == 7, "64x32 skin: 6 inner boxes + hat (got " .. #lboxes .. ")")
check(lboxes[5].mirror and lboxes[6].mirror, "64x32 skin mirrors the left arm and leg")
check((legacy.px[12 * 64 + 44] or 0) == 0, "solid hat area of an old skin is treated as empty")

-- Wrong input
check(skin.textureFromPNG("not a png") == nil, "non-PNG data rejected")
local armorPng = read(app.fs.joinPath(fixtures, "humanoid", "test_armor.png"))
check(skin.textureFromPNG(armorPng) ~= nil, "64x32 textures count as old skins")

-- Shading off shows exact texture colours: head front centre of the
-- mannequin, seen from the front.
local W, H = 220, 300
local function pixelAt(opts, x, y)
  opts.width, opts.height = W, H
  return render.render(opts):getPixel(x, y)
end
local zoom = render.fitZoom(W, H)
local headY = math.floor(H / 2 - (28 - 16) * zoom)
local mannequin = skin.mannequin()
local flat = pixelAt({ boxes=skin.playerBoxes(mannequin, false), yaw=0, pitch=0, shading=false }, W // 2, headY)
local shaded = pixelAt({ boxes=skin.playerBoxes(mannequin, false), yaw=0, pitch=0 }, W // 2, headY)
check(flat == mannequin.px[12 * 64 + 12], string.format("shading off: exact texture colour (%08x)", flat))
check(shaded ~= flat, "shading on: front face is darker")

-- Outlines use the grid colours.
local textures = {
  humanoid=render.textureFromFile(app.fs.joinPath(fixtures, "humanoid", "test_armor.png")),
  humanoid_leggings=render.textureFromFile(app.fs.joinPath(fixtures, "humanoid_leggings", "test_armor.png")),
}
local function countColour(img, rgb)
  local want = rgb[1] | (rgb[2] << 8) | (rgb[3] << 16) | 0xff000000
  local n = 0
  for it in img:pixels() do if it() == want then n = n + 1 end end
  return n
end
local withOutlines = render.render{ width=W, height=H, boxes=layout.armorBoxes(textures), yaw=-30, pitch=12, outlines=true }
local without = render.render{ width=W, height=H, boxes=layout.armorBoxes(textures), yaw=-30, pitch=12 }
-- (The test texture's solid helmet overlay hides the helmet itself.)
local overlayBlue = layout.GRIDS.humanoid[2].color
check(countColour(withOutlines, overlayBlue) > 50, "outlines on: helmet overlay outlined in its grid colour")
-- Each piece on its own (inner pieces are hidden behind outer ones).
local missing = {}
for _, piece in ipairs(layout.PIECES) do
  local only = {}
  for _, p in ipairs(layout.PIECES) do only[p.id] = (p.id == piece.id) end
  local img = render.render{ width=W, height=H, boxes=layout.armorBoxes(textures, only),
                             yaw=-30, pitch=12, outlines=true }
  for _, region in ipairs(layout.GRIDS[piece.layer]) do
    if region.piece == piece.id and region.label ~= "Helmet" and countColour(img, region.color) == 0 then
      missing[#missing + 1] = region.label
    end
  end
end
check(#missing == 0, "outlines on: every part shows its grid colour"
      .. (#missing > 0 and (" (missing: " .. table.concat(missing, ", ") .. ")") or ""))
check(countColour(without, overlayBlue) == 0, "outlines off: no outline colour drawn")

-- Player plus armor renders.
local both = {}
for _, b in ipairs(skin.playerBoxes(modern, true)) do both[#both + 1] = b end
for _, b in ipairs(layout.armorBoxes(textures)) do both[#both + 1] = b end
local drawn = 0
for it in render.render{ width=W, height=H, boxes=both, yaw=-30, pitch=12 }:pixels() do
  if (it() >> 24) > 0 then drawn = drawn + 1 end
end
check(drawn > 5000, "player with armor renders (" .. drawn .. " pixels)")

if app.params.online == "1" then
  -- Mojang limits how often one computer may ask; that isn't a failure here.
  local function busy(err) return err and err:find("busy") end
  local result, err = skin.fetch("Notch")
  if busy(err) then
    print("skip downloads a skin by player name (Mojang is rate limiting, run again later)")
  else
    check(result ~= nil and result.name == "Notch", "downloads a skin by player name" .. (err and (": " .. err) or ""))
    local _, err2 = skin.fetch("qzxqzx_nobody1")
    check(err2 == "player not found" or busy(err2), "unknown player: " .. tostring(err2))
  end
end

print(ok and "PASS" or "FAILED")
