-- Load this file from ~/.hammerspoon/init.lua; see README.md.
local source = debug.getinfo(1,"S").source
assert(source:sub(1,1)=="@", "Load this controller from its file")
local root = source:sub(2):gsub("\\","/"):match("^(.*)/[^/]+$")
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
if _G.HCI2000Controller then
  _G.HCI2000Controller:shutdown("Controller reloaded")
end
for _, name in ipairs({"controller","config","model","storage","materials","allocation"}) do
  package.loaded["study."..name] = nil
end
_G.HCI2000Controller = require("study.controller").new(hs,root)
_G.HCI2000Controller:guard(function()_G.HCI2000Controller:install()end)
-- Reload Config destroys the Lua environment: use the real synchronous hook.
-- Preserve unrelated user shutdown behavior without nesting old HCI hooks.
local previous = hs.shutdownCallback
if previous == _G.HCI2000ShutdownHook then previous = _G.HCI2000PreviousShutdown end
_G.HCI2000PreviousShutdown = previous
local current = _G.HCI2000Controller
local hook = function()
  local ok, err = pcall(function() current:shutdown("Hammerspoon shutdown/config reload") end)
  if not ok then print("[HCI2000] Shutdown cleanup error: "..tostring(err)) end
  if previous then
    local otherOK, otherError = pcall(previous)
    if not otherOK then print("[HCI2000] Previous shutdown callback error: "..tostring(otherError)) end
  end
end
_G.HCI2000ShutdownHook = hook
hs.shutdownCallback = hook
