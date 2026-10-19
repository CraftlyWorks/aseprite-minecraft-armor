-- Minecraft Java Edition armor texture layout (64x32 "humanoid" equipment
-- textures, plus HD multiples like 128x64).
--
-- Model space used everywhere in this extension, measured in texels of a
-- 64x32 texture: x grows toward the wearer's left, y grows up (feet at 0),
-- z grows toward the wearer's front.

local compat = require("mca_compat")

local M = {}

M.BASE_W, M.BASE_H = 64, 32

-- The two texture files an armor set is made of.
M.LAYER1 = "humanoid"           -- helmet, chestplate, boots
M.LAYER2 = "humanoid_leggings"  -- leggings
M.LAYERS = { M.LAYER1, M.LAYER2 }

M.LAYER_LABELS = {
  [M.LAYER1] = "Layer 1 (helmet, chestplate, boots)",
  [M.LAYER2] = "Layer 2 (leggings)",
}

function M.otherLayer(layer)
  return layer == M.LAYER1 and M.LAYER2 or M.LAYER1
end

-- Box-UV parts: uv = texture offset, size = { w (x), h (y), d (z) }.
M.PARTS = {
  head = { uv={ 0,  0}, size={8,  8, 8} },
  hat  = { uv={32,  0}, size={8,  8, 8} },
  body = { uv={16, 16}, size={8, 12, 4} },
  arm  = { uv={40, 16}, size={4, 12, 4} },
  leg  = { uv={ 0, 16}, size={4, 12, 4} },
}

-- Where each part sits on the model. Left limbs reuse the right limb's
-- pixels, mirrored, exactly like the game does.
M.BONES = {
  head      = { part="head", from={-4,   24, -4} },
  hat       = { part="hat",  from={-4,   24, -4} },
  body      = { part="body", from={-4,   12, -2} },
  right_arm = { part="arm",  from={-8,   12, -2} },
  left_arm  = { part="arm",  from={ 4,   12, -2}, mirror=true },
  right_leg = { part="leg",  from={-3.9,  0, -2} },
  left_leg  = { part="leg",  from={-0.1,  0, -2}, mirror=true },
}

-- Armor pieces: which texture they read and which bones they cover, with
-- the game's inflation (CubeDeformation) so pieces nest like in-game.
M.PIECES = {
  { id="helmet", name="Helmet", layer=M.LAYER1,
    bones={ {"head", 1.0}, {"hat", 1.5} } },
  { id="chestplate", name="Chestplate", layer=M.LAYER1,
    bones={ {"body", 1.0}, {"right_arm", 1.0}, {"left_arm", 1.0} } },
  { id="leggings", name="Leggings", layer=M.LAYER2,
    bones={ {"body", 0.5}, {"right_leg", 0.4}, {"left_leg", 0.4} } },
  { id="boots", name="Boots", layer=M.LAYER1,
    bones={ {"right_leg", 0.9}, {"left_leg", 0.9} } },
}

-- Grid regions drawn as slices on each texture, one colour per region.
M.GRIDS = {
  [M.LAYER1] = {
    { piece="helmet",     label="Helmet",          part="head", color={ 80, 160, 255} },
    { piece="helmet",     label="Helmet Overlay",  part="hat",  color={150, 215, 255} },
    { piece="chestplate", label="Chestplate",      part="body", color={255,  85,  85} },
    { piece="chestplate", label="Chestplate Arms", part="arm",  color={255, 170,  50} },
    { piece="boots",      label="Boots",           part="leg",  color={ 70, 220, 110} },
  },
  [M.LAYER2] = {
    { piece="leggings", label="Leggings Waist", part="body", color={185, 115, 255} },
    { piece="leggings", label="Leggings Legs",  part="leg",  color={255, 105, 215} },
  },
}

M.FACE_ORDER = { "top", "bottom", "right", "front", "left", "back" }
M.FACE_NAMES = {
  top="Top", bottom="Bottom", right="Right Side", front="Front",
  left="Left Side", back="Back",
}

