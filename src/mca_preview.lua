-- Floating 3D preview window. It shows one armor set (Layer 1 + Layer 2),
-- optionally on a player, reading pixels from open tabs when possible (so
-- unsaved strokes show up immediately) and from disk otherwise.

local compat = require("mca_compat")
local layout = require("mca_layout")
local render = require("mca_render")
local skin = require("mca_skin")

local P = {}

local prefs
local dlg
local set = {}        -- { [layer] = path }
local textures = {}   -- [compat.pathKey(path)] = { tex=, source="tab"|"disk", spriteId=, dirty=, err= }
local skinTex         -- the chosen skin; nil means the plain built-in figure
local view
local drag
local version = 0     -- bumped whenever the picture must be re-rendered
local rendered = {}   -- last render: { img, w, h, div, version, tex1, tex2 }
local timers = {}

-- Above this many pixels the preview renders at a lower resolution.
local MAX_RENDER_PIXELS = 160000

local DEFAULT_VIEW = { yaw=-30, pitch=12, zoomMul=1, panX=0, panY=0 }
local PRESETS = {
  front  = { yaw=0,   pitch=0 },
  side   = { yaw=90,  pitch=0 },
  back   = { yaw=180, pitch=0 },
  angled = { yaw=-30, pitch=12 },
}
local ARMS = { "Classic arms", "Slim arms" }

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- Runs fn after `delay` seconds, outside of the current event.
local function later(delay, fn)
  local timer
  timer = Timer{
    interval=delay,
    ontick=function()
      timer:stop()
      timers[timer] = nil
      fn()
    end,
  }
  timers[timer] = true
  timer:start()
end

local function changed()
  version = version + 1
  if dlg then dlg:repaint() end
end

-- Repaints shortly after the current event instead of inside it: sprite
-- 'change' events fire while Aseprite is still finishing a brush stroke,
-- and reading the sprite at that moment isn't safe.
local repaintPending = false
local function changedSoon()
  if not dlg or repaintPending then return end
  repaintPending = true
  later(0.03, function()
    repaintPending = false
    changed()
  end)
end

local function resetView(preset)
  view = {}
  for k, v in pairs(DEFAULT_VIEW) do view[k] = v end
  if preset then
    view.yaw, view.pitch = preset.yaw, preset.pitch
  end
  changed()
end

---------------------------------------------------------------------------
-- Textures

