-- Loads main.lua the way Aseprite does, runs init(), then drives the
-- "Work as Armor" flow on a copy of a texture set:
--   aseprite -b --script-param src=<src dir> --script-param file=<copy>/humanoid/test_armor.png
--     --script tests/test_init.lua
-- <copy>/humanoid_leggings/ must hold a texture with the same name.
package.path = app.params.src .. "/?.lua;" .. package.path
local ok = true
local function check(cond, msg) print((cond and "ok   " or "FAIL ") .. msg); ok = ok and cond end

local commands, groups = {}, {}
local plugin = {
  name="minecraft-armor-tools", path=app.params.src, preferences={},
}
function plugin:newCommand(t) commands[#commands + 1] = t end
function plugin:newMenuGroup(t) groups[#groups + 1] = t end
function plugin:newMenuSeparator(t) end

MCA_EXPOSE_FOR_TESTS = true
dofile(app.params.src .. "/main.lua")
init(plugin)
check(#groups == 1 and #commands == 6, "registered 1 menu group and 6 commands")
for _, c in ipairs(commands) do
  if c.onenabled then c.onenabled() end
  if c.onchecked then c.onchecked() end
end

-- Opening a texture fires sitechange; in batch mode it must not prompt.
local src = app.params.file
local spr = app.open(src)
check(spr ~= nil, "opened " .. app.fs.fileName(src))
MCA_TEST.onSiteChange()

-- "Work as Armor" with "Also open the matching file".
MCA_TEST.activate(spr, "humanoid", { openPartner=true, openPreview=false })
local partnerPath = app.fs.joinPath(app.fs.filePath(app.fs.filePath(src)), "humanoid_leggings", app.fs.fileName(src))
local partner
for _, s in ipairs(app.sprites) do if s.filename == partnerPath then partner = s end end
check(partner ~= nil, "partner humanoid_leggings/" .. app.fs.fileName(src) .. " opened as a second tab")
check(#spr.slices == 30, "Layer 1 has 30 grid slices (got " .. #spr.slices .. ")")
check(partner and #partner.slices == 12, "Layer 2 has 12 grid slices")
check(plugin.preferences.files[src] == "humanoid", "Layer 1 remembered")
check(plugin.preferences.files[partnerPath] == "humanoid_leggings", "Layer 2 remembered")
check(MCA_TEST.armor[partnerPath] and MCA_TEST.armor[partnerPath].partner == src, "pair linked both ways")

-- Edit both, then Save Armor Set.
app.sprite = spr
app.transaction(function() spr.cels[1].image:drawPixel(0, 0, Color(255, 0, 0)) end)
app.sprite = partner
app.transaction(function() partner.cels[1].image:drawPixel(0, 0, Color(0, 255, 0)) end)
check(spr.isModified and partner.isModified, "both tabs modified")
MCA_TEST.saveArmorSet()
check(not spr.isModified and not partner.isModified, "Save Armor Set saved both tabs")

MCA_TEST.deactivate(spr)
check(#spr.slices == 0, "Stop Treating as Armor removes the grids")
check(plugin.preferences.files[src] == nil, "and forgets the file")

exit(plugin)

-- Updating the extension re-runs main.lua in the same Lua state, where an
-- older version's modules may still be cached; they must be replaced.
local stale = { stale=true }
package.loaded["mca_render"] = stale
package.loaded["mca_preview"] = { stale=true }
dofile(app.params.src .. "/main.lua")
init(plugin)
check(package.loaded["mca_render"] ~= stale and not package.loaded["mca_render"].stale,
      "re-running main.lua (extension update) loads fresh modules")
exit(plugin)

print(ok and "PASS" or "FAILED")
