-- Minecraft Armor Tools for Aseprite
--
-- Detects armor textures when they're opened, adds body-part grids, pairs
-- Layer 1 (humanoid) with Layer 2 (humanoid_leggings) and shows both on a
-- live 3D preview.

-- Aseprite keeps one Lua state for every extension and never clears
-- package.loaded, so after an update require() would hand back the
-- previous version's modules. Drop them before loading.
local MODULES = { "mca_compat", "mca_layout", "mca_render", "mca_grids", "mca_preview" }
local function forgetModules()
  for _, name in ipairs(MODULES) do
    package.loaded[name] = nil
    package.loaded["minecraft-armor-tools/" .. name] = nil
  end
end
forgetModules()

local compat = require("mca_compat")
local layout = require("mca_layout")
local grids = require("mca_grids")
local preview = require("mca_preview")

-- Files are tracked by compat.pathKey(path) so the same file always gets
-- the same key on Windows, macOS and Linux.
local key = compat.pathKey

local prefs
local armor = {}         -- [key] = { layer=, path=, partner= }: files treated as armor this session
local asked = {}         -- [key] = true once handled this session
local watched = {}       -- [sprite.id] = { sprite=, path=, codes={} }
local appListeners = {}
local pendingTimers = {}
local savingPartner = false

-- Runs fn shortly after the current event, outside of Aseprite's handlers.
local function defer(fn)
  local timer
  timer = Timer{
    interval=0.05,
    ontick=function()
      timer:stop()
      pendingTimers[timer] = nil
      fn()
    end,
  }
  pendingTimers[timer] = true
  timer:start()
end

-- Whether the sprite is backed by a file on disk (not a new unsaved one).
-- Sprite.hasAssociatedFile only exists from Aseprite 1.3.18.
local function hasFile(sprite)
  return app.fs.isFile(sprite.filename)
end

local function setFor(path)
  local info = armor[key(path)]
  if not info then return nil end
  local s = { [info.layer]=info.path }
  if info.partner then s[layout.otherLayer(info.layer)] = info.partner end
  return s
end

local function showSetOf(path)
  local s = setFor(path)
  if s then preview.setSet(s) end
end

