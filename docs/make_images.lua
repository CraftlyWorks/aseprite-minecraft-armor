-- Regenerates the README images from the test textures.
--   aseprite -b --script-param src=<src dir> --script-param fixtures=<tests/fixtures>
--     --script-param out=<docs dir> --script docs/make_images.lua
package.path = app.params.src .. "/?.lua;" .. package.path
local layout = require("mca_layout")
local render = require("mca_render")
local pc = app.pixelColor
local BG = pc.rgba(40, 42, 48, 255)

local function load(name)
  return Image{ fromFile=app.fs.joinPath(app.params.fixtures, name, "test_armor.png") }
end

-- layout.png: Layer 1 and Layer 2 side by side, 8x.
local S, GAP = 8, 32
local l1, l2 = load("humanoid"), load("humanoid_leggings")
local sheetLayout = Image(64 * S * 2 + GAP * 3, 32 * S + GAP * 2, ColorMode.RGB)
sheetLayout:clear(BG)
for i, img in ipairs{ l1, l2 } do
  local ox = GAP + (i - 1) * (64 * S + GAP)
  for it in img:pixels() do
    local c = it()
    local light = ((it.x + it.y) % 2 == 0) and 58 or 50
    if (c >> 24) == 0 then c = pc.rgba(light, light, light + 6, 255) end
    for dy = 0, S - 1 do
      for dx = 0, S - 1 do sheetLayout:drawPixel(ox + it.x * S + dx, GAP + it.y * S + dy, c) end
    end
  end
end
sheetLayout:saveAs(app.fs.joinPath(app.params.out, "layout.png"))

-- preview.png: the 3D preview from three angles, then the leggings alone.
-- The helmet overlay is cleared here (in real armor it's mostly empty) so
-- the helmet itself is visible.
local helmetOnly = l1:clone()
for y = 0, 15 do for x = 32, 63 do helmetOnly:drawPixel(x, y, 0) end end
local textures = { humanoid=render.textureFromImage(helmetOnly), humanoid_leggings=render.textureFromImage(l2) }
local W, H = 240, 330
local legsOnly = { helmet=false, chestplate=false, leggings=true, boots=false }
local views = {
  { yaw=-30, pitch=12 }, { yaw=90, pitch=0 }, { yaw=-35, pitch=55 }, { yaw=-30, pitch=12, show=legsOnly },
}
local sheet = Image(W * #views, H, ColorMode.RGB)
sheet:clear(BG)
for i, v in ipairs(views) do
  sheet:drawImage(render.render{ width=W, height=H, boxes=layout.armorBoxes(textures, v.show), yaw=v.yaw, pitch=v.pitch },
                  Point((i - 1) * W, 0))
end
sheet:saveAs(app.fs.joinPath(app.params.out, "preview.png"))
print("wrote layout.png and preview.png")
