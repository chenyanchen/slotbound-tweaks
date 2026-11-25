-- Shared tweaks panel: one window (F8) with a tab per feature.
--
-- loader.lua loads this before the features and puts it first in the
-- dispatch order, so it sees input before any feature. Features add a tab:
--
--   T.panel.addTab({
--     id = "<feature name>", title = "Tab title",
--     draw(x, y, w, h, s)         content rect in screen pixels, s = UI scale
--     keypressed(key, scancode, isrepeat)
--     mousepressed(x, y, button)  only called for clicks inside the content rect
--     onShow()                    tab became visible
--   })
--
-- While the panel is open every key is swallowed; mouse clicks are swallowed
-- only when they land on the panel.

return function(T)
  local TOGGLE_KEY = "f8"
  local P = {
    open = false,
    tabs = {},
    cfg = T.config.load("panel", { tab = "" }),
    swallowRelease = {},
    hit = {},
  }
  T.panel = P

  local function inside(r, x, y)
    return r and x >= r[1] and y >= r[2] and x < r[1] + r[3] and y < r[2] + r[4]
  end
  P.inside = inside

  local function activeTab()
    for _, t in ipairs(P.tabs) do
      if t.id == P.cfg.tab then return t end
    end
    return P.tabs[1]
  end
  P.activeTab = activeTab

  local function call(tab, method, ...)
    local fn = tab and tab[method]
    if not fn then return nil end
    local ok, res = pcall(fn, ...)
    if not ok then T.log("panel tab %s.%s: %s", tostring(tab.id), method, tostring(res)) end
    return res
  end

  function P.addTab(tab)
    P.tabs[#P.tabs + 1] = tab
  end

  -- true when the panel is open and showing tab `id`
  function P.isShowing(id)
    local t = activeTab()
    return P.open and t ~= nil and t.id == id
  end

  local function select(tab)
    if not tab then return end
    if P.cfg.tab ~= tab.id then
      P.cfg.tab = tab.id
      T.config.save("panel", P.cfg)
    end
    call(tab, "onShow")
  end

  local function cycle(dir)
    local cur = activeTab()
    for i, t in ipairs(P.tabs) do
      if t == cur then select(P.tabs[(i - 1 + dir) % #P.tabs + 1]); return end
    end
  end

  function P.setOpen(open)
    P.open = open and #P.tabs > 0
    if P.open then call(activeTab(), "onShow") end
  end

  --------------------------------------------------------------------------
  -- layout / drawing
  --------------------------------------------------------------------------
  -- UI scale and panel rect for the current window size.
  function P.layout()
    local sw, sh = love.graphics.getDimensions()
    local s = math.max(0.5, math.min(sh / 1080, sw / 1100))
    local w, h = math.floor(980 * s), math.floor(680 * s)
    return math.floor((sw - w) / 2), math.max(0, math.floor((sh - h) / 2)), w, h, s
  end

  P.colors = {
    bg = { 0.06, 0.06, 0.1, 0.95 },
    gold = { 0.95, 0.78, 0.3, 1 },
    text = { 1, 1, 1, 1 },
    dim = { 0.75, 0.75, 0.82, 1 },
    button = { 1, 1, 1, 0.15 },
    warn = { 1, 0.55, 0.45, 1 },
    ok = { 0.6, 0.85, 0.6, 1 },
  }

  -- a filled button with centered text; returns its rect
  function P.button(r, label, font, active, enabled)
    local g = love.graphics
    if active then g.setColor(0.95, 0.78, 0.3, 0.9)
    else g.setColor(1, 1, 1, enabled == false and 0.06 or 0.15) end
    g.rectangle("fill", r[1], r[2], r[3], r[4], math.min(6, r[4] / 4))
    g.setFont(font)
    if active then g.setColor(0.08, 0.08, 0.1, 1) else g.setColor(1, 1, 1, enabled == false and 0.35 or 1) end
    g.printf(label, r[1], math.floor(r[2] + (r[4] - font:getHeight()) / 2), r[3], "center")
    return r
  end

  function P.draw()
    if not P.open then return end
    local g = love.graphics
    local x, y, w, h, s = P.layout()
    local pad = math.floor(18 * s)
    local C = P.colors
    P.rect = { x, y, w, h }
    P.hit = {}

    g.push("all")
    g.origin(); g.setCanvas(); g.setShader(); g.setScissor()
    g.setColor(C.bg); g.rectangle("fill", x, y, w, h, 12 * s)
    g.setColor(C.gold); g.setLineWidth(2 * s); g.rectangle("line", x, y, w, h, 12 * s)

    -- tab bar
    local tabFont = T.font(20 * s)
    local tx, ty, th = x + pad, y + pad, math.floor(36 * s)
    local cur = activeTab()
    for i, t in ipairs(P.tabs) do
      local tw = tabFont:getWidth(t.title) + 32 * s
      P.hit["tab" .. i] = P.button({ tx, ty, tw, th }, t.title, tabFont, t == cur)
      tx = tx + tw + 8 * s
    end
    g.setFont(T.font(14 * s)); g.setColor(C.dim)
    g.printf("Tab switch   F8/Esc close", x + pad, ty + (th - T.font(14 * s):getHeight()) / 2, w - pad * 2, "right")
    g.setColor(1, 1, 1, 0.12); g.rectangle("fill", x + pad, ty + th + 8 * s, w - pad * 2, 1)

    -- footer: leaderboard status (shared by every tab)
    local footFont = T.font(15 * s)
    local fy = y + h - pad - footFont:getHeight()
    g.setFont(footFont)
    if T.tainted then
      g.setColor(C.warn)
      g.print("Session modified: leaderboard submissions disabled until the game restarts.", x + pad, fy)
    else
      g.setColor(C.ok)
      g.print("Nothing changed yet: leaderboard submissions unaffected.", x + pad, fy)
    end

    -- content
    local cy = ty + th + 18 * s
    P.content = { x + pad, cy, w - pad * 2, fy - 10 * s - cy }
    if cur then
      g.setColor(1, 1, 1, 1)
      call(cur, "draw", P.content[1], P.content[2], P.content[3], P.content[4], s)
    end
    g.pop()
  end

  --------------------------------------------------------------------------
  -- input
  --------------------------------------------------------------------------
  function P.keypressed(key, scancode, isrepeat)
    if key == TOGGLE_KEY then P.setOpen(not P.open); return true end
    if not P.open then return false end
    if key == "escape" then P.setOpen(false)
    elseif key == "tab" then cycle(love.keyboard.isDown("lshift", "rshift") and -1 or 1)
    else call(activeTab(), "keypressed", key, scancode, isrepeat) end
    return true -- swallow all keys while the panel is open
  end

  function P.mousepressed(x, y, button)
    if not P.open or not inside(P.rect, x, y) then return false end
    P.swallowRelease[button] = true
    if button == 1 then
      for i, t in ipairs(P.tabs) do
        if inside(P.hit["tab" .. i], x, y) then select(t); return true end
      end
    end
    if inside(P.content, x, y) then call(activeTab(), "mousepressed", x, y, button) end
    return true
  end

  function P.mousereleased(_, _, button)
    if P.swallowRelease[button] then P.swallowRelease[button] = nil; return true end
    return false
  end

  return P
end
