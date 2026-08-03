local propTauntMenu
local propTauntEntries = {}
local OpenPropTauntMenu

net.Receive("PH_PropTauntList", function()
    propTauntEntries = net.ReadTable() or {}
    if IsValid(propTauntMenu) then
        propTauntMenu:Close()
    end
    OpenPropTauntMenu()
end)

local function RequestPropTauntList()
    net.Start("PH_RequestPropTaunts")
    net.SendToServer()
end

OpenPropTauntMenu = function()
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

    local list = vgui.Create("DScrollPanel", propTauntMenu)
    list:Dock(FILL)
    list:DockMargin(10, 82, 10, 10)

    local canvas = list:GetCanvas()
    canvas:DockPadding(0, 0, 0, 8)

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

    if #propTauntEntries == 0 then
        RequestPropTauntList()
    end

    local entries = {}
    for _, filename in ipairs(propTauntEntries) do
        local ext = string.GetExtensionFromFilename(filename):lower()
        if ext == "wav" or ext == "mp3" or ext == "ogg" then
                local tauntPath = "taunts/props/" .. filename
            local label = makeTauntLabel(filename)
            table.insert(entries, {sound = tauntPath, label = label})
        end
    end

    table.sort(entries, function(a, b)
        return string.lower(a.label) < string.lower(b.label)
    end)

    if #entries == 0 then
        local notice = vgui.Create("DLabel", list)
        notice:SetText("No prop taunts found in sound/taunts/props.")
        notice:Dock(TOP)
        notice:SetTextColor(Color(220, 220, 220, 255))
        notice:SetFont("DermaDefaultBold")
        notice:SizeToContents()
    end

    for _, entry in ipairs(entries) do
        local btn = vgui.Create("DButton", list)
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