-- Files that aren't open are read after the current event, never while
-- painting (the first read may show Aseprite's permission prompt).
local diskLoadPending = false
local updateLabels -- defined below
local function loadDiskTexturesSoon()
  if diskLoadPending then return end
  diskLoadPending = true
  later(0.01, function()
    diskLoadPending = false
    for _, layer in ipairs(layout.LAYERS) do
      local path = set[layer]
      if path and not layout.findOpenSprite(path) and app.fs.isFile(path) then
        local k = compat.pathKey(path)
        local entry = textures[k]
        if not entry or entry.source ~= "disk" or entry.dirty then
          local tex, err = render.textureFromFile(path)
          textures[k] = { tex=tex, source="disk", err=err }
        end
      end
    end
    updateLabels()
    changed()
  end)
end

local function textureFor(path)
  if not path then return nil end
  local k = compat.pathKey(path)
  local entry = textures[k]
  local sprite = layout.findOpenSprite(path)
  if sprite then
    if not entry or entry.source ~= "tab" or entry.spriteId ~= sprite.id or entry.dirty then
      entry = { tex=render.textureFromSprite(sprite, 1), source="tab", spriteId=sprite.id }
      textures[k] = entry
    end
    return entry.tex
  end
  if app.fs.isFile(path) then
    if not entry or entry.source ~= "disk" or entry.dirty then loadDiskTexturesSoon() end
    return entry and entry.source == "disk" and entry.tex or nil
  end
  textures[k] = nil
  return nil
end

local function describe(layer)
  local path = set[layer]
  if not path then return "none" end
  local name = app.fs.fileName(path)
  if layout.findOpenSprite(path) then return name .. " (open tab)" end
  if not app.fs.isFile(path) then return name .. " (not found)" end
  local entry = textures[compat.pathKey(path)]
  if entry and entry.err then return name .. " (" .. entry.err .. ")" end
  return name .. " (from disk)"
end

function updateLabels()
  if not dlg then return end
  dlg:modify{ id="layer1", text="Layer 1: " .. describe(layout.LAYER1) }
  dlg:modify{ id="layer2", text="Layer 2: " .. describe(layout.LAYER2) }
end

---------------------------------------------------------------------------
-- Player skin

local function setSkinStatus(text)
  if dlg then dlg:modify{ id="skinStatus", text="Skin: " .. text } end
end

local function skinLabel()
  if skinTex and prefs.skin and prefs.skin.name then return prefs.skin.name end
  return "plain figure"
end

-- Uses a fetched or loaded skin: { name, png, tex, slim (optional) }.
local function useSkin(result)
  skinTex = result.tex
  prefs.skin = { name=result.name, hex=skin.toHex(result.png) }
  if result.slim ~= nil then prefs.slim = result.slim end
  prefs.showPlayer = true
  if dlg then
    dlg:modify{ id="showPlayer", selected=true }
    dlg:modify{ id="arms", option=ARMS[prefs.slim and 2 or 1] }
  end
  setSkinStatus(skinLabel())
  changed()
end

local function getSkin()
  local name = dlg and dlg.data.skinName or ""
  name = name:gsub("^%s+", ""):gsub("%s+$", "")
  prefs.skinName = name
  if not skin.isValidName(name) then
    setSkinStatus("type a player name first")
    return
  end
  setSkinStatus("getting " .. name .. "...")
  later(0.05, function()
    local result, err = skin.fetch(name)
    if result then useSkin(result) else setSkinStatus(err) end
  end)
end

local function loadSkinFile(path)
  if not path or path == "" then return end
  later(0.01, function()
    local result, err = skin.loadFile(path)
    if result then useSkin(result) else setSkinStatus(err) end
  end)
end

---------------------------------------------------------------------------
-- Canvas

local function paint(ev)
  local gc = ev.context
  local W, H = gc.width, gc.height
  gc.color = prefs.lightBackground and Color{ r=214, g=214, b=220 } or Color{ r=52, g=52, b=58 }
  gc:fillRect(Rectangle(0, 0, W, H))

  local tex1, tex2 = textureFor(set[layout.LAYER1]), textureFor(set[layout.LAYER2])
  if not tex1 and not tex2 and not prefs.showPlayer then
    gc.color = prefs.lightBackground and Color{ r=90, g=90, b=100 } or Color{ r=165, g=165, b=175 }
    local msg = "Open an armor texture to preview it"
    local size = gc:measureText(msg)
    gc:fillText(msg, math.floor((W - size.width) / 2), math.floor(H / 2))
    return
  end

  if not rendered.img or rendered.w ~= W or rendered.h ~= H or rendered.version ~= version
     or rendered.tex1 ~= tex1 or rendered.tex2 ~= tex2 then
    local boxes = {}
    if prefs.showPlayer then
      boxes = skin.playerBoxes(skinTex or skin.mannequin(), prefs.slim == true)
    end
    for _, box in ipairs(layout.armorBoxes({ [layout.LAYER1]=tex1, [layout.LAYER2]=tex2 }, prefs.show)) do
      boxes[#boxes + 1] = box
    end
    -- Large windows render at a reduced resolution and are scaled up, so
    -- dragging stays smooth.
    local div = 1
    while math.ceil(W / div) * math.ceil(H / div) > MAX_RENDER_PIXELS do div = div + 1 end
    rendered = {
      img = render.render{
        width=math.ceil(W / div), height=math.ceil(H / div),
        boxes=boxes,
        yaw=view.yaw, pitch=view.pitch,
        zoom=render.fitZoom(W, H) * view.zoomMul / div,
        panX=view.panX / div, panY=view.panY / div,
        shading=prefs.shading ~= false,
        outlines=prefs.outlines == true,
      },
      w=W, h=H, div=div, version=version, tex1=tex1, tex2=tex2,
    }
  end
  local img, div = rendered.img, rendered.div
  if div == 1 then
    gc:drawImage(img, 0, 0)
  else
    gc:drawImage(img, Rectangle(0, 0, img.width, img.height),
                 Rectangle(0, 0, img.width * div, img.height * div))
  end
end

local function onMouseDown(ev)
  drag = {
    x=ev.x, y=ev.y,
    pan = ev.button == MouseButton.RIGHT or ev.button == MouseButton.MIDDLE or ev.shiftKey,
  }
end

local function onMouseMove(ev)
  if not drag then return end
  local dx, dy = ev.x - drag.x, ev.y - drag.y
  drag.x, drag.y = ev.x, ev.y
  if drag.pan then
    view.panX, view.panY = view.panX + dx, view.panY + dy
  else
    view.yaw = (view.yaw + dx * 0.8) % 360
    view.pitch = clamp(view.pitch + dy * 0.6, -89, 89)
  end
  changed()
end

local function zoomBy(factor)
  view.zoomMul = clamp(view.zoomMul * factor, 0.25, 8)
  changed()
end

---------------------------------------------------------------------------
-- Window

local function saveBounds()
  if not dlg then return end
  local ok, b = pcall(function() return dlg.bounds end)
  if ok and b then prefs.previewBounds = { b.x, b.y, b.width, b.height } end
end

-- Last window position, if it still fits inside the main window.
local function savedBounds()
  local b = prefs.previewBounds
  if not b or not app.window then return nil end
  if b[1] < 0 or b[2] < 0 or b[1] + b[3] > app.window.width or b[2] + b[4] > app.window.height then
    return nil
  end
  return Rectangle(b[1], b[2], b[3], b[4])
end

-- Checkbox that stores its value in prefs[key] and redraws.
local function toggle(d, key, text, selected)
  d:check{ id=key, text=text, selected=selected,
           onclick=function()
             prefs[key] = d.data[key]
             changed()
           end }
end

function P.setup(preferences)
  prefs = preferences
  prefs.show = prefs.show or {}
  if prefs.skin and prefs.skin.hex then
    skinTex = skin.textureFromPNG(skin.fromHex(prefs.skin.hex))
  end
  resetView()
end

function P.isOpen()
  return dlg ~= nil
end

function P.open()
  if dlg then return end
  local d = Dialog{
    title="Armor Preview",
    resizeable=true,
    onclose=function()
      saveBounds()
      dlg, drag = nil, nil
    end,
  }
  dlg = d
  d:canvas{
    id="view", width=240, height=330,
    onpaint=paint,
    onmousedown=onMouseDown,
    onmousemove=onMouseMove,
    onmouseup=function() drag = nil end,
    onwheel=function(ev) zoomBy(ev.deltaY > 0 and 1 / 1.12 or 1.12) end,
    ontouchmagnify=function(ev) zoomBy(1 + ev.magnification) end,
    ondblclick=function() resetView() end,
  }
  d:newrow()
  for i, piece in ipairs(layout.PIECES) do
    d:check{ id=piece.id, text=piece.name, selected=prefs.show[piece.id] ~= false,
             onclick=function()
               prefs.show[piece.id] = d.data[piece.id]
               changed()
             end }
    if i == 2 then d:newrow() end
  end
  d:newrow()
  d:button{ text="Front", onclick=function() resetView(PRESETS.front) end }
  d:button{ text="Side",  onclick=function() resetView(PRESETS.side) end }
  d:button{ text="Back",  onclick=function() resetView(PRESETS.back) end }
  d:button{ text="3/4",   onclick=function() resetView(PRESETS.angled) end }

  d:separator{ text="Player" }
  toggle(d, "showPlayer", "Show player", prefs.showPlayer == true)
  d:combobox{ id="arms", options=ARMS, option=ARMS[prefs.slim and 2 or 1],
              onchange=function()
                prefs.slim = d.data.arms == ARMS[2]
                changed()
              end }
  d:newrow()
  d:entry{ id="skinName", text=prefs.skinName or "" }
  d:button{ text="Get Skin", onclick=getSkin }
  d:newrow()
  d:file{ id="skinFile", title="Choose a skin", open=true, filetypes={ "png" },
          onchange=function() loadSkinFile(d.data.skinFile) end }
  d:newrow()
  d:label{ id="skinStatus", text="Skin: " .. skinLabel() }

  d:separator{ text="Display" }
  toggle(d, "shading", "Shading", prefs.shading ~= false)
  toggle(d, "outlines", "Outlines", prefs.outlines == true)
  toggle(d, "lightBackground", "Light background", prefs.lightBackground == true)
  d:newrow()
  d:label{ id="layer1", text="" }
  d:newrow()
  d:label{ id="layer2", text="" }
  d:newrow()
  d:button{ text="Reload from Disk", onclick=function() P.reloadFromDisk() end }
  updateLabels()
  d:show{ wait=false, bounds=savedBounds() }
end

function P.close()
  for timer in pairs(timers) do timer:stop() end
  timers, repaintPending, diskLoadPending = {}, false, false
  if dlg then
    saveBounds()
    local d = dlg
    dlg = nil
    d:close()
  end
end

function P.toggle()
  if dlg then P.close() else P.open() end
end

-- Shows another armor set: { [layer] = path }.
function P.setSet(newSet)
  newSet = newSet or {}
  local function sameLayer(layer)
    return newSet[layer] == set[layer] or compat.samePath(newSet[layer], set[layer])
  end
  local same = sameLayer(layout.LAYER1) and sameLayer(layout.LAYER2)
  set = newSet
  updateLabels()
  if not same then changed() end
end

function P.getSet()
  return set
end

-- A texture's pixels changed (e.g. a stroke in its tab).
function P.invalidate(path)
  local entry = textures[compat.pathKey(path)]
  if entry then entry.dirty = true end
  if compat.samePath(path, set[layout.LAYER1]) or compat.samePath(path, set[layout.LAYER2]) then
    changedSoon()
  end
end

-- Tabs opened/closed or saved: re-check where each texture comes from.
function P.refresh()
  if not dlg then return end
  updateLabels()
  dlg:repaint()
end

function P.reloadFromDisk()
  for _, entry in pairs(textures) do
    if entry.source == "disk" then entry.dirty = true end
  end
  changed()
end

return P