-- Face rectangles { x, y, w, h } of a w x h x d box whose box-UV starts at
-- (u, v). "right"/"left" are the wearer's right/left.
function M.boxFaceRects(u, v, w, h, d)
  return {
    top    = { u + d,         v,     w, d },
    bottom = { u + d + w,     v,     w, d },
    right  = { u,             v + d, d, h },
    front  = { u + d,         v + d, w, h },
    left   = { u + d + w,     v + d, d, h },
    back   = { u + d + w + d, v + d, w, h },
  }
end

-- Face rectangles of an armor part on a 64x32 texture.
function M.faceRects(partId)
  local p = M.PARTS[partId]
  return M.boxFaceRects(p.uv[1], p.uv[2], p.size[1], p.size[2], p.size[3])
end

-- Grid colour of a part on a layer, as an rgba pixel value.
local function gridColor(layer, partId)
  for _, region in ipairs(M.GRIDS[layer]) do
    if region.part == partId then
      local c = region.color
      return c[1] | (c[2] << 8) | (c[3] << 16) | 0xff000000
    end
  end
  return nil
end

-- Boxes for the renderer: every armor piece that has a texture and isn't
-- hidden in `show` (e.g. { boots=false }). Each face outline uses the same
-- colour as that part's grid on the texture.
function M.armorBoxes(textures, show)
  local boxes = {}
  for _, piece in ipairs(M.PIECES) do
    local tex = textures[piece.layer]
    if tex and (not show or show[piece.id] ~= false) then
      for _, ref in ipairs(piece.bones) do
        local bone = M.BONES[ref[1]]
        local part = M.PARTS[bone.part]
        boxes[#boxes + 1] = {
          tex=tex, uv=part.uv, size=part.size, from=bone.from, grow=ref[2],
          mirror=bone.mirror, outline=gridColor(piece.layer, bone.part),
        }
      end
    end
  end
  return boxes
end

-- 64x32, 128x64, 256x128...
function M.isArmorSize(w, h)
  return w >= M.BASE_W and w % M.BASE_W == 0 and h * 2 == w
end

-- Guesses which layer a file is from its folder or name:
--   .../humanoid/iron.png            -> Layer 1
--   .../humanoid_leggings/iron.png   -> Layer 2
--   iron_layer_1.png / iron_layer_2.png (pre-1.21.2 packs)
-- Folder and file names are matched case-insensitively: Windows and macOS
-- file systems usually ignore case.
function M.classify(path)
  if not path or path == "" then return nil end
  local folder = app.fs.fileName(app.fs.filePath(path)):lower()
  if folder == "humanoid" then return M.LAYER1 end
  if folder == "humanoid_leggings" then return M.LAYER2 end
  local title = app.fs.fileTitle(path):lower()
  if title:match("_layer_1$") then return M.LAYER1 end
  if title:match("_layer_2$") then return M.LAYER2 end
  return nil
end

-- Path of the other texture of the set, derived from the file's folder or
-- name (it may not exist on disk). nil when the path follows neither scheme.
-- app.fs builds it with the platform's separator ("\" on Windows).
function M.partnerPath(path)
  if not path or path == "" then return nil end
  local dir = app.fs.filePath(path)
  local folder = app.fs.fileName(dir):lower()
  if folder == "humanoid" or folder == "humanoid_leggings" then
    local otherFolder = (folder == "humanoid") and "humanoid_leggings" or "humanoid"
    return app.fs.joinPath(app.fs.filePath(dir), otherFolder, app.fs.fileName(path))
  end
  local title = app.fs.fileTitle(path)
  local n = title:lower():match("_layer_([12])$")
  if n then
    local otherTitle = title:sub(1, -2) .. (n == "1" and "2" or "1")
    return app.fs.joinPath(dir, otherTitle .. "." .. app.fs.fileExtension(path))
  end
  return nil
end

-- The open sprite (tab) for a file, if any.
function M.findOpenSprite(path)
  if not path then return nil end
  local key = compat.pathKey(path)
  for _, sprite in ipairs(app.sprites) do
    if compat.pathKey(sprite.filename) == key then return sprite end
  end
  return nil
end

return M
