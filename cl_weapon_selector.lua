--
hg = hg or {}
hg.WeaponSelector = hg.WeaponSelector or {}
local WS = hg.WeaponSelector

function WS.GetPrintName( self )
	local class = self:GetClass()
	local phrase = language.GetPhrase(class)
	return phrase ~= class and phrase or self:GetPrintName()
end

WS.Show = 0
WS.Transparent = 0
WS.LastSelectedSlot = 0
WS.LastSelectedSlotPos = 0

WS.SelectedSlot = 0
WS.SelectedSlotPos = 0

function WS.DrawText(text, font, posX, posY, color, textAlign)
    draw.DrawText( text, font, posX + 2, posY + 2, ColorAlpha(color_black,WS.Transparent*255) ,textAlign )
    draw.DrawText( text, font, posX, posY, ColorAlpha(color,WS.Transparent*255) ,textAlign )
end

function WS.GetSelectedWeapon()
    if not IsValid( LocalPlayer() ) or not LocalPlayer():Alive() then return end
    local Weapons = WS.GetWeaponTable( LocalPlayer() )
    return Weapons[WS.SelectedSlot] and Weapons[WS.SelectedSlot][WS.SelectedSlotPos] or Weapons[WS.LastSelectedSlot][WS.LastSelectedSlotPos] or Weapons[0][0]
end