-- Live updates: re-render the preview whenever the texture changes.
local function watch(sprite)
  if watched[sprite.id] then return end
  local entry = { sprite=sprite, path=sprite.filename, codes={} }
  local function onChange()
    preview.invalidate(sprite.filename)
  end
  entry.codes[#entry.codes + 1] = sprite.events:on('change', onChange)
  entry.codes[#entry.codes + 1] = compat.on(sprite.events, 'layervisibility', onChange)
  entry.codes[#entry.codes + 1] = sprite.events:on('filenamechange', function()
    -- "Save As" moved the file: carry the armor info over to the new path.
    local old, new = entry.path, sprite.filename
    entry.path = new
    local info = armor[key(old)]
    if not info then return end
    armor[key(old)] = nil
    info.path = new
    info.partner = layout.partnerPath(new)
    armor[key(new)] = info
    if hasFile(sprite) then prefs.files[key(new)] = info.layer end
    asked[key(new)] = true
    showSetOf(new)
  end)
  watched[sprite.id] = entry
end

local function unwatch(sprite)
  local entry = watched[sprite.id]
  if not entry then return end
  for _, code in ipairs(entry.codes) do sprite.events:off(code) end
  watched[sprite.id] = nil
end

local function applyGrids(sprite, layer)
  if prefs.gridsEnabled ~= false then
    grids.apply(sprite, layer, prefs.gridPieces)
  end
end

-- Treats an open sprite as an armor texture of the given layer.
local function activate(sprite, layer, opts)
  opts = opts or {}
  local path = sprite.filename
  local partner = layout.partnerPath(path)
  local partnerLayer = layout.otherLayer(layer)
  armor[key(path)] = { layer=layer, path=path, partner=partner }
  asked[key(path)] = true
  if hasFile(sprite) then prefs.files[key(path)] = layer end
  applyGrids(sprite, layer)
  watch(sprite)

  if partner then
    local other = layout.findOpenSprite(partner)
    local function registerPartner()
      armor[key(partner)] = { layer=partnerLayer, path=partner, partner=path }
      asked[key(partner)] = true
      prefs.files[key(partner)] = partnerLayer
    end
    if not other and opts.openPartner and app.fs.isFile(partner) then
      -- Register first so opening it doesn't trigger another prompt.
      registerPartner()
      local current = app.sprite
      other = app.open(partner)
      if compat.isOpen(current) then app.sprite = current end
    end
    if other then
      registerPartner()
      if not grids.hasGrids(other) then applyGrids(other, partnerLayer) end
      watch(other)
    end
  end

  showSetOf(path)
  if opts.openPreview then preview.open() end
end

local function deactivate(sprite)
  local path = sprite.filename
  grids.remove(sprite)
  unwatch(sprite)
  armor[key(path)] = nil
  prefs.files[key(path)] = nil
  asked[key(path)] = true
end

-- "Work on this as armor?" prompt.
local function prompt(sprite)
  if not compat.isOpen(sprite) then return end
  if not layout.isArmorSize(sprite.width, sprite.height) then
    app.alert{ title="Minecraft Armor",
               text={ string.format("This canvas is %dx%d.", sprite.width, sprite.height),
                      "Armor textures are 64x32 (or an HD multiple like 128x64)." } }
    return
  end
  local path = sprite.filename
  local name = app.fs.fileName(path)
  local guessed = layout.classify(path) or (armor[key(path)] and armor[key(path)].layer) or layout.LAYER1
  local options = { layout.LAYER_LABELS[layout.LAYER1], layout.LAYER_LABELS[layout.LAYER2] }
  local partner = layout.partnerPath(path)
  local canOpenPartner = partner and app.fs.isFile(partner) and not layout.findOpenSprite(partner)

  local dlg = Dialog{ title="Minecraft Armor" }
  dlg:label{ text=string.format("%s looks like a Minecraft armor texture (%dx%d).",
                                name, sprite.width, sprite.height) }
  dlg:newrow()
  dlg:label{ text="Work on it as an armor piece?" }
  dlg:combobox{ id="layer", label="Texture", options=options,
                option=options[guessed == layout.LAYER2 and 2 or 1] }
  if canOpenPartner then
    local partnerFolder = app.fs.fileName(app.fs.filePath(partner))
    dlg:check{ id="openPartner", label="Matching file",
               text="Also open " .. partnerFolder .. "/" .. app.fs.fileName(partner),
               selected=true }
  end
  dlg:check{ id="openPreview", label="Preview", text="Open the 3D preview", selected=true }
  dlg:separator()
  dlg:button{ id="yes", text="Work as Armor", focus=true }
  dlg:button{ id="no", text="Not Now" }
  dlg:button{ id="never", text="Never for This File" }
  dlg:show()

  local data = dlg.data
  if data.yes then
    local layer = (data.layer == options[2]) and layout.LAYER2 or layout.LAYER1
    activate(sprite, layer, { openPartner=data.openPartner, openPreview=data.openPreview })
  elseif data.never then
    prefs.files[key(path)] = "never"
  end
end

local function onSiteChange()
  local sprite = app.sprite
  if not sprite then return end
  local path = sprite.filename
  local k = key(path)

  if armor[k] then
    -- A file handled earlier may have been closed and reopened.
    if not watched[sprite.id] then
      local layer = armor[k].layer
      defer(function()
        if compat.isOpen(sprite) and not grids.hasGrids(sprite) then applyGrids(sprite, layer) end
      end)
      watch(sprite)
    end
    showSetOf(path)
    return
  end

  preview.refresh()
  if asked[k] or not layout.isArmorSize(sprite.width, sprite.height) then return end
  asked[k] = true
  if not app.isUIAvailable then return end

  local remembered = prefs.files[k]
  if remembered == "never" then return end
  if remembered == layout.LAYER1 or remembered == layout.LAYER2 then
    defer(function()
      if compat.isOpen(sprite) then activate(sprite, remembered) end
    end)
  else
    defer(function() prompt(sprite) end)
  end
end

-- Optional: saving one texture of a set also saves the other open one.
local function onAfterCommand(ev)
  if ev.name ~= "SaveFile" or savingPartner or not prefs.saveBoth then return end
  local sprite = app.sprite
  local info = sprite and armor[key(sprite.filename)]
  local other = info and layout.findOpenSprite(info.partner)
  if other and other.isModified then
    savingPartner = true
    other:saveAs(other.filename)
    savingPartner = false
  end
  preview.refresh()
end

local function saveArmorSet()
  local s = preview.getSet()
  local saved = 0
  for _, layer in ipairs(layout.LAYERS) do
    local sprite = layout.findOpenSprite(s[layer])
    if sprite and sprite.isModified then
      sprite:saveAs(sprite.filename)
      saved = saved + 1
    end
  end
  preview.refresh()
  compat.tip(saved == 0 and "Armor set: nothing to save" or ("Armor set: saved " .. saved .. " file(s)"))
end

local function gridsDialog()
  local dlg = Dialog{ title="Armor Grids" }
  dlg:check{ id="enabled", text="Show body-part grids on armor textures",
             selected=prefs.gridsEnabled ~= false }
  dlg:separator{ text="Pieces" }
  for _, piece in ipairs(layout.PIECES) do
    dlg:check{ id=piece.id, text=piece.name, selected=prefs.gridPieces[piece.id] ~= false }
    dlg:newrow()
  end
  dlg:separator()
  dlg:button{ id="ok", text="Apply", focus=true }
  dlg:button{ id="cancel", text="Cancel" }
  dlg:show()

  local data = dlg.data
  if not data.ok then return end
  prefs.gridsEnabled = data.enabled
  for _, piece in ipairs(layout.PIECES) do
    prefs.gridPieces[piece.id] = data[piece.id]
  end
  local active = app.sprite
  for _, sprite in ipairs(app.sprites) do
    local info = armor[key(sprite.filename)]
    if info then
      if prefs.gridsEnabled then grids.apply(sprite, info.layer, prefs.gridPieces)
      else grids.remove(sprite) end
    end
  end
  if compat.isOpen(active) then app.sprite = active end
end

-- Lets tests/test_init.lua drive the armor flow without dialogs.
if MCA_EXPOSE_FOR_TESTS then
  MCA_TEST = { activate=activate, deactivate=deactivate, saveArmorSet=saveArmorSet,
               armor=armor, onSiteChange=onSiteChange }
end

function init(plugin)
  if app.apiVersion < compat.MIN_API_VERSION then
    if app.isUIAvailable then
      app.alert{ title="Minecraft Armor Tools",
                 text="This extension needs Aseprite " .. compat.MIN_VERSION_LABEL .. " or newer." }
    end
    return
  end

  prefs = plugin.preferences
  prefs.files = prefs.files or {}
  prefs.gridPieces = prefs.gridPieces or {}
  preview.setup(prefs)

  plugin:newMenuGroup{ id="mca_menu", title="Minecraft Armor", group="view_canvas_helpers" }

  plugin:newCommand{
    id="MinecraftArmorPreview",
    title="3D Armor Preview",
    group="mca_menu",
    onclick=function() preview.toggle() end,
    onchecked=function() return preview.isOpen() end,
  }
  plugin:newCommand{
    id="MinecraftArmorWorkAsArmor",
    title="Work on This as Armor...",
    group="mca_menu",
    onclick=function() prompt(app.sprite) end,
    onenabled=function() return app.sprite ~= nil end,
  }
  plugin:newCommand{
    id="MinecraftArmorGrids",
    title="Armor Grids...",
    group="mca_menu",
    onclick=gridsDialog,
  }
  plugin:newCommand{
    id="MinecraftArmorSaveSet",
    title="Save Armor Set",
    group="mca_menu",
    onclick=saveArmorSet,
  }
  plugin:newMenuSeparator{ group="mca_menu" }
  plugin:newCommand{
    id="MinecraftArmorSaveBoth",
    title="Saving One Texture Saves Both",
    group="mca_menu",
    onclick=function() prefs.saveBoth = not prefs.saveBoth end,
    onchecked=function() return prefs.saveBoth == true end,
  }
  plugin:newCommand{
    id="MinecraftArmorStop",
    title="Stop Treating This as Armor",
    group="mca_menu",
    onclick=function() if app.sprite then deactivate(app.sprite) end end,
    onenabled=function() return app.sprite ~= nil and armor[key(app.sprite.filename)] ~= nil end,
  }

  appListeners[#appListeners + 1] = app.events:on('sitechange', onSiteChange)
  appListeners[#appListeners + 1] = app.events:on('aftercommand', onAfterCommand)

  -- A texture may already be open when Aseprite starts.
  if app.isUIAvailable then defer(onSiteChange) end
end

function exit(plugin)
  for _, code in ipairs(appListeners) do app.events:off(code) end
  for _, entry in pairs(watched) do
    if compat.isOpen(entry.sprite) then
      for _, code in ipairs(entry.codes) do pcall(function() entry.sprite.events:off(code) end) end
    end
  end
  for timer in pairs(pendingTimers) do timer:stop() end
  preview.close()
  forgetModules()
end
