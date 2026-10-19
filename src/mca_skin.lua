-- Player skins for the preview: download one by player name, load one from
-- a file, or use a plain built-in mannequin. Also builds the player model.

local fileio = require("mca_io")
local layout = require("mca_layout")
local png = require("mca_png")
local render = require("mca_render")

local S = {}

---------------------------------------------------------------------------
-- Helpers

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_INDEX = {}
for i = 1, #B64 do B64_INDEX[B64:sub(i, i)] = i - 1 end

local function base64Decode(text)
  text = text:gsub("[^%w%+/]", "")
  local out, bits, nbits = {}, 0, 0
  for i = 1, #text do
    bits = (bits << 6) | B64_INDEX[text:sub(i, i)]
    nbits = nbits + 6
    if nbits >= 8 then
      nbits = nbits - 8
      out[#out + 1] = string.char((bits >> nbits) & 0xff)
    end
  end
  return table.concat(out)
end

local function decodeJson(text)
  local ok, value = pcall(json.decode, text)
  if ok then return value end
  return nil
end

function S.toHex(data)
  return (data:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end

function S.fromHex(hex)
  return (hex:gsub("%x%x", function(h) return string.char(tonumber(h, 16)) end))
end

-- Minecraft player names: 3-16 letters, digits or underscores.
function S.isValidName(name)
  return type(name) == "string" and #name >= 3 and #name <= 16 and name:match("^[A-Za-z0-9_]+$") ~= nil
end

-- Skins are 64x64 (or 64x32 for very old ones), or HD multiples.
local function isSkinSize(w, h)
  return w >= 64 and w % 64 == 0 and (h == w or h * 2 == w)
end

-- Old 64x32 skins often fill the unused hat area with a solid colour.
-- Like the game, treat that area as empty when it has no transparency.
local function clearSolidHat(w, px)
  local s = w // 64
  for y = 0, 32 * s - 1 do
    for x = 32 * s, 64 * s - 1 do
      if ((px[y * w + x] or 0) >> 24) < 128 then return end
    end
  end
  for y = 0, 16 * s - 1 do
    for x = 32 * s, 64 * s - 1 do px[y * w + x] = 0 end
  end
end

-- Texture from PNG file contents, or nil and an error message.
function S.textureFromPNG(data)
  local w, h, px = png.decode(data)
  if not w then return nil, "this isn't a valid PNG" end
  if not isSkinSize(w, h) then
    return nil, string.format("a skin must be 64x64 or 64x32 (this one is %dx%d)", w, h)
  end
  if h * 2 == w then clearSolidHat(w, px) end
  return render.textureFromPixels(w, h, px)
end

---------------------------------------------------------------------------
-- Getting skins

-- Mojang answers with an empty reply when it gets too many requests.
local BUSY = "Mojang is busy right now, try again in a moment"

-- Downloads a player's skin from Mojang. Returns { name, slim, png } or nil
-- and an error message.
function S.fetch(name)
  if not S.isValidName(name) then return nil, "that isn't a valid player name" end

  local body, err = fileio.download("https://api.mojang.com/users/profiles/minecraft/" .. name)
  if not body then return nil, err end
  local profile = decodeJson(body)
  if not profile then return nil, BUSY end
  if not profile.id then
    local reason = profile.errorMessage
    if not reason or reason:find("find any profile") then return nil, "player not found" end
    return nil, "Mojang: " .. reason
  end

  body, err = fileio.download("https://sessionserver.mojang.com/session/minecraft/profile/" .. profile.id)
  if not body then return nil, err end
  local session = decodeJson(body)
  if not session then return nil, BUSY end
  if session.errorMessage then return nil, "Mojang: " .. session.errorMessage end
  local encoded
  for _, prop in ipairs(session and session.properties or {}) do
    if prop.name == "textures" then encoded = prop.value end
  end
  local textures = encoded and decodeJson(base64Decode(encoded))
  local skin = textures and textures.textures and textures.textures.SKIN
  if not skin or not skin.url then return nil, "this player uses a default skin" end

  local file = app.fs.joinPath(app.fs.tempPath, "minecraft-armor-tools-skin.png")
  local url = skin.url:gsub("^http://", "https://")
  local saved
  saved, err = fileio.download(url, file)
  if not saved then return nil, err end
  local data
  data, err = fileio.readFile(file)
  if not data then return nil, err end
  local tex = S.textureFromPNG(data)
  if not tex then return nil, "couldn't download the skin" end
  local slim = skin.metadata ~= nil and skin.metadata.model == "slim"
  return { name=profile.name or name, slim=slim, png=data, tex=tex }
end

-- Loads a skin PNG from disk. Returns { name, png, tex } or nil and an
-- error message.
function S.loadFile(path)
  local data, err = fileio.readFile(path)
  if not data then return nil, err end
  local tex
  tex, err = S.textureFromPNG(data)
  if not tex then return nil, err end
  return { name=app.fs.fileName(path), png=data, tex=tex }
end

-- A plain grey figure, used until a skin is chosen.
local mannequin
function S.mannequin()
  if mannequin then return mannequin end
  local px = {}
  local fill, edge = 0xff8a847c, 0xff5e5a55
  local parts = {
    { 0, 0, 8, 8, 8 }, { 16, 16, 8, 12, 4 }, { 40, 16, 4, 12, 4 },
    { 32, 48, 4, 12, 4 }, { 0, 16, 4, 12, 4 }, { 16, 48, 4, 12, 4 },
  }
  for _, p in ipairs(parts) do
    for _, r in pairs(layout.boxFaceRects(p[1], p[2], p[3], p[4], p[5])) do
      for y = r[2], r[2] + r[4] - 1 do
        for x = r[1], r[1] + r[3] - 1 do
          local border = x == r[1] or y == r[2] or x == r[1] + r[3] - 1 or y == r[2] + r[4] - 1
          px[y * 64 + x] = border and edge or fill
        end
      end
    end
  end
  mannequin = render.textureFromPixels(64, 64, px)
  return mannequin
end

---------------------------------------------------------------------------
-- Player model

-- Boxes for the renderer. 64x64 skins have their own left arm and leg plus
-- an outer layer (jacket, sleeves, trousers); 64x32 skins mirror the right
-- limbs and only have a hat layer. Slim ("Alex") arms are 3 pixels wide.
function S.playerBoxes(tex, slim)
  local modern = tex.h == tex.w
  local armW = slim and 3 or 4
  local armY = slim and 11.5 or 12
  local boxes = {}
  local function add(uv, size, from, grow, mirror, outer)
    boxes[#boxes + 1] = { tex=tex, uv=uv, size=size, from=from, grow=grow or 0,
                          mirror=mirror, opaque=not outer }
  end

  -- Inner layer (drawn without transparency, like the game)
  add({ 0, 0 },   { 8, 8, 8 },     { -4, 24, -4 })
  add({ 16, 16 }, { 8, 12, 4 },    { -4, 12, -2 })
  add({ 40, 16 }, { armW, 12, 4 }, { -4 - armW, armY, -2 })
  add({ 0, 16 },  { 4, 12, 4 },    { -3.9, 0, -2 })
  if modern then
    add({ 32, 48 }, { armW, 12, 4 }, { 4, armY, -2 })
    add({ 16, 48 }, { 4, 12, 4 },    { -0.1, 0, -2 })
  else
    add({ 40, 16 }, { armW, 12, 4 }, { 4, armY, -2 }, 0, true)
    add({ 0, 16 },  { 4, 12, 4 },    { -0.1, 0, -2 }, 0, true)
  end

  -- Outer layer
  add({ 32, 0 }, { 8, 8, 8 }, { -4, 24, -4 }, 0.5, false, true)
  if modern then
    add({ 16, 32 }, { 8, 12, 4 },    { -4, 12, -2 },          0.25, false, true)
    add({ 40, 32 }, { armW, 12, 4 }, { -4 - armW, armY, -2 }, 0.25, false, true)
    add({ 48, 48 }, { armW, 12, 4 }, { 4, armY, -2 },         0.25, false, true)
    add({ 0, 32 },  { 4, 12, 4 },    { -3.9, 0, -2 },         0.25, false, true)
    add({ 0, 48 },  { 4, 12, 4 },    { -0.1, 0, -2 },         0.25, false, true)
  end
  return boxes
end

return S
