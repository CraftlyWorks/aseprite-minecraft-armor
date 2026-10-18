-- Generates the test textures in tests/fixtures. Every face of every armor
-- part is filled with its grid colour, outlined a little darker, and its
-- top-left pixel is white so orientation mistakes are easy to spot.
--   aseprite -b --script-param src=<src dir> --script-param out=<fixtures dir> --script tests/make_fixtures.lua

package.path = app.params.src .. "/?.lua;" .. package.path
local layout = require("mca_layout")
local pc = app.pixelColor

local function shade(c, f)
  return pc.rgba(math.floor(c[1] * f), math.floor(c[2] * f), math.floor(c[3] * f), 255)
end

local function paint(img, layer)
  for _, region in ipairs(layout.GRIDS[layer]) do
    for _, face in ipairs(layout.FACE_ORDER) do
      local r = layout.faceRects(region.part)[face]
      local fill, edge = shade(region.color, 0.85), shade(region.color, 0.55)
      for y = r[2], r[2] + r[4] - 1 do
        for x = r[1], r[1] + r[3] - 1 do
          local border = x == r[1] or y == r[2] or x == r[1] + r[3] - 1 or y == r[2] + r[4] - 1
          img:drawPixel(x, y, border and edge or fill)
        end
      end
      img:drawPixel(r[1], r[2], pc.rgba(255, 255, 255, 255))
    end
  end
end

local function save(layer, path, indexed)
  local spr = Sprite(layout.BASE_W, layout.BASE_H)
  paint(spr.cels[1].image, layer)
  if indexed then
    app.sprite = spr
    app.command.ChangePixelFormat{ format="indexed" }
  end
  app.fs.makeAllDirectories(app.fs.filePath(path))
  spr:saveAs(path)
  spr:close()
  print("wrote " .. path)
end

local out = app.params.out
save(layout.LAYER1, app.fs.joinPath(out, "humanoid", "test_armor.png"))
save(layout.LAYER2, app.fs.joinPath(out, "humanoid_leggings", "test_armor.png"))
-- Older resource packs: <name>_layer_1/2.png side by side, saved indexed.
save(layout.LAYER1, app.fs.joinPath(out, "legacy", "test_armor_layer_1.png"), true)
save(layout.LAYER2, app.fs.joinPath(out, "legacy", "test_armor_layer_2.png"), true)
