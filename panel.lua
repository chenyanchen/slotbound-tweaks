-- Shared tweaks panel: one window (F8) with a tab per feature.
--
-- loader.lua loads this before the features and puts it first in the
-- dispatch order, so it sees input before any feature. Features add a tab:
--
--   T.panel.addTab({
--     id = "<feature name>", title = function() return T.tr("tab.<name>") end, -- or a string
--     draw(x, y, w, h, s)         content rect in screen pixels, s = UI scale
--     keypressed(key, scancode, isrepeat)
--     mousepressed(x, y, button)  only called for clicks inside the content rect
--     onShow()                    tab became visible
--   })
--
-- Shared UI helpers:
--   T.panel.button(r, label, font, active, enabled)
--   T.panel.stepper(opts)         unified -/+ buttons with click and hold-to-repeat
--   T.panel.hold(opts)            shared hold-to-repeat for keys or mouse buttons
--   T.panel.stopHold()
--
-- While the panel is open every key is swallowed; mouse clicks are swallowed
-- only when they land on the panel.

return function(T)
  local TOGGLE_KEY = "f8"
  local REPEAT_DELAY, REPEAT_FAST, REPEAT_FASTEST, ACCEL_AFTER = 0.35, 0.07, 0.03, 1.5
  local P = {
    open = false,
    tabs = {},
    cfg = T.config.load("panel", { tab = "" }),
    swallowRelease = {},
    hit = {},
    steppers = {},
    _hold = nil,
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

  --------------------------------------------------------------------------
  -- hold-to-repeat (shared by steppers and held navigation/adjustment keys)
  --------------------------------------------------------------------------
  function P.stopHold()
    local h = P._hold
    if not h then return end
    P._hold = nil
    if h.onStop then
      local ok, err = pcall(h.onStop)
      if not ok then T.log("panel hold onStop: %s", tostring(err)) end
    end
  end

  -- Repeat `opts.step(accel)` while `opts.mouse` or `opts.key` stays held.
  -- Returning false from `step` stops the hold. `opts.onStop` runs once when
  -- the hold ends (e.g. to flush a deferred save).
  function P.hold(opts)
    P.stopHold()
    if not P.open or type(opts) ~= "table" or type(opts.step) ~= "function" then return end
    P._hold = {
      tab = activeTab(),
      mouse = opts.mouse,
      key = opts.key,
      id = opts.id,
      dir = opts.dir,
      step = opts.step,
      onStop = opts.onStop,
      t = 0,
      nextAt = REPEAT_DELAY,
    }
  end

  function P.isHeld(id, dir)
    local h = P._hold
    return h ~= nil and id ~= nil and h.tab == activeTab() and h.id == id and (dir == nil or h.dir == dir)
  end

  function P.update(dt)
    local h = P._hold
    if not h then return end
    local down = (h.mouse and love.mouse.isDown(h.mouse)) or (h.key and love.keyboard.isDown(h.key))
    if not P.open or activeTab() ~= h.tab or not down then P.stopHold(); return end
    h.t = h.t + dt
    local fires = 0
    while h.t >= h.nextAt and fires < 8 do
      fires = fires + 1
      local accel = h.t > ACCEL_AFTER
      h.nextAt = h.nextAt + (accel and REPEAT_FASTEST or REPEAT_FAST)
      local ok, cont = pcall(h.step, accel)
      if not ok then
        T.log("panel hold step: %s", tostring(cont))
        P.stopHold()
        return
      end
      if cont == false or P._hold ~= h then
        if P._hold == h then P.stopHold() end
        return
      end
    end
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
      P.stopHold()
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
    if not P.open then P.stopHold()
    else call(activeTab(), "onShow") end
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

  -- Draw a unified -/+ stepper pair and register its hit rects for click and
  -- hold-to-repeat handling.
  -- opts:
  --   id                   unique key within the active tab (for held highlight)
  --   x, y, w, h           rect of each button (h defaults to w)
  --   gap                  space between - and + (default: 4)
  --   font                 font for "-" and "+"
  --   canMinus, canPlus    optional booleans (false dims the button)
  --   onStep(dir, accel)   called with dir = -1 | 1; return false to stop hold
  --   onStop()             optional; called when the hold ends
  function P.stepper(opts)
    local bw, bh = opts.w, opts.h or opts.w
    local gap = opts.gap or 4
    local r1 = { opts.x, opts.y, bw, bh }
    local r2 = { opts.x + bw + gap, opts.y, bw, bh }
    local minusActive = P.isHeld(opts.id, -1) and opts.canMinus ~= false
    local plusActive = P.isHeld(opts.id, 1) and opts.canPlus ~= false
    P.button(r1, "-", opts.font, minusActive, opts.canMinus)
    P.button(r2, "+", opts.font, plusActive, opts.canPlus)
    P.steppers[#P.steppers + 1] = {
      id = opts.id,
      minus = r1,
      plus = r2,
      onStep = opts.onStep,
      onStop = opts.onStop,
    }
    return r1, r2
  end

  -- The game draws its own pixel cursor (global cursorImage) at the end of
  -- love.draw, so the panel, drawn later at present time, covers it. Draw it
  -- again on top, the way the game does.
  local function drawGameCursor()
    local img = rawget(_G, "cursorImage")
    if type(img) ~= "userdata" or rawget(_G, "hideCursor") then return end
    -- the game's visibility check (gamepad mode, mouse focus, ...); its
    -- optional arguments are not mouse coordinates, the defaults are what we want
    local shown = rawget(_G, "__slotCursorShown")
    if type(shown) == "function" then
      local ok, vis = pcall(shown)
      if ok and not vis then return end
    end
    local mx, my = love.mouse.getPosition()
    local sc = tonumber(rawget(_G, "screenScale")) or 1
    local hx = tonumber(rawget(_G, "cursorHotspotX")) or 0
    local hy = tonumber(rawget(_G, "cursorHotspotY")) or 0
    love.graphics.setShader()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, math.floor(mx - hx * sc), math.floor(my - hy * sc), 0, sc, sc)
  end

  function P.draw()
    if not P.open then return end
    local g = love.graphics
    local x, y, w, h, s = P.layout()
    local pad = math.floor(18 * s)
    local C = P.colors
    P.rect = { x, y, w, h }
    P.hit = {}
    P.steppers = {}

    g.push("all")
    g.origin(); g.setCanvas(); g.setShader(); g.setScissor()
    g.setColor(C.bg); g.rectangle("fill", x, y, w, h, 12 * s)
    g.setColor(C.gold); g.setLineWidth(2 * s); g.rectangle("line", x, y, w, h, 12 * s)

    -- tab bar
    local tabFont = T.font(20 * s)
    local tx, ty, th = x + pad, y + pad, math.floor(36 * s)
    local cur = activeTab()
    for i, t in ipairs(P.tabs) do
      local title = type(t.title) == "function" and t.title() or tostring(t.title)
      local tw = tabFont:getWidth(title) + 32 * s
      P.hit["tab" .. i] = P.button({ tx, ty, tw, th }, title, tabFont, t == cur)
      tx = tx + tw + 8 * s
    end
    g.setFont(T.font(14 * s)); g.setColor(C.dim)
    g.printf(T.tr("panel.hint"), x + pad, ty + (th - T.font(14 * s):getHeight()) / 2, w - pad * 2, "right")
    g.setColor(1, 1, 1, 0.12); g.rectangle("fill", x + pad, ty + th + 8 * s, w - pad * 2, 1)

    -- footer: leaderboard status (shared by every tab)
    local footFont = T.font(15 * s)
    local fy = y + h - pad - footFont:getHeight()
    g.setFont(footFont)
    if T.tainted then
      g.setColor(C.warn)
      g.print(T.tr("panel.tainted"), x + pad, fy)
    else
      g.setColor(C.ok)
      g.print(T.tr("panel.clean"), x + pad, fy)
    end

    -- content
    local cy = ty + th + 18 * s
    P.content = { x + pad, cy, w - pad * 2, fy - 10 * s - cy }
    if cur then
      g.setColor(1, 1, 1, 1)
      call(cur, "draw", P.content[1], P.content[2], P.content[3], P.content[4], s)
    end
    pcall(drawGameCursor)
    g.pop()
  end

  --------------------------------------------------------------------------
  -- input
  --------------------------------------------------------------------------
  local function triggerStepper(st, dir, button)
    if type(st.onStep) ~= "function" then return end
    local ok, cont = pcall(st.onStep, dir, false)
    if not ok then T.log("panel stepper %s: %s", tostring(st.id), tostring(cont)); return end
    if cont ~= false then
      P.hold({
        mouse = button,
        id = st.id,
        dir = dir,
        step = function(accel) return st.onStep(dir, accel) end,
        onStop = st.onStop,
      })
    elseif st.onStop then
      local okS, errS = pcall(st.onStop)
      if not okS then T.log("panel stepper onStop: %s", tostring(errS)) end
    end
  end

  function P.keypressed(key, scancode, isrepeat)
    if key == TOGGLE_KEY then P.setOpen(not P.open); return true end
    if not P.open then return false end
    if isrepeat and P._hold and P._hold.key == key then return true end
    if key == "escape" then P.setOpen(false)
    elseif key == "tab" then cycle(love.keyboard.isDown("lshift", "rshift") and -1 or 1)
    else call(activeTab(), "keypressed", key, scancode, isrepeat) end
    return true -- swallow all keys while the panel is open
  end

  function P.mousepressed(x, y, button)
    if not P.open or not inside(P.rect, x, y) then return false end
    P.swallowRelease[button] = true
    P.stopHold()
    if button == 1 then
      for i, t in ipairs(P.tabs) do
        if inside(P.hit["tab" .. i], x, y) then select(t); return true end
      end
      if inside(P.content, x, y) then
        for _, st in ipairs(P.steppers) do
          if inside(st.minus, x, y) then triggerStepper(st, -1, button); return true end
          if inside(st.plus, x, y) then triggerStepper(st, 1, button); return true end
        end
      end
    end
    if inside(P.content, x, y) then call(activeTab(), "mousepressed", x, y, button) end
    return true
  end

  function P.mousereleased(_, _, button)
    if P._hold and P._hold.mouse == button then P.stopHold() end
    if P.swallowRelease[button] then P.swallowRelease[button] = nil; return true end
    return false
  end

  return P
end
