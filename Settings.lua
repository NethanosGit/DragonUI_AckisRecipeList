-- DragonUI_AckisRecipeList: a small settings window, opened with /duiarl.
--
-- Built from DragonUI's own ForeverUI pieces (the metal window, checkboxes and buttons), so it reads the
-- textures and fonts from DragonUI at runtime. Nothing is copied from DragonUI.

local DUI = _G.DragonUI
local EXT = _G.DragonUI_AckisRecipeList
local FUI = DUI and DUI.ForeverUI
if not (FUI and EXT and EXT.GetAckisEnabled) then return end

local WIDTH, HEIGHT = 420, 300
local window

local function CreateWindow()
    local f = FUI.CreateWindow("DragonUIAckisRecipeListWindow", UIParent, {
        width = WIDTH,
        height = HEIGHT,
        title = "DragonUI |cffffffffAckis Recipes|r",
        inset = true,
        strata = "DIALOG",
        movable = true,
        escClose = true,
    })
    f:SetPoint("CENTER")
    local inset = f.Inset

    local header = inset:CreateFontString(nil, "ARTWORK")
    header:SetFontObject(FUI.Fonts.HighlightMedium)
    header:SetPoint("TOPLEFT", inset, "TOPLEFT", 18, -18)
    header:SetText("Not Learned Recipes")

    local divider = FUI.CreateDivider(inset)
    divider:SetPoint("TOPLEFT", inset, "TOPLEFT", 0, -44)
    divider:SetPoint("TOPRIGHT", inset, "TOPRIGHT", 0, -44)
    divider:SetHeight(1)

    local info = inset:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    info:SetPoint("TOPLEFT", inset, "TOPLEFT", 18, -58)
    info:SetWidth(WIDTH - 70)
    info:SetJustifyH("LEFT")
    info:SetText("Shows the recipes you have not learned yet, from AckisRecipeList's database, inside DragonUI's " ..
        "Professions window. Click one to see what it makes, its reagents and where to get it.")

    local show = FUI.CreateCheckbox(inset, "Show not learned recipes", function(checked)
        EXT.SetAckisEnabled(checked)
    end)
    show:SetPoint("TOPLEFT", inset, "TOPLEFT", 16, -118)

    local trivial = FUI.CreateCheckbox(inset, "Hide trivial (grey) recipes", function(checked)
        EXT.SetAckisHideTrivial(checked)
    end)
    trivial:SetPoint("TOPLEFT", show, "BOTTOMLEFT", 0, -8)

    local rescanNote = inset:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    rescanNote:SetPoint("TOPLEFT", trivial, "BOTTOMLEFT", 2, -22)
    rescanNote:SetWidth(WIDTH - 70)
    rescanNote:SetJustifyH("LEFT")
    rescanNote:SetText("Learned recipes are cached, so nothing is scanned each time a profession opens. " ..
        "The Re-Scan button on the profession window re-reads that profession; this one forgets all of them.")

    local rescan = FUI.CreateButton(inset, "Re-Scan All Professions", 190, 22)
    rescan:SetPoint("TOPLEFT", rescanNote, "BOTTOMLEFT", 0, -10)
    rescan:SetScript("OnClick", function() EXT.AckisRescan() end)

    local status = inset:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    status:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", 18, 14)
    f.status = status

    local close = FUI.CreateButton(f, "Close", 96, 22)
    close:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 16)
    close:SetScript("OnClick", function() f:Hide() end)

    f:SetScript("OnShow", function(self)
        show:SetChecked(EXT.GetAckisEnabled())
        trivial:SetChecked(EXT.GetAckisHideTrivial())
        local arl = _G.AckisRecipeList
        if type(arl) == "table" and arl.private then
            self.status:SetText("AckisRecipeList: |cff20ff20connected|r")
        elseif type(arl) == "table" then
            self.status:SetText("AckisRecipeList: |cffff6060line missing in core.lua (see README)|r")
        else
            self.status:SetText("AckisRecipeList: |cffff6060not loaded|r")
        end
    end)

    window = f
    return f
end

local function Toggle()
    if not window then CreateWindow() end
    if window:IsShown() then window:Hide() else window:Show() end
end

SLASH_DUIARL1 = "/duiarl"
SlashCmdList["DUIARL"] = function(msg)
    if msg and msg:lower():match("^%s*debug") then
        EXT.Debug()
    else
        Toggle()
    end
end

EXT.OpenSettings = Toggle
