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

local function OpenHunterModelMenu()
    local ply = LocalPlayer()
    if not IsValid(ply) or ply:Team() ~= TEAM_HUNTERS then return end
    if not GetGlobalBool("InRound", false) then return end

    RunConsoleCommand("menu_player_model")
end

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
end)
