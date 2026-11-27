-- Languages: the panel follows the language chosen in the game.
--
--   T.lang()            the game's current language code ("en", "zh", "zh-Hant", "ja", ...)
--   T.gameText(key)     a string from the game's own language tables (current
--                       language, then English), or nil. Use it for anything
--                       the game names: units, items, cores, imprints, grades...
--   T.tr(key, ...)      the tweaks' own UI text from lang/<code>.lua (falling
--                       back to lang/en.lua, then the key), string.format'ed
--                       with the arguments. Words the game already has (see
--                       GAME_WORDS) come from the game in its current language.
--   T.font(px)          a font for UI text in the current language
--
-- Everything is looked up when drawn, so switching the game's language
-- updates the panel immediately.
--
-- Fonts: LÖVE's default font covers Latin scripts only. For each language
-- the primary font is the first of (default font, the game's TrueType fonts,
-- a few system fonts) that can draw a sample of that language's text; the
-- others are attached as fallbacks for any missing glyphs.

return function(T)
  -- tweaks keys whose text is a word the game already translates
  local GAME_WORDS = {
    items = "collection_tab_items",
    cores = "collection_tab_cores",
    units = "collection_tab_units",
    shop = "section_shop",
  }
  -- last-resort fonts with wide coverage (e.g. Cyrillic, which the game's
  -- TrueType fonts lack); missing files are skipped
  local SYSTEM_FONTS = {
    "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
    "/Library/Fonts/Arial Unicode.ttf",
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "C:/Windows/Fonts/arial.ttf",
    "C:/Windows/Fonts/segoeui.ttf",
  }

  function T.lang()
    local l = rawget(_G, "currentGameLang")
    return type(l) == "string" and l ~= "" and l or "en"
  end

  local function gameTable(lang)
    local L = package.loaded["src.data.language"]
    local t = type(L) == "table" and L[lang]
    return type(t) == "table" and t or nil
  end

  function T.gameText(key)
    local cur, en = gameTable(T.lang()), gameTable("en")
    local s = cur and cur[key]
    if type(s) ~= "string" then s = en and en[key] end
    return type(s) == "string" and s or nil
  end

  local own = {}
  local function ownTable(lang)
    if own[lang] == nil then
      local ok, t = pcall(T.loadLua, "lang/" .. lang .. ".lua")
      own[lang] = ok and type(t) == "table" and t or false
      if not ok and lang == "en" then T.log("i18n: lang/en.lua failed: %s", tostring(t)) end
    end
    return own[lang] or nil
  end

  function T.tr(key, ...)
    local lang = T.lang()
    local s
    local gk = GAME_WORDS[key]
    if gk then
      local g = gameTable(lang)
      s = g and g[gk]
    end
    if type(s) ~= "string" then
      local t = ownTable(lang)
      s = t and t[key]
    end
    if type(s) ~= "string" then
      local t = ownTable("en")
      s = t and t[key]
    end
    if type(s) ~= "string" then s = key end
    if select("#", ...) > 0 then
      local ok, r = pcall(string.format, s, ...)
      if ok then s = r end
    end
    return s
  end

  --------------------------------------------------------------------------
  -- fonts
  --------------------------------------------------------------------------
  -- candidate sources: { kind = "default" | "game" | "file", path }
  local sources
  local function fontSources()
    if sources then return sources end
    local list = { { kind = "default" } }
    -- the game's TrueType/OpenType fonts, found under its font directory
    local ui = rawget(_G, "ui")
    local fp = type(ui) == "table" and type(ui.fontPath) == "string" and ui.fontPath
    local dir = fp and fp:match("^(.*)/[^/]*$")
    if not dir then return list end -- the game hasn't set up its fonts yet; retry later
    local found = {}
    local function scan(d, depth)
      if depth > 2 then return end
      for _, name in ipairs(love.filesystem.getDirectoryItems(d)) do
        local p = d .. "/" .. name
        local info = love.filesystem.getInfo(p)
        if info and info.type == "directory" then scan(p, depth + 1)
        elseif name:lower():match("%.[ot]tf$") then found[#found + 1] = p end
      end
    end
    pcall(scan, dir, 0)
    table.sort(found)
    for _, p in ipairs(found) do list[#list + 1] = { kind = "game", path = p } end
    for _, p in ipairs(SYSTEM_FONTS) do
      local f = io.open(p, "rb")
      if f then
        local bytes = f:read("*a"); f:close()
        local ok, data = pcall(love.filesystem.newFileData, bytes, p:match("[^/]*$"))
        if ok then list[#list + 1] = { kind = "file", path = p, data = data } end
      end
    end
    sources = list
    return list
  end

  local function newFont(src, px)
    local ok, f
    if src.kind == "default" then ok, f = pcall(love.graphics.newFont, px)
    elseif src.kind == "game" then ok, f = pcall(love.graphics.newFont, src.path, px)
    else
      ok, f = pcall(love.font.newTrueTypeRasterizer, src.data, px)
      if ok then ok, f = pcall(love.graphics.newFont, f) end
    end
    if not ok then return nil end
    if src.kind == "game" then f:setFilter("nearest", "nearest") end -- the game's fonts are pixel fonts
    return f
  end

  -- text typical of a language: the game's names for a few things, plus our
  -- own translations of the tab titles
  local function sample(lang)
    local parts = {}
    local g = gameTable(lang)
    for _, k in ipairs({ "collection_tab_items", "collection_tab_cores", "collection_tab_units",
      "section_shop", "grade.label.normal", "grade.label.legendary", "settings_language" }) do
      if g and type(g[k]) == "string" then parts[#parts + 1] = g[k] end
    end
    local t = ownTable(lang)
    for _, k in ipairs({ "tab.symbol_weights", "tab.unit_grades", "tab.imprints" }) do
      if t and type(t[k]) == "string" then parts[#parts + 1] = t[k] end
    end
    return (table.concat(parts, " "):gsub("%c", " "))
  end

  -- per language: the order of sources, primary first
  local orders = {}
  local function sourceOrder(lang)
    local srcs = fontSources()
    if orders[lang] and orders[lang].n == #srcs then return orders[lang].list end
    local text, primary = sample(lang), 1
    for i, src in ipairs(srcs) do
      local f = newFont(src, 20)
      local ok, has = false, false
      if f then ok, has = pcall(f.hasGlyphs, f, text) end
      if ok and has then primary = i; break end
    end
    local list = { srcs[primary] }
    for i, src in ipairs(srcs) do if i ~= primary then list[#list + 1] = src end end
    orders[lang] = { n = #srcs, list = list }
    if #srcs > 1 then
      T.log("i18n: %s font %s", lang, tostring(srcs[primary].path or "default"))
    end
    return list
  end

  local fonts = {}
  function T.font(px)
    local lang = T.lang()
    local list = sourceOrder(lang)
    if list[1].kind == "game" then
      px = math.max(10, math.floor(px / 10 + 0.5) * 10) -- the game's pixel fonts: whole multiples of 10 px
    else
      px = math.max(10, math.floor(px + 0.5))
    end
    local key = lang .. "#" .. #list .. "@" .. px
    local f = fonts[key]
    if not f then
      local made = {}
      for _, src in ipairs(list) do
        local font = newFont(src, px)
        if font then made[#made + 1] = font end
      end
      f = made[1] or love.graphics.newFont(px)
      if #made > 1 then pcall(f.setFallbacks, f, unpack(made, 2)) end
      fonts[key] = f
    end
    return f
  end

  return T
end
