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

-- Test skins: each part of the inner layer in its own colour, the outer
-- layer (hat, jacket, sleeves, trousers) as a light frame.
local INNER = {
  { 0, 0, 8, 8, 8, {230, 190, 150} }, { 16, 16, 8, 12, 4, {60, 120, 200} },
  { 40, 16, 4, 12, 4, {200, 150, 110} }, { 32, 48, 4, 12, 4, {190, 140, 100} },
  { 0, 16, 4, 12, 4, {70, 70, 160} }, { 16, 48, 4, 12, 4, {60, 60, 150} },
}
local OUTER = {
  { 32, 0, 8, 8, 8 }, { 16, 32, 8, 12, 4 }, { 40, 32, 4, 12, 4 },
  { 48, 48, 4, 12, 4 }, { 0, 32, 4, 12, 4 }, { 0, 48, 4, 12, 4 },
}
local function saveSkin(path, legacy)
  local h = legacy and 32 or 64
  local spr = Sprite(64, h)
  local img = spr.cels[1].image
  for _, p in ipairs(INNER) do
    if p[2] + p[5] + p[4] <= h then
      for _, r in pairs(layout.boxFaceRects(p[1], p[2], p[3], p[4], p[5])) do
        for y = r[2], r[2] + r[4] - 1 do
          for x = r[1], r[1] + r[3] - 1 do img:drawPixel(x, y, shade(p[6], 1)) end
        end
      end
    end
  end
  if legacy then
    -- Old skins often fill the unused right half solid; the game then
    -- treats the hat as empty.
    for y = 0, 31 do
      for x = 32, 63 do
        if img:getPixel(x, y) == 0 then img:drawPixel(x, y, pc.rgba(0, 0, 0, 255)) end
      end
    end
  else
    for _, p in ipairs(OUTER) do
      for _, r in pairs(layout.boxFaceRects(p[1], p[2], p[3], p[4], p[5])) do
        for y = r[2], r[2] + r[4] - 1 do
          for x = r[1], r[1] + r[3] - 1 do
            local border = x == r[1] or y == r[2] or x == r[1] + r[3] - 1 or y == r[2] + r[4] - 1
            if border then img:drawPixel(x, y, pc.rgba(250, 250, 250, 255)) end
          end
        end
      end
    end
  end
  app.fs.makeAllDirectories(app.fs.filePath(path))
  spr:saveAs(path)
  spr:close()
  print("wrote " .. path)
end

local out = app.params.out
saveSkin(app.fs.joinPath(out, "skins", "test_skin.png"), false)
saveSkin(app.fs.joinPath(out, "skins", "test_skin_legacy.png"), true)
save(layout.LAYER1, app.fs.joinPath(out, "humanoid", "test_armor.png"))
save(layout.LAYER2, app.fs.joinPath(out, "humanoid_leggings", "test_armor.png"))
-- Older resource packs: <name>_layer_1/2.png side by side, saved indexed.
save(layout.LAYER1, app.fs.joinPath(out, "legacy", "test_armor_layer_1.png"), true)
save(layout.LAYER2, app.fs.joinPath(out, "legacy", "test_armor_layer_2.png"), true)
