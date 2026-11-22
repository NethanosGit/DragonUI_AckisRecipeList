-- DragonUI_AckisRecipeList: AckisRecipeList recipes inside DragonUI's Professions window.
--
-- Adds a "Not Learned (Ackis)" group at the end of the recipe list. Its rows are the recipes AckisRecipeList
-- knows about that the character has not learned, sorted by required skill and greyed out. Clicking one shows,
-- in the details pane, what it makes, its reagents and where the recipe is obtained.
--
-- Relies on: DragonUI.Professions (Model.Build / Model.Click / Model.Select / Model.SelectedIndex, List.rows,
-- Details) and AckisRecipeList.private (a one-line bridge added to AckisRecipeList's core.lua).
-- Nothing in DragonUI is modified; its functions are wrapped at runtime.

local DUI = _G.DragonUI
local EXT = _G.DragonUI_AckisRecipeList or {}
_G.DragonUI_AckisRecipeList = EXT
if not (DUI and DUI.Professions and DUI.Professions.Model and DUI.Professions.List) then return end

local P = DUI.Professions
local Model, List = P.Model, P.List

local GHOST_HEADER = -1
local GHOST_COLOR = { 0.55, 0.55, 0.55 }
local MAX_LINES_PER_TYPE = 6

-- ============================================================================
-- SETTINGS AND CACHE (saved variable DragonUI_AckisRecipeListDB)
-- ============================================================================
--   DragonUI_AckisRecipeListDB.items / .names   account-wide item details (see ITEM DATABASE)
--   DragonUI_AckisRecipeListDB.chars[realm-name] per character: settings, learned recipes, categories

local function root()
    local d = _G.DragonUI_AckisRecipeListDB
    if not d then
        d = {}
        _G.DragonUI_AckisRecipeListDB = d
    end
    d.items = d.items or {}
    d.names = d.names or {}
    d.chars = d.chars or {}
    return d
end

local function store()
    local key = (GetRealmName() or "?") .. "-" .. (UnitName("player") or "?")
    local chars = root().chars
    local s = chars[key]
    if not s then
        s = { enabled = true, hideTrivial = false, known = {}, dirty = {} }
        chars[key] = s
    end
    s.known = s.known or {}
    s.dirty = s.dirty or {}
    s.cat = s.cat or {}
    return s
end

local function refreshList()
    if List.frame and _G.TradeSkillFrame and TradeSkillFrame:IsShown() then List.Refresh() end
end

function EXT.GetAckisEnabled() local s = store() return s and s.enabled ~= false end
function EXT.SetAckisEnabled(v) local s = store() if s then s.enabled = v and true or false refreshList() end end
function EXT.GetAckisHideTrivial() local s = store() return s and s.hideTrivial and true or false end
function EXT.SetAckisHideTrivial(v) local s = store() if s then s.hideTrivial = v and true or false refreshList() end end

-- Forget every cached profession; each one is read again the next time its window opens.
function EXT.AckisRescan()
    local s = store()
    if not s then return end
    s.known, s.dirty, s.cat = {}, {}, {}
    refreshList()
end

-- ============================================================================
-- ITEM DATABASE (account-wide, in the same saved variable)
-- ============================================================================
-- Reagent details are kept on disk so the client's item cache is not asked every time:
--   items[id] = { name, icon, quality, sell, buy }   names[name] = id
-- Filled from three places: the reagents of recipes the character knows (a scan reads the real item links),
-- GetItemInfo when the client has the item, and the buy prices of any vendor window the player opens.
-- The 3.3.5a API cannot ask a vendor's prices without visiting it, so "buy" appears once a vendor was seen.

local itemDB = root

local function recordItem(id, name, icon, quality, sell, buy)
    if not (id and name) then return end
    local d = itemDB()
    local e = d.items[id]
    if not e then
        e = {}
        d.items[id] = e
    end
    e.name = name
    e.icon = icon or e.icon
    e.quality = quality or e.quality
    e.sell = sell or e.sell
    e.buy = buy or e.buy
    d.names[name] = id
end

-- id and stored entry for a reagent known by name; asks the client's cache only when the database has nothing.
local function lookupItem(name)
    local d = itemDB()
    local id = d.names[name]
    local e = id and d.items[id]
    if not (e and e.icon) then
        local n, link, quality, _, _, _, _, _, _, tex, sell = GetItemInfo(name)
        local fromLink = link and tonumber(link:match("item:(%d+)"))
        if fromLink then
            recordItem(fromLink, n, tex, quality, sell)
            id, e = fromLink, d.items[fromLink]
        end
    end
    return id, e
end

local seeded = {}   -- recipes whose reagents were stored this session

-- Stores the reagents of a stock recipe: their real links give the item ids the tooltip text lacks.
local function seedReagents(index, name)
    if seeded[name] then return end
    local complete = true
    for r = 1, GetTradeSkillNumReagents(index) do
        local rName, icon = GetTradeSkillReagentInfo(index, r)
        local link = GetTradeSkillReagentItemLink(index, r)
        local id = link and tonumber(link:match("item:(%d+)"))
        if rName and id then
            local _, _, quality, _, _, _, _, _, _, _, sell = GetItemInfo(link)
            recordItem(id, rName, icon, quality, sell)
        else
            complete = false
        end
    end
    if complete then seeded[name] = true end
end

-- Vendor prices: what a merchant asks per single item, stored the first time the window is seen.
local merchant = CreateFrame("Frame")
merchant:RegisterEvent("MERCHANT_SHOW")
merchant:RegisterEvent("MERCHANT_UPDATE")
merchant:SetScript("OnEvent", function()
    for i = 1, GetMerchantNumItems() do
        local name, tex, price, quantity, _, _, extended = GetMerchantItemInfo(i)
        local link = GetMerchantItemLink(i)
        local id = link and tonumber(link:match("item:(%d+)"))
        if id and name and price and price > 0 and not extended then
            recordItem(id, name, tex, nil, nil, math.floor(price / math.max(quantity or 1, 1)))
        end
    end
end)

-- Whatever the character carries or has banked is stored too: crafting materials mostly pass through the bags.
local function storeContainers(bags)
    local d = itemDB()
    for _, bag in ipairs(bags) do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do
            local link = GetContainerItemLink(bag, slot)
            local id = link and tonumber(link:match("item:(%d+)"))
            local e = id and d.items[id]
            if id and not (e and e.icon) then
                local n, _, quality, _, _, _, _, _, _, tex, sell = GetItemInfo(link)
                recordItem(id, n, tex, quality, sell)
            end
        end
    end
end

local BAG_IDS, BANK_IDS = { 0, 1, 2, 3, 4 }, { -1, 5, 6, 7, 8, 9, 10, 11 }
local bagWatch = CreateFrame("Frame")
bagWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
bagWatch:RegisterEvent("BAG_UPDATE")
bagWatch:RegisterEvent("BANKFRAME_OPENED")
local bagDirty, bagWait = false, 0
bagWatch:SetScript("OnEvent", function(_, event)
    if event == "BANKFRAME_OPENED" then
        storeContainers(BANK_IDS)
    else
        bagDirty = true
    end
end)
-- Bag events come in bursts: read the bags once, a moment after the last one.
bagWatch:SetScript("OnUpdate", function(_, elapsed)
    if not bagDirty then return end
    bagWait = bagWait + elapsed
    if bagWait >= 1.5 then
        bagDirty, bagWait = false, 0
        storeContainers(BAG_IDS)
    end
end)

-- /duiarl debug: what the item database holds for the Ackis recipe on show, to find out why an icon is missing.
function EXT.Debug()
    local d = itemDB()
    local count = 0
    for _ in pairs(d.items) do count = count + 1 end
    DEFAULT_CHAT_FRAME:AddMessage("|cff1784d1DragonUI_AckisRecipeList|r: " .. count .. " items stored.")
    if not EXT.SelectedReagents then return end
    for _, r in ipairs((EXT.SelectedReagents())) do
        local id, e = lookupItem(r.name)
        DEFAULT_CHAT_FRAME:AddMessage(string.format("  %s: id=%s icon=%s buy=%s client=%s", r.name, tostring(id),
            tostring(e and e.icon), tostring(e and e.buy), tostring(GetItemInfo(r.name) ~= nil)))
    end
end

-- ============================================================================
-- ACKIS DATA
-- ============================================================================

local ARL, private
local function arlReady()
    if private then return true end
    ARL = _G.AckisRecipeList
    private = ARL and ARL.private
    if not private then ARL = nil end
    return private ~= nil
end

local lookupsDone = {}
local ghostLists = {}

-- Every Ackis recipe of one profession, sorted by skill; built once per session.
local function recipesFor(line)
    if ghostLists[line] then return ghostLists[line] end
    if not arlReady() then return nil end
    if ARL.InitializeLookups then ARL:InitializeLookups() end
    local ok = false
    for _, name in pairs(private.professions) do
        if name == line then ok = true end
    end
    if not ok then return nil end
    pcall(ARL.InitializeProfession, ARL, line)
    local list = {}
    local faction = UnitFactionGroup("player")
    for _, recipe in pairs(private.recipe_list) do
        if recipe.profession == line and recipe.name and not recipe.specialty then
            local skip = false
            local okFlags, alliance, horde = pcall(function()
                return recipe:IsFlagged("common1", "ALLIANCE"), recipe:IsFlagged("common1", "HORDE")
            end)
            if okFlags then
                if faction == "Horde" and alliance and not horde then skip = true end
                if faction == "Alliance" and horde and not alliance then skip = true end
            end
            if not skip then list[#list + 1] = recipe end
        end
    end
    table.sort(list, function(a, b)
        if a.skill_level ~= b.skill_level then return a.skill_level < b.skill_level end
        return a.name < b.name
    end)
    ghostLists[line] = list
    return list
end

-- ============================================================================
-- KNOWN-RECIPE CACHE
-- ============================================================================

local scanning = false

-- ============================================================================
-- CATEGORIES: which of Blizzard's headers a recipe belongs to
-- ============================================================================
-- Ackis has no categories, so they are learned from the recipes the character already has: for each one the
-- item it makes (its type, subtype and equip slot) is tied to the header it sits under. An unlearned recipe
-- whose item looks the same goes under that header. Enchants have no item, so their "Enchant Boots - " prefix is used.

-- Keys from the most to the least specific; nil while the item is not in the client's cache yet.
local function catKeys(itemId, name)
    local keys = {}
    if itemId then
        local _, _, _, _, _, class, sub, _, loc = GetItemInfo(itemId)
        if not class then return nil end
        sub = sub or ""
        if loc and loc ~= "" then
            keys[#keys + 1] = "full:" .. class .. "|" .. sub .. "|" .. loc
            keys[#keys + 1] = "loc:" .. loc
        end
        keys[#keys + 1] = "sub:" .. class .. "|" .. sub
    end
    local prefix = name and name:match("^(.-) %- ")
    if prefix then keys[#keys + 1] = "pre:" .. prefix end
    return keys
end

local function learnCategory(line, header, index, name)
    local s = store()
    if not (s and header and name) then return end
    local cat = s.cat[line]
    if not cat then
        cat = { map = {}, seen = {} }
        s.cat[line] = cat
    end
    if cat.seen[name] then return end
    local link = GetTradeSkillItemLink(index)
    local itemId = link and tonumber(link:match("item:(%d+)"))
    local keys = catKeys(itemId, name)
    if not keys then return end
    cat.seen[name] = true
    cat.rev = (cat.rev or 0) + 1   -- headerFor's cache of answers is out of date
    for _, key in ipairs(keys) do
        local counts = cat.map[key]
        if not counts then
            counts = {}
            cat.map[key] = counts
        end
        counts[header] = (counts[header] or 0) + 1
    end
end

-- Header name for an Ackis recipe; second result is true while its item data is still loading.
local headerCache = {}   -- [line] = { owner = cat table, [spell id] = header or false }

local function headerFor(line, recipe)
    local s = store()
    local cat = s and s.cat[line]
    if not cat then return nil end
    local cache = headerCache[line]
    if not cache or cache.owner ~= cat or cache.rev ~= cat.rev then
        cache = { owner = cat, rev = cat.rev }
        headerCache[line] = cache
    end
    local known = cache[recipe.spell_id]
    if known ~= nil then return known or nil end
    local keys = catKeys(recipe.item_id, recipe.name)
    if not keys then return nil, true end
    local best
    for _, key in ipairs(keys) do
        local counts = cat.map[key]
        if counts then
            local bestN
            for header, n in pairs(counts) do
                if not bestN or n > bestN or (n == bestN and header < best) then best, bestN = header, n end
            end
            break
        end
    end
    cache[recipe.spell_id] = best or false
    return best
end

-- Reads every recipe of the open profession, expanding collapsed headers and collapsing them back.
local function scanKnown(line, set)
    scanning = true
    local collapsed = {}
    for i = GetNumTradeSkills(), 1, -1 do
        local name, kind, _, expanded = GetTradeSkillInfo(i)
        if kind == "header" and not expanded then
            collapsed[name] = true
            ExpandTradeSkillSubClass(i)
        end
    end
    local header
    for i = 1, GetNumTradeSkills() do
        local name, kind = GetTradeSkillInfo(i)
        if name and kind == "header" then
            header = name
        elseif name then
            set[name] = true
            learnCategory(line, header, i, name)
            seedReagents(i, name)
        end
    end
    for i = GetNumTradeSkills(), 1, -1 do
        local name, kind = GetTradeSkillInfo(i)
        if kind == "header" and collapsed[name] then CollapseTradeSkillSubClass(i) end
    end
    scanning = false
end

local scanTries = {}      -- per profession, this session
local scanPending          -- profession waiting for its scan
local settleUntil = 0      -- until then the scan's own list updates are still arriving

-- The scan runs on its own frame, never inside a list build: it expands and collapses headers, and every
-- one of those fires a list update. While it and those updates run the list builds plain (stock rows only);
-- once they have passed, the list is rebuilt a single time with the Ackis recipes in it.
local scanner = CreateFrame("Frame")
scanner:SetScript("OnUpdate", function()
    if scanPending then
        local line = scanPending
        scanPending = nil
        local s = store()
        if s and TradeSkillFrame and TradeSkillFrame:IsShown() and GetTradeSkillLine() == line then
            local set = s.known[line] or {}
            s.known[line] = set
            s.dirty[line] = nil
            pcall(scanKnown, line, set)
            scanning = false
            settleUntil = GetTime() + 0.6
        end
    elseif settleUntil > 0 and GetTime() >= settleUntil then
        settleUntil = 0
        refreshList()
    end
end)

-- The learned recipes of a profession, or nil while its first scan is still on its way.
local function knownSet(line)
    local s = store()
    if not s then return nil end
    local set = s.known[line]
    if set and not s.dirty[line] and s.cat[line] then return set end
    if scanPending ~= line and settleUntil == 0 and not scanning then
        -- A scan that leaves no category data (a flat list, or items not loaded) must not repeat forever.
        if set and not s.dirty[line] and (scanTries[line] or 0) >= 2 then
            s.cat[line] = s.cat[line] or { map = {}, seen = {} }
            return set
        end
        if not s.dirty[line] then scanTries[line] = (scanTries[line] or 0) + 1 end
        scanPending = line
    end
    return set   -- stale after learning something, nil before the first scan
end

-- Learning something at a trainer or from an item: every cached profession is read again on its next open.
local learned = CreateFrame("Frame")
learned:RegisterEvent("CHAT_MSG_SYSTEM")
learned:SetScript("OnEvent", function(_, _, msg)
    local pattern = _G.ERR_LEARN_RECIPE_S and _G.ERR_LEARN_RECIPE_S:gsub("%%s", ".+"):gsub("%-", "%%-")
    if pattern and msg and msg:find("^" .. pattern .. "$") then
        local s = store()
        if not s then return end
        for line in pairs(s.known) do s.dirty[line] = true end
        refreshList()
    end
end)

-- ============================================================================
-- SELECTION AND LIST ROWS
-- ============================================================================

local selected          -- the Ackis recipe being shown in the details pane
local collapsedGroup = false
local details           -- built lazily

local function hex(r, g, b)
    return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end

local function difficultyFor(recipe, rank)
    if rank >= recipe.trivial_level then return "trivial" end
    if rank >= recipe.easy_level then return "easy" end
    if rank >= recipe.medium_level then return "medium" end
    if rank >= recipe.optimal_level then return "optimal" end
    return "locked"
end

local function ghostRows(line, rank, skillUpOnly)
    local s = store()
    if not (s and s.enabled ~= false) or IsTradeSkillLinked() then return nil end
    local list = recipesFor(line)
    if not list then return nil end
    local known = knownSet(line)
    if not known then return nil end

    local text = List.SearchText and List.SearchText():lower() or ""
    if text ~= "" and text:match("^[%d~%-%s]+$") then return nil end

    local rows = {}
    local limit = rank   -- never above the current skill
    for _, recipe in ipairs(list) do
        if recipe.skill_level > limit then break end
        if not known[recipe.name] and not (text ~= "" and not recipe.name:lower():find(text, 1, true)) then
            local difficulty = difficultyFor(recipe, rank)
            if not ((s.hideTrivial or skillUpOnly) and difficulty == "trivial") then
                rows[#rows + 1] = {
                    index = -recipe.spell_id, ghost = true, recipe = recipe, count = 0,
                    difficulty = difficulty,
                    name = recipe.name,
                }
            end
        end
    end
    if #rows == 0 then return nil end
    return rows
end

local recipeByName   -- defined below with the labels
local origBuild = Model.Build
-- Safety net: if the list is rebuilt in a runaway loop, the Ackis part switches itself off for the session
-- (and says so) instead of freezing the game. Normal use, even dragging the scroll bar, stays far below it.
local buildStamp, buildCount, tripped = 0, 0, false
local building = false

function Model.Build(skillUpOnly, search)
    if scanning or tripped or building or settleUntil > 0 then return origBuild(skillUpOnly, search) end
    local now = GetTime()
    if now - buildStamp > 1 then buildStamp, buildCount = now, 0 end
    buildCount = buildCount + 1
    if buildCount > 150 then
        tripped = true
        DEFAULT_CHAT_FRAME:AddMessage("|cffff6060DragonUI_AckisRecipeList|r: the recipe list was rebuilt " .. buildCount ..
            " times in a second (" .. tostring(GetTradeSkillLine()) .. "); Ackis recipes are switched off until /reload.")
        -- Who keeps asking for the list: the call chain of the rebuild that tripped it.
        for entry in tostring(debugstack(2, 12, 0)):gmatch("[^\n]+") do
            DEFAULT_CHAT_FRAME:AddMessage("|cff9d9d9d  " .. (entry:gsub("Interface\\AddOns\\", "")) .. "|r")
        end
        return origBuild(skillUpOnly, search)
    end
    building = true
    local ok, rows = pcall(function() return EXT.BuildWithGhosts(skillUpOnly, search) end)
    building = false
    if ok then return rows end
    if not EXT.ackisErrored then
        EXT.ackisErrored = true
        DEFAULT_CHAT_FRAME:AddMessage("|cffff6060DragonUI_AckisRecipeList|r: Ackis recipes failed: " .. tostring(rows))
    end
    return origBuild(skillUpOnly, search)
end

function EXT.BuildWithGhosts(skillUpOnly, search)
    local line, rank = GetTradeSkillLine()
    local ghosts
    if line and EXT.GetAckisEnabled() then
        local ok, result = pcall(function()
            local set = knownSet(line)           -- may scan: before the stock rows are read
            return set and ghostRows(line, rank or 0, skillUpOnly)
        end)
        scanning = false
        ghosts = ok and result or nil
        if not ok and not EXT.ackisErrored then
            EXT.ackisErrored = true
            DEFAULT_CHAT_FRAME:AddMessage("|cffff6060DragonUI_AckisRecipeList|r: Ackis recipes failed: " .. tostring(result))
        end
    end
    local rows = origBuild(skillUpOnly, search)
    -- Whatever shows now is known for sure: learned recipes join the cache without a scan.
    local s = store()
    local set = s and line and s.known[line]
    if set then
        local header
        for _, row in ipairs(rows) do
            if row.header then
                header = row.name
            else
                set[row.name] = true
                learnCategory(line, header, row.index, row.name)
                seedReagents(row.index, row.name)
            end
        end
    end
    if ghosts then
        -- Into the header the recipe's kind belongs to; what has no header (yet) gets a group of its own.
        local open, shut = {}, {}
        for _, row in ipairs(rows) do
            if row.header then
                if row.expanded then open[row.name] = true else shut[row.name] = true end
            end
        end
        local byHeader, rest = {}, {}
        for _, g in ipairs(ghosts) do
            local header, pending = headerFor(line, g.recipe)
            if pending then Model.pendingItems = true end
            if header and open[header] then
                byHeader[header] = byHeader[header] or {}
                table.insert(byHeader[header], g)
            elseif not (header and shut[header]) then
                rest[#rest + 1] = g
            end
        end
        -- Inside each header, learned and not learned recipes are merged and ordered by required skill, highest first (as retail).
        local out, current, children = {}, nil, {}
        local function skillOf(row)
            if row.ghost then return row.recipe.skill_level end
            local r = recipeByName(line, row.name)
            return r and r.skill_level
        end
        local function flush()
            local list = current and byHeader[current.name]
            if list then
                for _, g in ipairs(list) do children[#children + 1] = g end
            end
            -- A learned recipe Ackis does not know takes the skill of the row before it, so it stays put.
            local last = 0
            for n, row in ipairs(children) do
                row.sortSkill = skillOf(row) or last
                row.sortPos = n
                last = row.sortSkill
            end
            table.sort(children, function(a, b)
                if a.sortSkill ~= b.sortSkill then return a.sortSkill > b.sortSkill end
                return a.sortPos < b.sortPos
            end)
            for _, row in ipairs(children) do out[#out + 1] = row end
            children = {}
        end
        for _, row in ipairs(rows) do
            if row.header then
                flush()
                current = row
                out[#out + 1] = row
            elseif current then
                children[#children + 1] = row
            else
                out[#out + 1] = row
            end
        end
        flush()
        rows = out
        -- The group of its own reads highest skill first too.
        for a = 1, math.floor(#rest / 2) do rest[a], rest[#rest - a + 1] = rest[#rest - a + 1], rest[a] end
        ghosts = rest
    end
    if ghosts and #ghosts > 0 then
        rows[#rows + 1] = { index = GHOST_HEADER, header = true, ghostHeader = true,
                            name = "Not Learned (Ackis)", expanded = not collapsedGroup }
        if not collapsedGroup then
            for _, row in ipairs(ghosts) do rows[#rows + 1] = row end
        end
    end
    return rows
end

-- Ackis recipe by name for the open profession (specialty and other-faction ones included, since a learned recipe
-- can be any of them); used to order the list and to show the skill in the details pane.
local byName = {}
function recipeByName(line, name)
    local map = byName[line]
    if not map then
        map = {}
        byName[line] = map
        if recipesFor(line) then
            for _, recipe in pairs(private.recipe_list) do
                if recipe.profession == line and recipe.name then map[recipe.name] = recipe end
            end
        end
    end
    return map[name]
end

local origSelectedIndex = Model.SelectedIndex
function Model.SelectedIndex()
    if selected then return -selected.spell_id end
    return origSelectedIndex()
end

-- ============================================================================
-- DETAILS PANE
-- ============================================================================

local CONTROLS = { "TradeSkillCreateButton", "TradeSkillCreateAllButton", "TradeSkillInputBox",
                   "TradeSkillDecrementButton", "TradeSkillIncrementButton" }

local function hideStockForm()
    if TradeSkillDetailScrollFrame then TradeSkillDetailScrollFrame:Hide() end
    for _, name in ipairs(CONTROLS) do
        local f = _G[name]
        if f then f:Hide() end
    end
end

local function showStockForm()
    if TradeSkillDetailScrollFrame then TradeSkillDetailScrollFrame:Show() end
end

local scanTip
local function reagentsOf(spellId)
    scanTip = scanTip or CreateFrame("GameTooltip", "DragonUIExtAckisScan", UIParent, "GameTooltipTemplate")
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTip:SetHyperlink("enchant:" .. spellId)
    local prefix = _G.SPELL_REAGENTS or "Reagents: "
    local out, seen = {}, scanTip:NumLines()
    for i = 1, seen do
        local line = _G["DragonUIExtAckisScanTextLeft" .. i]
        local text = line and line:GetText()
        if text and text:sub(1, #prefix) == prefix then
            -- Reagents you lack are coloured red in the tooltip: the codes would end up in the name.
            local plain = text:sub(#prefix + 1):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            for part in plain:gmatch("[^,]+") do
                part = strtrim(part)
                -- "Name (4)": the number is how many are needed, not part of the name.
                local name, count = part:match("^(.-)%s*%((%d+)%)%s*$")
                out[#out + 1] = { name = strtrim(name or part), count = tonumber(count) or 1 }
            end
        end
    end
    scanTip:Hide()
    return out, seen > 0
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

local function unitLine(list, id)
    local u = list and list[id]
    if not u then return nil end
    local where = u.location or ""
    if u.coord_x and u.coord_y then where = string.format("%s (%.1f, %.1f)", where, u.coord_x, u.coord_y) end
    return u.name, where, u.faction
end

-- "Source: Name - Zone (x, y)" entries, grouped under their acquire type.
local function acquireText(recipe)
    local A = private.acquire_types
    local gold, white, grey = "|cffffd100", "|cffffffff", "|cff9d9d9d"
    local chunks = {}
    local function add(typeId, label, entries)
        if #entries == 0 then return end
        local lines = { gold .. label .. "|r" }
        for i, e in ipairs(entries) do
            if i > MAX_LINES_PER_TYPE then
                lines[#lines + 1] = grey .. "   ... and " .. (#entries - MAX_LINES_PER_TYPE) .. " more|r"
                break
            end
            lines[#lines + 1] = "   " .. e
        end
        chunks[#chunks + 1] = table.concat(lines, "\n")
    end
    local function simple(typeId, label, list)
        local data = recipe.acquire_data[typeId]
        if not data then return end
        local entries = {}
        for _, id in ipairs(sortedKeys(data)) do
            local name, where, faction = unitLine(list, id)
            if name then
                local extra = (where ~= "" and (grey .. " - " .. where .. "|r") or "")
                if faction and faction ~= "Neutral" then extra = extra .. grey .. " [" .. faction .. "]|r" end
                entries[#entries + 1] = white .. name .. "|r" .. extra
            end
        end
        add(typeId, label, entries)
    end
    local names = private.acquire_names
    simple(A.TRAINER, names[A.TRAINER], private.trainer_list)
    simple(A.VENDOR, names[A.VENDOR], private.vendor_list)
    simple(A.QUEST, names[A.QUEST], private.quest_list)
    simple(A.MOB_DROP, names[A.MOB_DROP], private.mob_list)

    local rep = recipe.acquire_data[A.REPUTATION]
    if rep then
        local entries = {}
        for _, factionId in ipairs(sortedKeys(rep)) do
            local faction = private.reputation_list[factionId]
            for _, level in ipairs(sortedKeys(rep[factionId])) do
                local standing = _G["FACTION_STANDING_LABEL" .. (tonumber(level) + 4)] or tostring(level)
                for _, vendorId in ipairs(sortedKeys(rep[factionId][level])) do
                    local name, where = unitLine(private.vendor_list, vendorId)
                    entries[#entries + 1] = string.format("%s%s|r (%s)%s", white, faction and faction.name or "?",
                        standing, name and (grey .. " - " .. name .. (where ~= "" and (", " .. where) or "") .. "|r") or "")
                end
            end
        end
        add(A.REPUTATION, names[A.REPUTATION], entries)
    end

    local drop = recipe.acquire_data[A.WORLD_DROP]
    if drop then
        local entries = {}
        for _, zone in ipairs(sortedKeys(drop)) do entries[#entries + 1] = white .. tostring(zone) .. "|r" end
        add(A.WORLD_DROP, names[A.WORLD_DROP], entries)
    end
    for _, pair in ipairs({ { A.SEASONAL, private.seasonal_list }, { A.CUSTOM, private.custom_list } }) do
        local data = recipe.acquire_data[pair[1]]
        if data then
            local entries = {}
            for _, id in ipairs(sortedKeys(data)) do
                local u = pair[2] and pair[2][id]
                if u then
                    entries[#entries + 1] = white .. tostring(u.name) .. "|r" ..
                        ((u.location and u.location ~= "") and (grey .. " - " .. u.location .. "|r") or "")
                end
            end
            add(pair[1], names[pair[1]], entries)
        end
    end
    if #chunks == 0 then return grey .. "No source known.|r" end
    return table.concat(chunks, "\n\n")
end

-- The icon is 1px smaller on every side than DragonUI's 36 (34, 2.5 in), so these offsets are DragonUI's plus 1:
-- the frame keeps its size and position.
-- The same frames DragonUI draws round its own reagent and output icons (prof_details.lua), by item quality.
local OUTPUT_RINGS = { [0] = "ring-gray", [2] = "ring-green", [3] = "ring-blue", [4] = "ring-purple", [5] = "ring-orange" }
local SLOT_FRAMES = { [2] = "slot-frame-green", [3] = "slot-frame-blue", [4] = "slot-frame-epic", [5] = "slot-frame-legendary" }

local function placeSlotBorder(border, icon, quality)
    local art = SLOT_FRAMES[quality]
    P.Art.Set(border, art or "square-frame")
    border:ClearAllPoints()
    if art then
        border:SetPoint("TOPLEFT", icon, "TOPLEFT", -2.5, 2.5)
        border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 4.5, -4.5)
    else
        border:SetPoint("TOPLEFT", icon, "TOPLEFT", -7.5, 6.5)
        border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 6.5, -7.5)
    end
end

local function buildDetails()
    local frame = CreateFrame("Frame", nil, P.Frame.craft)
    frame:SetPoint("TOPLEFT", TradeSkillDetailScrollFrame, "TOPLEFT", 0, 0)
    frame:SetSize(316, 440)
    frame:SetFrameLevel(TradeSkillDetailScrollFrame:GetFrameLevel() + 5)
    frame:Hide()

    frame.iconRound = frame:CreateTexture(nil, "BACKGROUND")
    frame.iconRound:SetSize(43, 43)
    frame.iconRound:SetPoint("TOPLEFT", frame, "TOPLEFT", 17, -16)
    frame.ring = frame:CreateTexture(nil, "BORDER")
    P.Art.Set(frame.ring, "ring-gray", true)
    frame.ring:SetPoint("CENTER", frame.iconRound, "CENTER")
    frame.hit = CreateFrame("Button", nil, frame)
    frame.hit:SetAllPoints(frame.iconRound)
    frame.hit:SetScript("OnEnter", function(self)
        local r = self.recipe
        if r and r.item_id then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. r.item_id)
            GameTooltip:Show()
        end
    end)
    frame.hit:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local font = _G.DragonUI_ProfessionsOutputFont or GameFontNormalLarge
    frame.title = frame:CreateFontString(nil, "ARTWORK")
    frame.title:SetFontObject(font)
    frame.title:SetPoint("TOPLEFT", frame.iconRound, "TOPRIGHT", 12, 0)
    frame.title:SetWidth(240)
    frame.title:SetJustifyH("LEFT")
    frame.sub = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    frame.sub:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -4)
    frame.sub:SetWidth(240)
    frame.sub:SetJustifyH("LEFT")

    frame.reagentsLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    frame.reagentsLabel:SetText(_G.SPELL_REAGENTS and strtrim(SPELL_REAGENTS) or "Reagents:")
    -- Same fonts as DragonUI's own reagent list, read from the stock frames it restyles.
    local function copyFont(fs, from)
        local path, size, flags = from:GetFont()
        if path then fs:SetFont(path, size, flags) end
    end
    if TradeSkillReagentLabel then copyFont(frame.reagentsLabel, TradeSkillReagentLabel) end
    frame.reagents = {}
    for i = 1, 8 do
        local b = CreateFrame("Button", nil, frame)
        b:SetSize(150, 39)
        if i == 1 then
            b:SetPoint("TOPLEFT", frame.reagentsLabel, "BOTTOMLEFT", 0, -4)
        elseif i % 2 == 1 then
            b:SetPoint("TOPLEFT", frame.reagents[i - 2], "BOTTOMLEFT", 0, -2)
        else
            b:SetPoint("LEFT", frame.reagents[i - 1], "RIGHT", 6, 0)
        end
        -- As on DragonUI's reagent buttons: icon (36, 1.5 in from the corner, cropped 0.08) with the frame over its
        -- edge. Two textures of one layer draw in no promised order (the bronze frame lost to the icon), so the
        -- icon is on BORDER, the frame on ARTWORK and the count on OVERLAY.
        b.icon = b:CreateTexture(nil, "BORDER")
        b.icon:SetSize(34, 34)
        b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 2.5, -2.5)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.border = b:CreateTexture(nil, "ARTWORK")
        placeSlotBorder(b.border, b.icon, nil)
        b.text = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
        b.text:SetWidth(103)
        b.price = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        b.price:SetPoint("TOPLEFT", b.text, "BOTTOMLEFT", 0, -1)
        b.price:SetWidth(103)
        b.price:SetJustifyH("LEFT")
        b.text:SetJustifyH("LEFT")
        b.text:SetTextColor(1, 1, 1)
        if TradeSkillReagent1Name then copyFont(b.text, TradeSkillReagent1Name) end
        b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        b.count:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", -2, 2)
        if TradeSkillReagent1Count then copyFont(b.count, TradeSkillReagent1Count) end
        b:SetScript("OnEnter", function(self)
            if self.link then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(self.link)
                GameTooltip:Show()
            end
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        frame.reagents[i] = b
    end

    frame.acquireLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    frame.acquireLabel:SetText("How to obtain:")
    frame.acquire = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    frame.acquire:SetWidth(310)   -- the form is 316 wide and the text starts 16 in: it may reach past the edge by 10
    frame.acquire:SetJustifyH("LEFT")
    frame.acquire:SetJustifyV("TOP")
    return frame
end

local labelX, labelTop = 12, 86   -- set from the stock form by measureStockLabel
local measuredTop   -- { lowest, highest } label offset seen on stock recipes
-- 3.3.5a has no C_Timer; a throwaway OnUpdate frame stands in.
local function after(delay, fn)
    local f = CreateFrame("Frame")
    local t = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        t = t + elapsed
        if t >= delay then
            self:SetScript("OnUpdate", nil)
            fn()
        end
    end)
end

function EXT.SelectedReagents()
    if not selected then return {} end
    return (reagentsOf(selected.spell_id))
end

local function renderDetails(retry)
    local recipe = selected
    if not (recipe and details) then return end
    local item = recipe.item_id
    local itemName, itemLink, quality, _, _, _, _, _, _, itemIcon
    if item then itemName, itemLink, quality, _, _, _, _, _, _, itemIcon = GetItemInfo(item) end
    local icon = itemIcon or select(3, GetSpellInfo(recipe.spell_id)) or "Interface\\Icons\\INV_Misc_QuestionMark"
    SetPortraitToTexture(details.iconRound, icon)
    details.iconRound:SetTexCoord(0.078125, 0.921875, 0.078125, 0.921875)
    -- Like DragonUI: no item (enchants) reads as quality 0, the grey ring; a common item keeps the bronze one.
    local ringQuality = item and (quality or 1) or 0
    local ring = OUTPUT_RINGS[ringQuality]
    P.Art.Set(details.ring, ring or "ring-frame", true)
    details.iconRound:SetSize(ring and 43 or 45, ring and 43 or 45)
    details.hit.recipe = recipe

    local color = quality and ITEM_QUALITY_COLORS[quality] or nil
    details.title:SetText((color and color.hex or "") .. (itemName or recipe.name) .. (color and "|r" or ""))
    local _, rank = GetTradeSkillLine()
    local diff = difficultyFor(recipe, rank or 0)
    local c = _G.TradeSkillTypeColor and TradeSkillTypeColor[diff]
    details.sub:SetText(string.format("%s%s %d|r  |cff9d9d9d- not learned|r",
        c and hex(c.r, c.g, c.b) or "|cffa0a0a0", recipe.profession, recipe.skill_level))

    details.reagentsLabel:ClearAllPoints()
    details.reagentsLabel:SetPoint("TOPLEFT", details, "TOPLEFT", labelX, -labelTop)
    local reagents, cached = reagentsOf(recipe.spell_id)
    local unresolved = false
    for i, b in ipairs(details.reagents) do
        local r = reagents[i]
        if r then
            local id, e = lookupItem(r.name)
            if not id then unresolved = true end
            b.icon:SetTexture(e and e.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            b.link = id and ("item:" .. id) or nil
            placeSlotBorder(b.border, b.icon, e and e.quality)
            b.text:SetText(r.name)
            -- Bags / needed, like the stock list; the name greys when there is not enough.
            local have = GetItemCount(id or r.name)
            b.count:SetText(string.format("%d /%d", have, r.count))
            -- Blizzard's own rule for a reagent you lack: name and icon both go to 50% grey.
            local shade = have >= r.count and 1 or 0.5
            b.text:SetTextColor(shade, shade, shade)
            b.icon:SetVertexColor(shade, shade, shade)
            local buy = e and e.buy
            if buy then
                b.price:SetText((GetCoinTextureString or GetCoinText)(buy, 10))
                b.text:ClearAllPoints()
                b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 7)
                b.text:SetHeight(14)
            else
                b.price:SetText("")
                b.text:ClearAllPoints()
                b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
                b.text:SetHeight(0)
            end
            b:Show()
        else
            b:Hide()
        end
    end
    local shown = math.min(#reagents, 8)
    if shown > 0 then details.reagentsLabel:Show() else details.reagentsLabel:Hide() end
    local rows = math.ceil(shown / 2)
    details.acquireLabel:ClearAllPoints()
    if shown > 0 then
        details.acquireLabel:SetPoint("TOPLEFT", details.reagentsLabel, "BOTTOMLEFT", 0, -(rows * 41 + 12))
    else
        details.acquireLabel:SetPoint("TOPLEFT", details, "TOPLEFT", labelX, -labelTop)
    end
    details.acquire:ClearAllPoints()
    details.acquire:SetPoint("TOPLEFT", details.acquireLabel, "BOTTOMLEFT", 0, -6)
    details.acquire:SetText(acquireText(recipe))

    -- Item and spell data may still be on its way from the server: look again a moment later.
    if (not retry or retry < 3) and ((item and not itemName) or (not cached) or unresolved) then
        local n = (retry or 0) + 1
        after(0.6, function() if selected == recipe then renderDetails(n) end end)
    end
end

-- Bag counts follow what the player picks up or spends.
local bags = CreateFrame("Frame")
bags:RegisterEvent("BAG_UPDATE")
bags:SetScript("OnEvent", function()
    if selected and details and details:IsShown() then renderDetails(3) end
end)

-- Where the stock "Reagents:" label sits in the form. Blizzard hangs it under the description when a recipe has
-- one and under the requirements line otherwise; an Ackis recipe has neither, so it takes the middle of the spots seen
-- on stock recipes without a description (long names and tools lines push the label lower).
local function measureStockLabel()
    local child, label, desc = TradeSkillDetailScrollChildFrame, TradeSkillReagentLabel, TradeSkillDescription
    if selected or not (child and label and label:IsVisible() and child:GetTop() and label:GetTop() and label:GetLeft()) then return end
    local text = desc and desc:GetText()
    if text and strtrim(text) ~= "" then return end
    local top = child:GetTop() - label:GetTop()
    if top > 20 and top < 200 then
        -- The spot moves with the name's line count and the tools line; the middle of what was seen is the fair one.
        measuredTop = measuredTop or { top, top }
        measuredTop[1] = math.min(measuredTop[1], top)
        measuredTop[2] = math.max(measuredTop[2], top)
        -- Whole pixels only: a half-pixel start lets an icon bleed 1px past its frame.
        labelTop = math.floor((measuredTop[1] + measuredTop[2]) / 2 + 0.5)
        if child:GetLeft() then labelX = math.floor(label:GetLeft() - child:GetLeft() + 0.5) end
    end
end
P.On("Update", measureStockLabel)
P.On("Selection", measureStockLabel)

local function selectGhost(recipe)
    if not arlReady() then return end
    measureStockLabel()
    details = details or buildDetails()
    selected = recipe
    hideStockForm()
    details:Show()
    renderDetails()
    List.Refresh()
end

local function clearGhost()
    if not selected then return end
    selected = nil
    if details then details:Hide() end
    showStockForm()
end

local function findRecipe(index)
    local line = GetTradeSkillLine()
    for _, recipe in ipairs(ghostLists[line] or {}) do
        if recipe.spell_id == -index then return recipe end
    end
end

local origClick, origSelect = Model.Click, Model.Select

function Model.Click(index, button)
    if index and index < 0 and index ~= GHOST_HEADER then
        if IsModifiedClick() then
            local recipe = findRecipe(index)
            if recipe and recipe.item_id then
                local _, link = GetItemInfo(recipe.item_id)
                if link then HandleModifiedItemClick(link) end
            end
        elseif button == "LeftButton" then
            local recipe = findRecipe(index)
            if recipe then selectGhost(recipe) end
        end
        return
    end
    clearGhost()
    return origClick(index, button)
end

function Model.Select(index)
    if index == GHOST_HEADER then
        collapsedGroup = not collapsedGroup
        List.Refresh()
        return
    end
    clearGhost()
    return origSelect(index)
end

-- Any other selection (tracker, keyboard, Blizzard) hands the pane back to the stock form.
-- Blizzard_TradeSkillUI loads on demand, so the function does not exist yet here: DragonUI's own hook fires this.
P.On("Selection", function()
    if selected then
        clearGhost()
        List.Refresh()
    end
end)

P.On("Hide", clearGhost)
P.On("ProfessionChanged", clearGhost)

-- DragonUI's own refreshes re-show the create controls; while an Ackis recipe is open they stay hidden.
local function keepFormHidden()
    if selected then hideStockForm() end
end
P.On("Update", keepFormHidden)
P.On("Selection", keepFormHidden)

-- ============================================================================
-- ROW STYLING (greyed out)
-- ============================================================================

local function styleRows()
    for _, b in ipairs(List.rows) do
        local row = b.row
        if b:IsShown() and row and row.ghost then
            b.label:SetTextColor(GHOST_COLOR[1], GHOST_COLOR[2], GHOST_COLOR[3])
            b.skill:SetAlpha(0.4)
        else
            b.skill:SetAlpha(1)
        end
        if not b.extAckisHooked then
            b.extAckisHooked = true
            b:HookScript("OnLeave", function(self)
                if self.row and self.row.ghost then
                    self.label:SetTextColor(GHOST_COLOR[1], GHOST_COLOR[2], GHOST_COLOR[3])
                end
            end)
        end
    end
end

hooksecurefunc(List, "Refresh", styleRows)
-- DragonUI registers the original Refresh for these events, so the wrapper above never sees them.
P.On("Update", styleRows)
P.On("Selection", styleRows)
P.On("FavoritesChanged", styleRows)
P.On("FiltersChanged", styleRows)

-- ============================================================================
-- ACKIS "SCAN" BUTTON -> "RE-SCAN"
-- ============================================================================
-- Ackis docks a Scan button on the tradeskill window that opens its own (old) window. Here it only forgets what
-- is cached for the open profession; the list reads it again at once, nothing else opens.

function EXT.AckisRescanCurrent()
    local line = GetTradeSkillLine()
    local s = store()
    if not (line and s) then return end
    s.known[line], s.cat[line], s.dirty[line] = nil, nil, nil
    table.wipe(seeded)
    refreshList()
    DEFAULT_CHAT_FRAME:AddMessage("|cff1784d1DragonUI_AckisRecipeList|r: rescanned " .. line .. ".")
end

local function repurposeScanButton()
    local arl = _G.AckisRecipeList
    local button = type(arl) == "table" and arl.scan_button
    if not button or button.extRescan then return end
    button.extRescan = true
    button:SetScript("OnClick", function() EXT.AckisRescanCurrent() end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Re-Scan", 1, 1, 1)
        GameTooltip:AddLine("Forget the cached learned recipes of this profession and read them again.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    button:SetText("Re-Scan")
    button:SetWidth(button:GetTextWidth() + 10)
end

repurposeScanButton()
P.On("Show", repurposeScanButton)
P.On("Update", repurposeScanButton)

-- ============================================================================
-- SKILL NEEDED, NEXT TO THE NAME IN THE DETAILS PANE (learned recipes)
-- ============================================================================
-- Not in the list rows: the stock form's name gets a "[skill]" prefix, coloured by how the recipe rates now.

local function showSkillInName()
    if selected or not EXT.GetAckisEnabled() or not TradeSkillSkillName then return end
    local index = GetTradeSkillSelectionIndex()
    if not index or index <= 0 then return end
    local name, kind = GetTradeSkillInfo(index)
    if not name or kind == "header" then return end
    local ok, recipe = pcall(function()
        local line = GetTradeSkillLine()
        return line and arlReady() and recipeByName(line, name)
    end)
    if not (ok and recipe) then return end
    local c = _G.TradeSkillTypeColor and TradeSkillTypeColor[kind]
    TradeSkillSkillName:SetText(string.format("%s[%d]|r %s", c and hex(c.r, c.g, c.b) or "|cffa0a0a0", recipe.skill_level, name))
    -- DragonUI put its favourite star after the name before this; move it after the longer name.
    local star = P.Details and P.Details.favorite
    if star and star:IsShown() then
        star:ClearAllPoints()
        star:SetPoint("LEFT", TradeSkillSkillName, "LEFT",
            math.min(TradeSkillSkillName:GetStringWidth(), TradeSkillSkillName:GetWidth()) + 4, 1)
    end
end
P.On("Update", showSkillInName)
P.On("Selection", showSkillInName)

-- ============================================================================
-- MISSING BRIDGE LINE IN ACKISRECIPELIST
-- ============================================================================

local check = CreateFrame("Frame")
check:RegisterEvent("PLAYER_LOGIN")
check:SetScript("OnEvent", function()
    local arl = _G.AckisRecipeList
    if type(arl) == "table" and not arl.private then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff6060DragonUI_AckisRecipeList|r: AckisRecipeList's core.lua is missing the line " ..
            "|cffffffffaddon.private = private|r, so no recipes can be shown. See this addon's README.")
    end
end)
