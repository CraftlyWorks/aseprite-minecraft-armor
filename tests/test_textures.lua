-- Texture reading must match Aseprite's own flattening (Image:drawSprite,
-- used here only as the reference): from disk, and from open sprites with
-- trimmed cels, hidden layers, opacity, groups and indexed colour.
--   aseprite -b --script-param src=<src dir> --script-param files="a.png;b.png"
--     --script-param palette=<indexed png> --script tests/test_textures.lua
package.path = app.params.src .. "/?.lua;" .. package.path
local render = require("mca_render")
local failures = 0

local function reference(sprite)
  local img = Image(sprite.width, sprite.height, ColorMode.RGB)
  img:drawSprite(sprite, 1)
  return render.textureFromImage(img)
end

local function compare(label, a, b)
  local diffs = 0
  for i = 0, a.w * a.h - 1 do
    local p, q = a.px[i] or 0, b.px[i] or 0
    -- Fully transparent pixels may differ in RGB; compare only visible ones.
    if ((p >> 24) ~= 0 or (q >> 24) ~= 0) and p ~= q then diffs = diffs + 1 end
  end
  print(string.format("%-4s %-46s %d differing pixels", diffs == 0 and "ok" or "FAIL", label, diffs))
  if diffs > 0 then failures = failures + 1 end
end

-- Files: disk loader vs open sprite vs reference.
for path in app.params.files:gmatch("[^;]+") do
  local name = app.fs.fileName(app.fs.filePath(path)) .. "/" .. app.fs.fileName(path)
  local spr = Sprite{ fromFile=path }
  local ref = reference(spr)
  compare(name .. " (disk)", render.textureFromFile(path), ref)
  compare(name .. " (open tab)", render.textureFromSprite(spr, 1), ref)
  spr:close()
end

-- Synthetic sprites.
local red, green, blue = Color(255, 0, 0), Color(0, 255, 0), Color(0, 0, 255)

local spr = Sprite(64, 32)
app.sprite = spr
app.useTool{ tool="pencil", color=red, points={ Point(3, 20), Point(30, 28) } }   -- cel gets trimmed to y>=16
local top = spr:newLayer()
app.useTool{ tool="pencil", color=green, layer=top, points={ Point(0, 18), Point(20, 18) } }
top.opacity = 128
local hidden = spr:newLayer()
app.useTool{ tool="pencil", color=blue, layer=hidden, points={ Point(5, 5), Point(9, 25) } }
hidden.isVisible = false
compare("trimmed cel + 50% layer + hidden layer", render.textureFromSprite(spr, 1), reference(spr))
local group = spr:newGroup()
top.parent = group
group.opacity = 200
compare("layer inside a group", render.textureFromSprite(spr, 1), reference(spr))
spr:close()

local idx = Sprite(64, 32, ColorMode.INDEXED)
idx:setPalette(Palette{ fromFile=app.params.palette })
app.sprite = idx
app.useTool{ tool="pencil", color=Color{ index=3 }, points={ Point(1, 17), Point(40, 31) } }
compare("indexed sprite", render.textureFromSprite(idx, 1), reference(idx))
idx:close()

print(failures == 0 and "PASS" or ("FAIL: " .. failures))