function WS.GetWeaponTable( ply )
    if not IsValid( ply ) or not ply:Alive() then return end
    local WeaponsGet = ply:GetWeapons()
    local FormatedTable = {
        [0] = {}, [1] = {}, [2] = {}, [3] = {}, [4] = {}, [5] = {},
    }

    table.sort(WeaponsGet, function(a, b) return (a.SlotPos or 0) > (b.SlotPos or 0) end)

    for k,wep in ipairs(WeaponsGet) do
        local tTbl = FormatedTable[wep.Slot or 0]
        local iMinPos = math.min( (wep.SlotPos and wep.SlotPos) or 1, ((#tTbl or 0) + 1)) - 1
        local iPos = tTbl[ iMinPos ] and #tTbl + 1 or iMinPos
        tTbl[ iPos ] = wep
    end
    return FormatedTable
end

local scrW, scrH = ScrW(), ScrH()

local AcsentColor = Color(155,0,0)
local gradient_u = Material("vgui/gradient-d")

-- Wheel layout / feel. Tweak these to taste.
local WheelHubX      = scrW * 0.03   -- hub sits right against the left edge
local WheelCenterY   = scrH * 0.5
local WheelRadius    = scrH * 0.22   -- distance of each slot icon from the hub
local SlotBoxSize    = scrH * 0.06   -- size of an unselected slot icon
local SlotBoxSizeSel = scrH * 0.085  -- size of the highlighted slot icon
local ItemBoxW       = scrW * 0.115  -- width of a weapon row in the expanded slot
local ItemBoxH       = scrH * 0.045
local AngleStep      = 24            -- degrees between neighboring slots on the arc
local RotateSpeed    = 10            -- higher = snappier slide
local EdgeMargin     = 8             -- min gap kept between any icon and the screen edge

WS.WheelOffset = WS.WheelOffset or 0 -- continuous "which slot is centered" value

-- Slides WS.WheelOffset toward the selected slot's index the short way
-- around the list (so going from slot 6 back to slot 1 doesn't spin through
-- every slot in between), without ever letting the value jump.
local function ApproachIndex(target, current, count, speed)
    local diff = target - current
    diff = diff - count * math.floor(diff / count + 0.5)
    return current + diff * math.min(FrameTime() * speed, 1)
end

function WS.WeaponSelectorDraw( ply )
    if not IsValid( ply ) or not ply:Alive() or GetGlobalBool("RadialInventory", false) then return end
    if WS.Show < CurTime() then 
        WS.SelectedSlot = WS.LastSelectedSlot 
        WS.SelectedSlotPos = -1
        
        return 
    end
    local Weapons = WS.GetWeaponTable( ply )
    local SelectedWep = WS.GetSelectedWeapon()
    if not IsValid(SelectedWep) then return end
    WS.Transparent = LerpFT( 0.2, WS.Transparent, math.min( WS.Show - CurTime(), 1 ) )

    -- Gather only the slots that actually have weapons in them, in order.
    local ActiveSlots = {}
    for i = 0, #Weapons do
        if table.Count(Weapons[i]) > 0 then
            ActiveSlots[#ActiveSlots + 1] = i
        end
    end
    local Count = #ActiveSlots
    if Count < 1 then return end

    -- Where is the currently selected slot in that ordered list?
    local selJ = 0
    for j, slotIdx in ipairs(ActiveSlots) do
        if slotIdx == WS.SelectedSlot then
            selJ = j - 1
            break
        end
    end

    -- Instead of spinning a full 360-degree circle (which could swing icons
    -- behind the edge of the screen mid-rotation), we slide a fixed, bounded
    -- arc: each slot sits at a fixed angular distance from whichever slot is
    -- currently selected. Only WS.WheelOffset moves, and it always takes the
    -- shortest path, so the motion is smooth and every icon stays on-screen
    -- the whole time.
    WS.WheelOffset = ApproachIndex(selJ, WS.WheelOffset, Count, RotateSpeed)

    -- Backdrop so the wheel always reads clearly against the game world
    -- behind it, and never looks like it's "behind" anything else.
    local backdropH = math.min(WheelRadius * 2 + SlotBoxSizeSel, scrH * 0.9)
    draw.RoundedBox(
        8,
        0,
        WheelCenterY - backdropH/2,
        WheelHubX + WheelRadius + SlotBoxSizeSel/2 + EdgeMargin,
        backdropH,
        ColorAlpha(color_black, WS.Transparent*90)
    )

    for j, slotIdx in ipairs(ActiveSlots) do
        local slotTbl = Weapons[slotIdx]

        -- Signed distance (in slots) from the centered/selected slot, wrapped
        -- the short way around so it never exceeds +-Count/2.
        local relIndex = (j - 1) - WS.WheelOffset
        relIndex = relIndex - Count * math.floor(relIndex / Count + 0.5)

        local rad = math.rad(relIndex * AngleStep)

        local isSelectedSlot = slotIdx == WS.SelectedSlot
        local boxSize = isSelectedSlot and SlotBoxSizeSel or SlotBoxSize

        local px = WheelHubX + math.cos(rad) * WheelRadius
        local py = WheelCenterY + math.sin(rad) * WheelRadius

        -- Clamp so the icon's box can never be clipped by a screen edge,
        -- regardless of screen size or how far the arc math pushes it.
        px = math.Clamp(px, boxSize/2 + EdgeMargin, scrW - boxSize/2 - EdgeMargin)
        py = math.Clamp(py, boxSize/2 + EdgeMargin, scrH - boxSize/2 - EdgeMargin)

        -- spoke from hub to icon
        surface.SetDrawColor(0, 0, 0, WS.Transparent*120)
        surface.DrawLine(WheelHubX, WheelCenterY, px, py)

        -- box background, then highlight gradient, then outline, then text
        -- LAST so the label is always drawn on top and never hidden.
        draw.RoundedBox(
            4,
            px - boxSize/2,
            py - boxSize/2,
            boxSize,
            boxSize,
            ColorAlpha(color_black, WS.Transparent*215)
        )

        surface.SetDrawColor( 155, 0, 0, WS.Transparent*( isSelectedSlot and 200 or 0 ) )
        surface.SetMaterial( gradient_u )
        surface.DrawTexturedRect( px - boxSize/2, py - boxSize/2, boxSize, boxSize )

        if isSelectedSlot then
            surface.SetDrawColor( 255, 0, 0, WS.Transparent*155 )
            surface.DrawOutlinedRect( px - boxSize/2, py - boxSize/2, boxSize, boxSize, 2 )
        end

        WS.DrawText( slotIdx+1, "HomigradFontMedium", px, py - 8, ColorAlpha(color_white,WS.Transparent*255), TEXT_ALIGN_CENTER )

        -- Expand the highlighted slot's individual weapons out to the right
        -- of its icon, stacked vertically, same style as the old bar.
        if isSelectedSlot then
            local listX = px + boxSize/2 + 15
            local listCount = table.Count(slotTbl)
            local listY = math.Clamp(
                py - (listCount * ItemBoxH) / 2,
                EdgeMargin,
                scrH - (listCount * ItemBoxH) - EdgeMargin
            )
            listX = math.min(listX, scrW - ItemBoxW - EdgeMargin)
            local row = 0

            for Id = 0, #slotTbl do
                local wep = slotTbl[Id]
                if not wep then continue end

                local py2 = listY + row * ItemBoxH
                local isSelWep = SelectedWep == wep

                draw.RoundedBox(
                    0, listX, py2, ItemBoxW, ItemBoxH,
                    ColorAlpha(color_black, WS.Transparent*215)
                )

                surface.SetDrawColor( 155, 0, 0, WS.Transparent*( isSelWep and 200 or 0 ) )
                surface.SetMaterial( gradient_u )
                surface.DrawTexturedRect( listX, py2, ItemBoxW, ItemBoxH )

                if isSelWep then
                    surface.SetDrawColor( 255, 0, 0, WS.Transparent*155 )
                    surface.DrawOutlinedRect( listX, py2, ItemBoxW, ItemBoxH, 2 )
                end

                WS.DrawText( WS.GetPrintName(wep), "HomigradFontSmall", listX + ItemBoxW/2, py2 + ItemBoxH/2 - 6, ColorAlpha(color_white,WS.Transparent*255), TEXT_ALIGN_CENTER )

                if isSelWep and wep.DrawWeaponSelection then
                    wep:DrawWeaponSelection(listX + 5, py2 + ItemBoxH + 5, ItemBoxW - 10, ItemBoxH, WS.Transparent*255)
                end

                row = row + 1
            end
        end
    end
end

-- Changer
local tAcceptKeys = {
    ["slot1"] = 1,
    ["slot2"] = 2,
    ["slot3"] = 3,
    ["slot4"] = 4,
    ["slot5"] = 5,
    ["slot6"] = 6,
}

--[[
    Table:
        [1]	=	Weapon [52][weapon_hands_sh]
        [2]	=	Weapon [117][weapon_bigconsumable]
        [3]	=	Weapon [121][weapon_handcuffs_key]
        [4]	=	Weapon [122][weapon_handcuffs]
        [5]	=	Weapon [123][weapon_traitor_poison1]
        [6]	=	Weapon [124][weapon_traitor_suit]
        [7]	=	Weapon [125][weapon_matches]

    TableFormated:
    [0]:
		[0]	=	Weapon [126][weapon_physgun]
		[1]	=	Weapon [52][weapon_hands_sh]
    [1]:
    [2]:
    [3]:
		[1]	=	Weapon [117][weapon_bigconsumable]
		[2]	=	Weapon [121][weapon_handcuffs_key]
		[3]	=	Weapon [122][weapon_handcuffs]
		[4]	=	Weapon [123][weapon_traitor_poison1]
		[5]	=	Weapon [125][weapon_matches]
    [4]:
    [5]:
		[1]	=	Weapon [124][weapon_traitor_suit]
--]]

local function GetUpper(Weapons)
    if #LocalPlayer():GetWeapons() < 1 then return end
    WS.SelectedSlot = WS.SelectedSlot < 0 and #Weapons or WS.SelectedSlot - 1
    WS.SelectedSlotPos = Weapons[WS.SelectedSlot] and #Weapons[WS.SelectedSlot] or 0

    --print(WS.SelectedSlot, WS.SelectedSlotPos)

    if Weapons[WS.SelectedSlot] == nil or Weapons[WS.SelectedSlot][WS.SelectedSlotPos] == nil then
        GetUpper(Weapons)
    end
end

local function GetDown(Weapons)
    if #LocalPlayer():GetWeapons() < 1 then return end
    WS.SelectedSlot = WS.SelectedSlot > #Weapons and 0 or WS.SelectedSlot + 1
    WS.SelectedSlotPos = 0

    --print(WS.SelectedSlot, WS.SelectedSlotPos)

    if Weapons[WS.SelectedSlot] == nil or Weapons[WS.SelectedSlot][WS.SelectedSlotPos] == nil then
        GetDown(Weapons)
    end
end

local LastSelected = 0

local function get_active_tool(ply, tool)
    local activeWep = ply:GetActiveWeapon()
    if not IsValid(activeWep) or activeWep:GetClass() ~= "gmod_tool" or activeWep.Mode ~= tool then return end
    return activeWep:GetToolObject(tool)
end

local function canUseSelector(ply)
    local wep = ply:GetActiveWeapon()
    local tool = get_active_tool(ply, "submaterial")
    if tool and IsValid(ply:GetEyeTraceNoCursor().Entity) then
        return true
    end

    return IsAiming(ply) or (IsValid(wep) and wep:GetClass() == "weapon_physgun" and ply:KeyDown(IN_ATTACK)) or (lply.organism and lply.organism.pain and lply.organism.pain > 100) or GetGlobalBool("RadialInventory", false)
end

function WS.ChangeSelectionWep( ply, key )
    if not IsValid( ply ) or not ply:Alive() or GetGlobalBool("RadialInventory", false) then return end
    if ply.organism and ply.organism.otrub then return end
    if canUseSelector( ply ) then return end
    --print(canUseSelector( ply ))
    --print("Table")
    --PrintTable( WS.GetWeaponTable( ply ) )
    local iPos = tAcceptKeys[ key ]
    if iPos or key == "invnext" or key == "invprev" or key == "lastinv" then

        local Weapons = WS.GetWeaponTable( ply )

        WS.Show = CurTime() + 4
        --print(key)
        surface.PlaySound("arc9_eft_shared/weapon_generic_rifle_spin"..math.random(10)..".ogg")
        if iPos then
            iPos = iPos - 1
            if LastSelected ~= iPos then 
                WS.SelectedSlotPos = -1
            end
            WS.SelectedSlotPos = (Weapons[iPos] and LastSelected == iPos and WS.SelectedSlotPos + 1 > #Weapons[iPos] and 0 or math.min( WS.SelectedSlotPos + 1, #Weapons[iPos] )) or 0
            WS.SelectedSlot = iPos
            LastSelected = iPos
            --print(WS.SelectedSlotPos)
            --print(iPos)
            --print( Weapons[WS.SelectedSlot][WS.SelectedSlotPos] )
        elseif key == "invprev" then
            WS.SelectedSlotPos = WS.SelectedSlotPos - 1
            --print(WS.SelectedSlotPos)
            if Weapons[WS.SelectedSlot] and WS.SelectedSlotPos < 0  then
                GetUpper(Weapons)
            end
            --WS.SelectedSlot = Weapons[WS.SelectedSlot] and #Weapons[WS.SelectedSlot] > (WS.SelectedSlotPos + 1) and WS.SelectedSlot + 1 or WS.SelectedSlot + 1 > #Weapons - 1 and 0 or 0
        elseif key == "invnext" then
            WS.SelectedSlotPos = WS.SelectedSlotPos + 1
            --print(WS.SelectedSlotPos)
            if Weapons[WS.SelectedSlot] and WS.SelectedSlotPos > #Weapons[WS.SelectedSlot] then
                GetDown(Weapons)
            end
        elseif key == "lastinv" and IsValid(WS.LastInv) then
            WS.Show = 0
            WS.LastInv = WS.LastInv or "weapon_hands_sh"
            local oldwep = ply:GetActiveWeapon()
            input.SelectWeapon( WS.LastInv )
            WS.LastInv = oldwep
        end

    end
end

function WS.SetActuallyWeapon( ply, cmd )
    if not IsValid( ply ) or not ply:Alive() or GetGlobalBool("RadialInventory", false) then return end
    if (cmd:KeyDown( IN_ATTACK ) or cmd:KeyDown( IN_ATTACK2 )) and WS.Show > CurTime() then

        if WS.Selected and WS.Selected > CurTime() then 
            cmd:RemoveKey(IN_ATTACK) 
            cmd:RemoveKey(IN_ATTACK2) 
        else
            cmd:RemoveKey(IN_ATTACK)
            cmd:RemoveKey(IN_ATTACK2) 
            --print(WS.GetSelectedWeapon())
            
            if IsValid(WS.GetSelectedWeapon()) then
                WS.LastInv = WS.LastInv ~= ply:GetActiveWeapon() and WS.LastInv or ply:GetActiveWeapon()
                input.SelectWeapon( WS.GetSelectedWeapon() )
            end
            cmd:RemoveKey(IN_ATTACK)
            cmd:RemoveKey(IN_ATTACK2) 

            WS.LastSelectedSlot = WS.SelectedSlot
            WS.LastSelectedSlotPos = WS.SelectedSlotPos
            WS.Selected = CurTime() + 0.2
            WS.Show = CurTime() + 0.2
            surface.PlaySound("arc9_eft_shared/weapon_generic_spin"..math.random(1,10)..".ogg")
        end
    end
end

hook.Add( "PlayerBindPress", "WeaponSelector_PlayerBindPress", WS.ChangeSelectionWep )

hook.Add( "HUDPaint", "WeaponSelector_Draw", function()
    WS.WeaponSelectorDraw( LocalPlayer() )
end)

hook.Add( "StartCommand", "WeaponSelector_StartCommand", WS.SetActuallyWeapon )

local tHideElements = {
    ["CHudWeaponSelection"] = true
}

hook.Add("HUDShouldDraw", "WeaponSelector_HUDShouldDraw", function(sElementName)
    if tHideElements[sElementName] then return false end
end)

-- Я ТАК ЗАДОЛБАЛСЯ ПРОСТО УБЕЙТЕ МЕНЯ ХАХАХАХАХАХАХАХАХАХААХАХАХАХАХАХА
-- ПОЛЧАСА Я ПЫТАЛСЯ СДЕЛАТЬ НОРМЛАЬНОЕ ПЕРЕКЛЮЧЕНИЕ ГОВНА!!!
-- ЗАТО ПОЛУЧИЛОСЬ!!!!
-- УЭЭЭЭЭЭЭЭЭЭЭЭЭЭЭЭЭЭЭЭЭЭЭЭЭЭЭЭЭЭЭЭЭЭЭЭЭЭЭЭЭЭЭЭЭ
--[[
    /\_/\
    |_ _|
    |   |__
   /_|_____\ -- IT'S SO OVER
--]]