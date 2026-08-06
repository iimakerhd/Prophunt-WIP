local propTauntMenu
local propTauntList
local propTauntEntries = {}

local function RequestPropTauntList()
    net.Start("PH_RequestPropTaunts")
    net.SendToServer()
end

local function makeTauntLabel(name)
    local clean = string.StripExtension(name) or name
    clean = string.gsub(clean, "[_%-]", " ")
    clean = string.Trim(clean)
    clean = string.lower(clean)
    clean = string.gsub(clean, "(%a)([%w_']*)", function(first, rest)
        return string.upper(first) .. rest
    end)
    return clean
end

local function PopulatePropTauntList()
    if not IsValid(propTauntList) then return end
    propTauntList:Clear()

    local entries = {}
    for _, filename in ipairs(propTauntEntries) do
        local ext = string.GetExtensionFromFilename(filename):lower()
        if ext == "wav" or ext == "mp3" or ext == "ogg" then
            local tauntPath = PROP_TAUNT_FOLDER .. filename
            local label = makeTauntLabel(filename)
            table.insert(entries, {sound = tauntPath, label = label})
        end
    end

    table.sort(entries, function(a, b)
        return string.lower(a.label) < string.lower(b.label)
    end)

    if #entries == 0 then
        local notice = vgui.Create("DLabel", propTauntList)
        notice:SetText("No prop taunts found in sound/" .. PROP_TAUNT_FOLDER)
        notice:Dock(TOP)
        notice:SetTextColor(Color(220, 220, 220, 255))
        notice:SetFont("DermaDefaultBold")
        notice:SizeToContents()
        return
    end

    for _, entry in ipairs(entries) do
        local btn = vgui.Create("DButton", propTauntList)
        btn:Dock(TOP)
        btn:DockMargin(0, 0, 0, 8)
        btn:SetText("")
        btn.label = entry.label
        btn:SetFont("DermaDefaultBold")
        btn:SetTextColor(Color(240, 240, 240, 255))
        btn:SetTall(36)

        function btn:Paint(w, h)
            local bg = self:IsHovered() and Color(95, 155, 255, 180) or Color(40, 40, 40, 170)
            draw.RoundedBox(6, 0, 0, w, h, bg)
            draw.SimpleText(self.label, self:GetFont(), 14, h * 0.5, Color(255, 255, 255, 230), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end

        btn.DoClick = function()
            net.Start("PH_PlayTaunt")
                net.WriteString(entry.sound)
            net.SendToServer()
            if IsValid(propTauntMenu) then
                propTauntMenu:Close()
            end
        end
    end
end

-- Just refresh whatever's currently in the (already open) menu - this must NOT
-- reopen/recreate the frame. The previous version closed+reopened the whole menu
-- on every response, and re-requested the list any time it was empty, which meant
-- an empty list caused an endless close/reopen loop that made the menu impossible
-- to dismiss. Now a response only ever updates the list contents in place.
net.Receive("PH_PropTauntList", function()
    propTauntEntries = net.ReadTable() or {}
    PopulatePropTauntList()
end)

local function OpenPropTauntMenu()
    local ply = LocalPlayer()
    if not IsValid(ply) or ply:Team() ~= TEAM_PROPS then return end
    if not GetGlobalBool("InRound", false) then return end

    if IsValid(propTauntMenu) then
        propTauntMenu:Close()
    end

    propTauntMenu = vgui.Create("DFrame")
    propTauntMenu:SetTitle("")
    propTauntMenu:SetSize(360, 420)
    propTauntMenu:Center()
    propTauntMenu:MakePopup()
    propTauntMenu:SetDraggable(false)
    propTauntMenu:ShowCloseButton(true)
    propTauntMenu:SetDeleteOnClose(true)
    propTauntMenu:SetBackgroundBlur(false)

    function propTauntMenu:Paint(w, h)
        draw.RoundedBox(10, 0, 0, w, h, Color(15, 15, 15, 210))
        draw.RoundedBox(10, 10, 10, w - 20, 52, Color(255, 255, 255, 20))
        draw.SimpleText("Prop Taunt Menu", "DermaLarge", 20, 16, Color(255, 255, 255, 225), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText("Select a sound to play while remaining hidden.", "DermaDefault", 20, 44, Color(200, 200, 200, 180), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end

    propTauntList = vgui.Create("DScrollPanel", propTauntMenu)
    propTauntList:Dock(FILL)
    propTauntList:DockMargin(10, 82, 10, 10)
    propTauntList:GetCanvas():DockPadding(0, 0, 0, 8)

    -- Show whatever we currently know (instant, no flicker), then ask the server
    -- for a fresh list once. The response above only updates the list contents -
    -- it never touches the frame itself, so the menu stays open/closed exactly
    -- as the player left it regardless of how many responses arrive.
    PopulatePropTauntList()
    RequestPropTauntList()
end

concommand.Add("ph_taunt_menu", OpenPropTauntMenu)


-- ===========================================================================
-- Hunter player model menu
--
-- Deliberately NOT using the stock "menu_player_model" console command - that
-- just sets the cl_playermodel convar, which only takes effect on next spawn.
-- This builds its own grid and applies the choice over the network
-- immediately, live, with no respawn needed.
--
-- The model list combines TWO sources so both default GMod models and
-- workshop-subscribed ones show up:
--   1) player_manager.AllValidModels() - anything properly registered, which
--      covers default GMod models and well-behaved workshop playermodel packs.
--   2) A recursive filesystem scan of models/player/ - catches workshop packs
--      that just drop .mdl files there without registering via player_manager.
-- Both send the model's actual file path to the server (not a short name),
-- since only a real path can be validated/used for packs from source (2).
-- ===========================================================================

local hunterModelMenu
local hunterModelGrid
local hunterModelList -- cached {path=, label=} list, built once per session

local function ApplyHunterModel(modelPath)
    net.Start("PH_SetHunterModel")
        net.WriteString(modelPath)
    net.SendToServer()
end

local function BuildHunterModelList()
    if hunterModelList then return hunterModelList end

    local list = {}
    local seen = {}

    -- Source 1: officially registered models (default GMod + well-behaved addons)
    local registered = player_manager.AllValidModels()
    for niceName, modelPath in pairs(registered) do
        if not seen[modelPath] then
            seen[modelPath] = true
            table.insert(list, {path = modelPath, label = niceName})
        end
    end

    -- Source 2: recursive scan for any other .mdl under models/player/ that
    -- wasn't already registered - covers workshop packs that skip registration.
    local function scan(path)
        local files, dirs = file.Find(path .. "*", "GAME")
        for _, f in ipairs(files) do
            if string.EndsWith(string.lower(f), ".mdl") then
                local fullPath = path .. f
                if not seen[fullPath] then
                    seen[fullPath] = true
                    table.insert(list, {path = fullPath, label = string.StripExtension(f)})
                end
            end
        end
        for _, d in ipairs(dirs) do
            scan(path .. d .. "/")
        end
    end
    scan("models/player/")

    table.sort(list, function(a, b) return string.lower(a.label) < string.lower(b.label) end)

    hunterModelList = list
    return list
end

local function PopulateHunterModelGrid(filterText)
    if not IsValid(hunterModelGrid) then return end
    hunterModelGrid:Clear()

    local ply = LocalPlayer()
    local currentPath = IsValid(ply) and ply:GetNWString("PH_HunterModel", "") or ""

    filterText = filterText and string.lower(string.Trim(filterText)) or ""

    for _, entry in ipairs(BuildHunterModelList()) do
        if filterText == "" or string.find(string.lower(entry.label), filterText, 1, true) then
            local holder = vgui.Create("DPanel", hunterModelGrid)
            holder:SetSize(88, 108)
            holder.Paint = function(self, w, h)
                if entry.path == currentPath then
                    draw.RoundedBox(6, 0, 0, w, h, Color(95, 155, 255, 90))
                end
            end

            local icon = vgui.Create("SpawnIcon", holder)
            icon:SetPos(2, 2)
            icon:SetSize(84, 84)
            icon:SetModel(entry.path)
            icon:SetTooltip(entry.path == currentPath and (entry.label .. " (current)") or entry.label)

            icon.DoClick = function()
                ApplyHunterModel(entry.path)
                currentPath = entry.path
                if IsValid(hunterModelMenu) then
                    hunterModelMenu:Close()
                end
            end

            local label = vgui.Create("DLabel", holder)
            label:SetPos(0, 88)
            label:SetSize(88, 18)
            label:SetContentAlignment(5)
            label:SetFont("DermaDefault")
            label:SetTextColor(Color(220, 220, 220, 255))
            label:SetText(entry.label)
        end
    end
end

local function OpenHunterModelMenu()
    local ply = LocalPlayer()
    if not IsValid(ply) or ply:Team() ~= TEAM_HUNTERS then return end
    if not GetGlobalBool("InRound", false) then return end

    -- Blinded hunters can't see anyway, and opening this while the camera is
    -- parked out in the void (see GM:CalcView in cl_init.lua) causes the
    -- SpawnIcon render-target previews to bleed a leftover colour into the
    -- screen instead of the expected blackness. Simplest fix: don't allow it.
    if blind then
        ply:ChatPrint("You can't change your model while blinded.")
        return
    end

    if IsValid(hunterModelMenu) then
        hunterModelMenu:Close()
    end

    hunterModelMenu = vgui.Create("DFrame")
    hunterModelMenu:SetTitle("")
    hunterModelMenu:SetSize(640, 520)
    hunterModelMenu:Center()
    hunterModelMenu:MakePopup()
    hunterModelMenu:SetDraggable(false)
    hunterModelMenu:ShowCloseButton(true)
    hunterModelMenu:SetDeleteOnClose(true)
    hunterModelMenu:SetBackgroundBlur(false)

    function hunterModelMenu:Paint(w, h)
        draw.RoundedBox(10, 0, 0, w, h, Color(15, 15, 15, 210))
        draw.RoundedBox(10, 10, 10, w - 20, 52, Color(255, 255, 255, 20))
        draw.SimpleText("Select Hunter Model", "DermaLarge", 20, 16, Color(255, 255, 255, 225), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText("Applies immediately - no need to respawn.", "DermaDefault", 20, 44, Color(200, 200, 200, 180), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end

    local search = vgui.Create("DTextEntry", hunterModelMenu)
    search:Dock(TOP)
    search:DockMargin(10, 82, 10, 8)
    search:SetTall(26)
    search:SetPlaceholderText("Search models...")

    local scroll = vgui.Create("DScrollPanel", hunterModelMenu)
    scroll:Dock(FILL)
    scroll:DockMargin(10, 0, 10, 10)

    hunterModelGrid = vgui.Create("DIconLayout", scroll)
    hunterModelGrid:Dock(FILL)
    hunterModelGrid:SetSpaceY(6)
    hunterModelGrid:SetSpaceX(6)

    search.OnValueChange = function(self, val)
        PopulateHunterModelGrid(val)
    end

    PopulateHunterModelGrid("")
end

concommand.Add("ph_hunter_model_menu", OpenHunterModelMenu)

local lastF4Down = false
hook.Add("Think", "PH_PropTauntMenuF4Bind", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not GetGlobalBool("InRound", false) then
        lastF4Down = false
        return
    end

    local f4Down = input.IsKeyDown(KEY_F4)
    if f4Down and not lastF4Down then
        if ply:Team() == TEAM_PROPS then
            OpenPropTauntMenu()
        elseif ply:Team() == TEAM_HUNTERS then
            OpenHunterModelMenu()
        end
    end

    lastF4Down = f4Down
end)

hook.Add("OnSpawnMenuClose", "PH_PropTauntMenuClose", function()
    if IsValid(propTauntMenu) then
        propTauntMenu:Close()
    end
    if IsValid(hunterModelMenu) then
        hunterModelMenu:Close()
    end
end)
