local ADDON_NAME, ADDON = ...

local DB_KEY
local biSPanel
local selectedSpecID = nil
local itemButtons = {}
local isLocked = false
local manuallyOpened = false
local openedByMinimap = false
local openedBySlashCommmand = false
local specDropdown

local sortOptions = {
    { text = "Drop Location", value = "location" },
    { text = "Item Type", value = "slot" },
}
local currentSortType = "location"
local collapsedGroups = {}

local GetItemInfoFunc = C_Item and C_Item.GetItemInfo or GetItemInfo
local GetItemInfoInstantFunc = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
local IsEquippableItemFunc = C_Item and C_Item.IsEquippableItem or IsEquippableItem
local GetItemIconFunc = C_Item and C_Item.GetItemIconByID or GetItemIcon
local GetItemQualityColorFunc = C_Item and C_Item.GetItemQualityColor or GetItemQualityColor
local RequestLoadItemDataByIDFunc = C_Item and C_Item.RequestLoadItemDataByID or RequestLoadItemDataByID

StaticPopupDialogs["BISJOURNAL_CHAT_SOURCE"] = {
    text = "Enter source information for %s\n(Format: \"Dungeon/Raid - Boss Name\")\n Exact location will allow click back to function",
    button1 = "Add to BiS Journal",
    button2 = CANCEL,
    hasEditBox = true,
    editBoxWidth = 250,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    displayMode = "input",
    OnShow = function(self, data)
        local editBox = self.EditBox or self.editBox or self.InputBox or self.inputBox
        if editBox then
            editBox:SetText("Delve - The War Within")
            editBox:HighlightText()
            editBox:SetFocus()
        end
        self.data = data
    end,


    OnAccept = function(self)
        local editBox = self.EditBox or self.InputBox or self.inputBox or nil
        local source = editBox and editBox:GetText() or ""
        if source == "" then
            source = "Unknown Source - Unknown Location"
        end
        AddToBiSList(self.data.itemID, source)
    end,
}

local function GetCurrentDBKey()
    local guid = UnitGUID("player")
    local specIndex

    -- If user chose a spec from the dropdown, use it
    if selectedSpecID then
        return guid .. "-" .. selectedSpecID
    end

    -- Otherwise default to current specialization
    specIndex = GetSpecialization()
    if not specIndex then return nil end
    local specID = GetSpecializationInfo(specIndex)
    return guid .. "-" .. specID
end

-- Database initialization
local function InitializeDB()
    BiSJournalDB.config.isLocked = BiSJournalDB.config.isLocked or false
    local specIndex = GetSpecialization()
    if not specIndex then return end
    
    local specID = GetSpecializationInfo(specIndex)
    local playerGUID = UnitGUID("player")
    
    DB_KEY = playerGUID.."-"..specID
    BiSJournalDB.lists[GetCurrentDBKey()] = BiSJournalDB.lists[GetCurrentDBKey()] or {}

    for slot, value in pairs(BiSJournalDB.lists[GetCurrentDBKey()]) do
        if type(value) ~= "table" then
            BiSJournalDB.lists[GetCurrentDBKey()][slot] = {value}
        end
    end
end

-- Item handling functions
local function GetItemSlotType(itemID)
    local _, _, _, _, _, _, _, _, itemEquipLoc = GetItemInfoFunc(itemID)
    -- If the item has no equipment location or empty location, it's not equippable
    if not itemEquipLoc or itemEquipLoc == "" or itemEquipLoc == "INVTYPE_NON_EQUIP_IGNORE" then
        return "Misc/Collectible"
    end
    
    return itemEquipLoc
end

local function FormatSlotText(slot)
    -- Handle our custom slot type
    if slot == "Misc/Collectible" then
        return "Misc/Collectible"
    end
    
    -- Remove the "INVTYPE_" prefix
    local formattedSlot = slot:gsub("^INVTYPE_", "")
    
    -- Capitalize the first letter (optional)
    formattedSlot = formattedSlot:sub(1, 1):upper() .. formattedSlot:sub(2):lower()
    
    -- Customize specific slot names if desired
    local customNames = {
        CHEST = "Chest Piece",
        HEAD = "Helmet",
        LEGS = "Leggings",
        FEET = "Boots",
        HANDS = "Gloves",
        FINGER = "Ring",
        TRINKET = "Trinket",
    }
    
    return customNames[formattedSlot] or formattedSlot
end

local function GenerateAcronym(name)
    return name:gsub("%w+", function(word) return word:sub(1,1) end):gsub("%s+", "")
end

local function GetCurrentAdventureGuideTab()
    if not EncounterJournal or not EncounterJournal:IsShown() then
        return nil, "Adventure Guide not open"
    end
    
    -- Check which tab is selected
    local tabIndex = PanelTemplates_GetSelectedTab(EncounterJournal)
    
    -- Map tab indices to names
    local tabNames = {
        [1] = "Traveler's Log",
        [2] = "Suggested Content",
        [3] = "Dungeons",
        [4] = "Raids",
        [5] = "Item Sets"
    }
    
    return tabIndex, tabNames[tabIndex] or "Unknown Tab"
end

function AddToBiSList(itemID, source)
    local currentKey = GetCurrentDBKey()
    if not itemID or not currentKey then return end

    -- Wait for item info if needed
    if not GetItemInfoFunc(itemID) then
        C_Timer.After(0.5, function() AddToBiSList(itemID, source) end)
        return
    end

    local slot = GetItemSlotType(itemID)
    -- IMPORTANT: Force non-equippable items to use "Misc/Collectible" as the slot
    local _, _, _, _, _, _, _, _, itemEquipLoc = GetItemInfoFunc(itemID)
    if not itemEquipLoc or itemEquipLoc == "" then
        slot = "Misc/Collectible"
    end

    if not slot then return end

        -- Force non-equippable items to use "Misc/Collectible" instead of "non_equip_ignore"
    if slot == "non_equip_ignore" then
        slot = "Misc/Collectible"
    end

    BiSJournalDB.lists[currentKey] = BiSJournalDB.lists[currentKey] or {}
    BiSJournalDB.lists[currentKey][slot] = BiSJournalDB.lists[currentKey][slot] or {}

    local isDuplicate = false
    for _, existingItem in ipairs(BiSJournalDB.lists[currentKey][slot]) do
        if type(existingItem) == "table" and existingItem.id == itemID then
            isDuplicate = true
            break
        elseif existingItem == itemID then -- Handle legacy data format
            isDuplicate = true
            break
        end
    end

    if not isDuplicate then
        local instanceName, bossName = source:match("(.+) %- (.+)")
        local shortenedSource

        if instanceName and bossName then     
            shortenedSource = source
        else
            shortenedSource = source
        end

        -- Determine source type
        local sourceType = "unknown"
        local tabIndex, tabName = GetCurrentAdventureGuideTab()
        local isDungeon = false
        
        if MerchantFrame and MerchantFrame:IsShown() then
            sourceType = "vendor"
        elseif tabName == "Dungeons" then
            sourceType = "instance"
            isDungeon = true
        elseif tabName == "Raids" then
            sourceType = "instance"
            isDungeon = false
        elseif source:match("World Quest") then
            sourceType = "worldquest"
        elseif source:match("Delve") then
            sourceType = "delve"
        elseif source:match("PvP") then
            sourceType = "pvp"
        elseif source:match("Crafted") then
            sourceType = "crafted"
        elseif source:match("Manual") then
            sourceType = "manual"
        else
            sourceType = "other"
        end

        local currentExpansion = EJ_GetCurrentTier()

        -- Store as a table with id, source, and sourceType
        local itemData = {
            id = itemID,
            fullSource = source,
            source = shortenedSource or "Unknown source",
            sourceType = sourceType,
            expansion = currentExpansion,
            isDungeon = isDungeon
        }

        table.insert(BiSJournalDB.lists[currentKey][slot], itemData)

        local itemName, itemLink = GetItemInfoFunc(itemID)
        print("|cFF00FF00Added|r " .. itemLink .. " |cFF00FF00to BiS list for slot:|r " .. FormatSlotText(slot))
        RefreshBiSPanel()
    else
        local itemName, itemLink = GetItemInfo(itemID)
        print("|cFFFFFF00Item|r " .. itemLink .. " |cFFFFFF00is already in your BiS list.|r")
    end

    RefreshBiSPanel()
end

function RemoveFromBiSList(slot, index)
    local currentKey = GetCurrentDBKey()
    if not DB_KEY then return end
    
    if BiSJournalDB.lists[currentKey][slot] and BiSJournalDB.lists[currentKey][slot][index] then
        local itemData = BiSJournalDB.lists[currentKey][slot][index]
        local itemID = type(itemData) == "table" and itemData.id or itemData
        local itemName, itemLink = GetItemInfoFunc(itemID)
        
        -- Remove the specific item at the index
        table.remove(BiSJournalDB.lists[currentKey][slot], index)
        
        -- If the slot is now empty, remove the slot entry
        if #BiSJournalDB.lists[currentKey][slot] == 0 then
            BiSJournalDB.lists[currentKey][slot] = nil
        end
        
        print("|cFFFF0000Removed|r " .. (itemLink or "item") .. " |cFFFF0000from BiS list.|r")
        RefreshBiSPanel()
    end
end

local function SafeCreateFontString(parent, layer, template)
    local fontString = parent:CreateFontString(nil, layer, template)
    if not fontString then
        -- Fallback to a basic font if the template is missing
        fontString = parent:CreateFontString(nil, layer)
        fontString:SetFont("Fonts\\FRIZQT__.TTF", 12) -- Default WoW font with size 12
    end
    return fontString
end

-- Create a minimap button
local minimapButton = CreateFrame("Button", "BiSJournalMinimapButton", Minimap)
_G["minimapButton"] = minimapButton
_G["BiSJournalMinimapButton"] = minimapButton
minimapButton:SetSize(32, 32)
minimapButton:SetFrameStrata("MEDIUM")
minimapButton:SetFrameLevel(8)
minimapButton:SetPoint("CENTER", Minimap, "CENTER", -80, -20) -- Default position

-- Set the button texture
local texture = minimapButton:CreateTexture(nil, "BACKGROUND")
texture:SetSize(18, 20)
texture:SetPoint("CENTER", minimapButton, "CENTER")
texture:SetTexture("Interface\\Icons\\INV_Misc_Book_09") -- You can choose a different icon
minimapButton.texture = texture

-- Add a border using a built-in template
local border = minimapButton:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetWidth(54)
border:SetHeight(54)
border:SetPoint("TOPLEFT", minimapButton, "TOPLEFT")

-- Add a border when hovering
minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

-- Make the button draggable around the minimap
minimapButton:RegisterForDrag("LeftButton")
minimapButton:SetScript("OnDragStart", minimapButton.StartMoving)
minimapButton:SetScript("OnDragStop", minimapButton.StopMovingOrSizing)

-- Set up the button's click behavior
minimapButton:SetScript("OnClick", function()
    if biSPanel:IsShown() then
        biSPanel:Hide()
        openedByMinimap = false
        openedBySlashCommmand = false
    else
        if BiSJournalDB.config.panelPosition then
            biSPanel:ClearAllPoints()
            biSPanel:SetPoint(
                BiSJournalDB.config.panelPosition.point,
                UIParent,
                BiSJournalDB.config.panelPosition.relativePoint,
                BiSJournalDB.config.panelPosition.xOfs,
                BiSJournalDB.config.panelPosition.yOfs
            )
        end
        biSPanel:Show()
        openedByMinimap = true
        openedBySlashCommmand = false
        C_Timer.After(0.2, RefreshBiSPanel)
    end
end)

-- Add tooltip
minimapButton:SetScript("OnEnter", function()
    GameTooltip:SetOwner(minimapButton, "ANCHOR_LEFT")
    GameTooltip:SetText("BiS Journal")
    GameTooltip:AddLine("Click to toggle the BiS Journal panel", 1, 1, 1)
    GameTooltip:Show()
end)
minimapButton:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

function SortItems(a, b)
    local function getSource(item)
        local s = item.fullSource or item.source or ""
        return tostring(s)
    end

    if currentSortType == "location" then
        return getSource(a):lower() < getSource(b):lower()
    elseif currentSortType == "slot" then
        local slotA = FormatSlotText(GetItemSlotType(a.id or a))
        local slotB = FormatSlotText(GetItemSlotType(b.id or b))
        return slotA < slotB
    elseif currentSortType == "name" then
        local nameA = GetItemInfoFunc(a.id or a) or ""
        local nameB = GetItemInfoFunc(b.id or b) or ""
        return nameA < nameB
    else
        return false
    end
end

-- UI refresh function
function RefreshBiSPanel()
    if not biSPanel or not biSPanel.content then return end

    local currentKey = GetCurrentDBKey()
    if not currentKey or not BiSJournalDB.lists[currentKey] then return end

    local panelWidth = biSPanel:GetWidth()
    local panelHeight = biSPanel:GetHeight()
    local instructions = biSPanel.instructions
    if instructions then instructions:SetWidth(panelWidth - 40) end

    local scrollFrame = biSPanel.content:GetParent()
    scrollFrame:SetSize(panelWidth - 30, panelHeight - 100)
    biSPanel.content:SetWidth(panelWidth - 50)

    -- Use distinct button pools for headers/items to prevent index conflicts!
    biSPanel.headerButtons = biSPanel.headerButtons or {}
    biSPanel.itemButtons = biSPanel.itemButtons or {}

    -- Hide all existing buttons first
    for _, btn in ipairs(biSPanel.headerButtons) do btn:Hide() end
    for _, btn in ipairs(biSPanel.itemButtons) do btn:Hide() end

    local content = biSPanel.content
    local yOffset = 5
    local needsRefresh = false
    collapsedGroups = collapsedGroups or {}

    -- Collapse All Button (create once and reuse)
    if not biSPanel.collapseAllButton then
        local btn = CreateFrame("Button", nil, biSPanel, "UIPanelButtonTemplate")
        btn:SetSize(100, 22)
        biSPanel.collapseAllButton = btn
    end
    local collapseAllButton = biSPanel.collapseAllButton
    collapseAllButton:Hide() -- Hide by default, show only if more than one group

    if currentSortType == "location" then
        -- Build groups by source/instance name
        local groups = {}
        for slot, items in pairs(BiSJournalDB.lists[currentKey]) do
            for itemIndex, itemData in ipairs(items) do
                local groupName = "Other"
                if type(itemData) == "table" and itemData.fullSource then
                    local inst = itemData.fullSource:match("(.+) %- .+")
                    if inst and inst ~= "" then
                        groupName = inst
                    else
                        groupName = itemData.fullSource
                    end
                end
                if not groupName or groupName == "" then groupName = "Other" end
                groups[groupName] = groups[groupName] or {}
                table.insert(groups[groupName], { slot = slot, itemData = itemData, itemIndex = itemIndex })
            end
        end

        local sortedGroupNames = {}
        for groupName in pairs(groups) do table.insert(sortedGroupNames, groupName) end
        table.sort(sortedGroupNames)

        -- Ensure all are collapsed by default
        for _, groupName in ipairs(sortedGroupNames) do
            if collapsedGroups[groupName] == nil then
                collapsedGroups[groupName] = true
            end
        end

        -- Toggle logic
        local allCollapsed = true
        for _, groupName in ipairs(sortedGroupNames) do
            if not collapsedGroups[groupName] then
                allCollapsed = false
                break
            end
        end

        if #sortedGroupNames > 1 then
            collapseAllButton:ClearAllPoints()
            collapseAllButton:Show()
            collapseAllButton:SetPoint("TOPLEFT", biSPanel, "TOPLEFT", 10, -10)

            if allCollapsed then
                collapseAllButton:SetText("Expand All")
                collapseAllButton:SetScript("OnClick", function()
                    for _, groupName in ipairs(sortedGroupNames) do
                        collapsedGroups[groupName] = false
                    end
                    RefreshBiSPanel()
                end)
            else
                collapseAllButton:SetText("Collapse All")
                collapseAllButton:SetScript("OnClick", function()
                    for _, groupName in ipairs(sortedGroupNames) do
                        collapsedGroups[groupName] = true
                    end
                    RefreshBiSPanel()
                end)
            end
        else
            collapseAllButton:Hide()
        end

        -- Draw headers/items
        local headerIdx = 1
        local itemIdx = 1
        for _, groupName in ipairs(sortedGroupNames) do
            local groupItems = groups[groupName]
            -- HEADER BUTTON
            local headerButton = biSPanel.headerButtons[headerIdx]
            if not headerButton then
                headerButton = CreateFrame("Button", nil, content)
                headerButton:SetSize(250, 24)
                local icon = headerButton:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
                icon:SetPoint("LEFT", 0, 0)
                headerButton.icon = icon
                local text = headerButton:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
                text:SetPoint("LEFT", icon, "RIGHT", 2, 0)
                headerButton.text = text
                biSPanel.headerButtons[headerIdx] = headerButton
            end

            local isCollapsed = collapsedGroups[groupName]
            headerButton.icon:SetText(isCollapsed and "+" or "-")
            headerButton.text:SetText(groupName)
            headerButton:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -yOffset)
            headerButton:Show()
            headerButton:SetScript("OnClick", function()
                collapsedGroups[groupName] = not collapsedGroups[groupName]
                RefreshBiSPanel()
            end)
            yOffset = yOffset + 24
            headerIdx = headerIdx + 1

            -- ITEM BUTTONS
            if not isCollapsed then
                for _, info in ipairs(groupItems) do
                    local itemData = info.itemData
                    local slot = info.slot
                    local itemID = type(itemData) == "table" and itemData.id or itemData
                    local itemName = GetItemInfoFunc(itemID)
                    if not itemName then
                        needsRefresh = true
                        C_Item.RequestLoadItemDataByID(itemID)
                    else
                        local button = biSPanel.itemButtons[itemIdx]
                        if not button then
                            button = CreateFrame("Button", nil, content)
                            button:SetSize(250, 60)
                            local icon = button:CreateTexture(nil, "ARTWORK")
                            icon:SetSize(45, 45)
                            icon:SetPoint("LEFT", 0, 6)
                            button.icon = icon
                            local text = SafeCreateFontString(button, "OVERLAY", "GameFontNormal")
                            text:SetPoint("TOPLEFT", icon, "TOPRIGHT", 5, -2)
                            text:SetWidth(180)
                            text:SetJustifyH("LEFT")
                            text:SetWordWrap(false)
                            text:SetHeight(12)
                            button.text = text
                            text:SetFont(text:GetFont(), 13)
                            local sourceText = SafeCreateFontString(button, "OVERLAY", "GameFontHighlight")
                            sourceText:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -5)
                            sourceText:SetWidth(180)
                            sourceText:SetJustifyH("LEFT")
                            sourceText:SetHeight(10)
                            sourceText:SetWordWrap(false)
                            sourceText:SetTextColor(0, 0.8, 1)
                            if sourceText.SetNonSpaceWrap then sourceText:SetNonSpaceWrap(false) end
                            button.sourceText = sourceText
                            local slotText = SafeCreateFontString(button, "OVERLAY", "GameFontNormal")
                            slotText:SetPoint("TOPLEFT", sourceText, "BOTTOMLEFT", 0, -2)
                            slotText:SetWidth(180)
                            slotText:SetJustifyH("LEFT")
                            slotText:SetTextColor(0.7, 0.7, 0.7)
                            button.slotText = slotText
                            local removeButton = CreateFrame("Button", nil, button, "UIPanelCloseButton")
                            removeButton:SetSize(20, 20)
                            removeButton:SetPoint("RIGHT", -5, 0)
                            button.removeButton = removeButton
                            biSPanel.itemButtons[itemIdx] = button
                        end

                        local itemName, itemLink, itemRarity, _, _, _, _, _, _, itemTexture = GetItemInfoFunc(itemID)
                        button.icon:SetTexture(itemTexture)
                        button.text:SetText(itemLink or itemName)
                        -- Only show boss name (NOT instance) for location sort
                        local sourceToUse = itemData.fullSource or itemData.source
                        local instanceName, bossName = sourceToUse and sourceToUse:match("(.+) %- (.+)")
                        if bossName and bossName ~= "" then
                            button.sourceText:SetText(bossName)
                        elseif sourceToUse and sourceToUse ~= "" then
                            local dashIdx = sourceToUse:find("%-")
                            if dashIdx then
                                local afterDash = sourceToUse:sub(dashIdx + 1):gsub("^%s+", "")
                                button.sourceText:SetText(afterDash)
                            else
                                button.sourceText:SetText(sourceToUse)
                            end
                        else
                            button.sourceText:SetText("Unknown source")
                        end
                        if button.bossText then button.bossText:SetText(""); button.bossText:Hide() end
                        button.slotText:SetPoint("TOPLEFT", button.sourceText, "BOTTOMLEFT", 0, -5)
                        local actualSlotType = GetItemSlotType(itemID)
                        local slotDisplay = FormatSlotText(actualSlotType)
                        if #BiSJournalDB.lists[currentKey][slot] > 1 then
                            slotDisplay = slotDisplay .. " #" .. info.itemIndex
                        end
                        button.slotText:SetText(slotDisplay)
                        button.slot = slot
                        button.itemIndex = info.itemIndex
                        button.removeButton:SetScript("OnClick", function()
                            RemoveFromBiSList(button.slot, button.itemIndex)
                        end)
                        button:SetScript("OnEnter", function()
                            GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
                            GameTooltip:SetItemByID(itemID)
                            GameTooltip:Show()
                        end)
                        button:SetScript("OnClick", function(self)
                            local itemData = BiSJournalDB.lists[currentKey][slot][info.itemIndex]
                            if type(itemData) == "table" then
                                local sourceToUse = itemData.fullSource or itemData.source
                                local sourceType = itemData.sourceType or "unknown"
                                local expansion = itemData.expansion
                                if sourceType == "vendor" then
                                    local instanceName, vendorName = sourceToUse:match("(.+) %- (.+)")
                                    if instanceName and vendorName then
                                        print("Visit " .. vendorName .. " in " .. instanceName .. " to purchase this item.")
                                    else
                                        print("Vendor information incomplete for this item.")
                                    end
                                elseif sourceType == "instance" then
                                    local instanceName, bossName = sourceToUse:match("(.+) %- (.+)")
                                    if instanceName and bossName then
                                        OpenAdventureGuideToSource(instanceName, bossName, expansion, itemData.isDungeon)
                                    else
                                        print("Instance information incomplete for this item.")
                                    end
                                else
                                    local instanceName, bossName = sourceToUse:match("(.+) %- (.+)")
                                    if instanceName and bossName then
                                        print("This item was added using an older version of BiSJournal or manually added. It drops from " .. bossName .. " in " .. instanceName .. ".")
                                    else
                                        print("Source information incomplete for this item. Add this item again for Adventure Guide functionality.")
                                    end
                                end
                            end
                        end)
                        button:SetScript("OnLeave", function()
                            GameTooltip:Hide()
                        end)
                        button:SetPoint("TOPLEFT", content, "TOPLEFT", 30, -yOffset)
                        button:Show()
                        yOffset = yOffset + 48
                        itemIdx = itemIdx + 1
                    end
                end
            end
        end
        -- Clean up unused header/item buttons
        for i = headerIdx, #biSPanel.headerButtons do
            if biSPanel.headerButtons[i] then biSPanel.headerButtons[i]:Hide() end
        end
        for i = itemIdx, #biSPanel.itemButtons do
            if biSPanel.itemButtons[i] then biSPanel.itemButtons[i]:Hide() end
        end

    elseif currentSortType == "slot" then
        -- Build groups by slot
        local groups = {}
        for slot, items in pairs(BiSJournalDB.lists[currentKey]) do
            local slotDisplay = FormatSlotText(slot)
            groups[slotDisplay] = groups[slotDisplay] or {}
            for itemIndex, itemData in ipairs(items) do
                table.insert(groups[slotDisplay], {
                    slot = slot,
                    itemData = itemData,
                    itemIndex = itemIndex,
                })
            end
        end

        local sortedSlotNames = {}
        for slotName in pairs(groups) do table.insert(sortedSlotNames, slotName) end
        table.sort(sortedSlotNames)

        -- Ensure all are collapsed by default
        for _, slotName in ipairs(sortedSlotNames) do
            if collapsedGroups[slotName] == nil then
                collapsedGroups[slotName] = true
            end
        end

        -- Toggle logic
        local allCollapsed = true
        for _, slotName in ipairs(sortedSlotNames) do
            if not collapsedGroups[slotName] then
                allCollapsed = false
                break
            end
        end

        if #sortedSlotNames > 1 then
            collapseAllButton:ClearAllPoints()
            collapseAllButton:Show()
            collapseAllButton:SetPoint("TOPLEFT", biSPanel, "TOPLEFT", 10, -10)

            if allCollapsed then
                collapseAllButton:SetText("Expand All")
                collapseAllButton:SetScript("OnClick", function()
                    for _, slotName in ipairs(sortedSlotNames) do
                        collapsedGroups[slotName] = false
                    end
                    RefreshBiSPanel()
                end)
            else
                collapseAllButton:SetText("Collapse All")
                collapseAllButton:SetScript("OnClick", function()
                    for _, slotName in ipairs(sortedSlotNames) do
                        collapsedGroups[slotName] = true
                    end
                    RefreshBiSPanel()
                end)
            end
        else
            collapseAllButton:Hide()
        end

        local headerIdx = 1
        local itemIdx = 1
        for _, slotDisplay in ipairs(sortedSlotNames) do
            local groupItems = groups[slotDisplay]
            -- HEADER BUTTON
            local headerButton = biSPanel.headerButtons[headerIdx]
            if not headerButton then
                headerButton = CreateFrame("Button", nil, content)
                headerButton:SetSize(250, 24)
                local icon = headerButton:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
                icon:SetPoint("LEFT", 0, 0)
                headerButton.icon = icon
                local text = headerButton:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
                text:SetPoint("LEFT", icon, "RIGHT", 2, 0)
                headerButton.text = text
                biSPanel.headerButtons[headerIdx] = headerButton
            end

            local isCollapsed = collapsedGroups[slotDisplay]
            headerButton.icon:SetText(isCollapsed and "+" or "-")
            headerButton.text:SetText(slotDisplay)
            headerButton:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -yOffset)
            headerButton:Show()
            headerButton:SetScript("OnClick", function()
                collapsedGroups[slotDisplay] = not collapsedGroups[slotDisplay]
                RefreshBiSPanel()
            end)
            yOffset = yOffset + 24
            headerIdx = headerIdx + 1

            if not isCollapsed then
                for _, info in ipairs(groupItems) do
                    local itemData = info.itemData
                    local slot = info.slot
                    local itemID = type(itemData) == "table" and itemData.id or itemData
                    local itemName = GetItemInfoFunc(itemID)
                    if not itemName then
                        needsRefresh = true
                        C_Item.RequestLoadItemDataByID(itemID)
                    else
                        local button = biSPanel.itemButtons[itemIdx]
                        if not button then
                            button = CreateFrame("Button", nil, content)
                            button:SetSize(250, 60)
                            local icon = button:CreateTexture(nil, "ARTWORK")
                            icon:SetSize(45, 45)
                            icon:SetPoint("LEFT", 0, 6)
                            button.icon = icon
                            local text = SafeCreateFontString(button, "OVERLAY", "GameFontNormal")
                            text:SetPoint("TOPLEFT", icon, "TOPRIGHT", 5, -2)
                            text:SetWidth(180)
                            text:SetJustifyH("LEFT")
                            text:SetWordWrap(false)
                            text:SetHeight(12)
                            button.text = text
                            text:SetFont(text:GetFont(), 13)
                            local sourceText = SafeCreateFontString(button, "OVERLAY", "GameFontHighlight")
                            sourceText:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -5)
                            sourceText:SetWidth(180)
                            sourceText:SetJustifyH("LEFT")
                            sourceText:SetHeight(10)
                            sourceText:SetWordWrap(false)
                            sourceText:SetTextColor(0, 0.8, 1)
                            if sourceText.SetNonSpaceWrap then sourceText:SetNonSpaceWrap(false) end
                            button.sourceText = sourceText
                            button.slotText = nil -- DON'T SHOW slot label.
                            local removeButton = CreateFrame("Button", nil, button, "UIPanelCloseButton")
                            removeButton:SetSize(20, 20)
                            removeButton:SetPoint("RIGHT", -5, 0)
                            button.removeButton = removeButton
                            biSPanel.itemButtons[itemIdx] = button
                        end
                        if button.slotText then button.slotText:Hide() end
                        local itemName, itemLink, itemRarity, _, _, _, _, _, _, itemTexture = GetItemInfoFunc(itemID)
                        button.icon:SetTexture(itemTexture)
                        button.text:SetText(itemLink or itemName)
                        if type(itemData) == "table" then
                            local sourceToUse = itemData.fullSource or itemData.source
                            local instanceName, bossName = sourceToUse and sourceToUse:match("(.+) %- (.+)")
                            if instanceName and bossName then
                                button.sourceText:SetText(instanceName)
                                if not button.bossText then
                                    button.bossText = SafeCreateFontString(button, "OVERLAY", "GameFontHighlight")
                                    button.bossText:SetPoint("TOPLEFT", button.sourceText, "BOTTOMLEFT", 0, -5)
                                    button.bossText:SetWidth(180)
                                    button.bossText:SetJustifyH("LEFT")
                                    button.bossText:SetHeight(10)
                                    button.bossText:SetWordWrap(false)
                                    button.bossText:SetTextColor(1, 0.82, 0)
                                end
                                button.bossText:SetText(bossName)
                                button.bossText:Show()
                            else
                                button.sourceText:SetText(sourceToUse or "Unknown source")
                                if button.bossText then button.bossText:SetText(""); button.bossText:Hide() end
                            end
                        else
                            button.sourceText:SetText("Unknown source")
                            if button.bossText then button.bossText:SetText(""); button.bossText:Hide() end
                        end
                        button:SetPoint("TOPLEFT", content, "TOPLEFT", 30, -yOffset)
                        button:Show()
                        yOffset = yOffset + 48
                        itemIdx = itemIdx + 1
                        button.slot = slot
                        button.itemIndex = info.itemIndex
                        button.removeButton:SetScript("OnClick", function()
                            RemoveFromBiSList(button.slot, button.itemIndex)
                        end)
                        button:SetScript("OnEnter", function()
                            GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
                            GameTooltip:SetItemByID(itemID)
                            GameTooltip:Show()
                        end)
                        button:SetScript("OnClick", function(self)
                            local itemData = BiSJournalDB.lists[currentKey][slot][info.itemIndex]
                            if type(itemData) == "table" then
                                local sourceToUse = itemData.fullSource or itemData.source
                                local sourceType = itemData.sourceType or "unknown"
                                local expansion = itemData.expansion
                                if sourceType == "vendor" then
                                    local instanceName, vendorName = sourceToUse:match("(.+) %- (.+)")
                                    if instanceName and vendorName then
                                        print("Visit " .. vendorName .. " in " .. instanceName .. " to purchase this item.")
                                    else
                                        print("Vendor information incomplete for this item.")
                                    end
                                elseif sourceType == "instance" then
                                    local instanceName, bossName = sourceToUse:match("(.+) %- (.+)")
                                    if instanceName and bossName then
                                        OpenAdventureGuideToSource(instanceName, bossName, expansion, itemData.isDungeon)
                                    else
                                        print("Instance information incomplete for this item.")
                                    end
                                else
                                    local instanceName, bossName = sourceToUse:match("(.+) %- (.+)")
                                    if instanceName and bossName then
                                        print("This item was added using an older version of BiSJournal or manually added. It drops from " .. bossName .. " in " .. instanceName .. ".")
                                    else
                                        print("Source information incomplete for this item. Add this item again for Adventure Guide functionality.")
                                    end
                                end
                            end
                        end)
                        button:SetScript("OnLeave", function()
                            GameTooltip:Hide()
                        end)
                    end
                end
            end
        end
        for i = headerIdx, #biSPanel.headerButtons do
            if biSPanel.headerButtons[i] then biSPanel.headerButtons[i]:Hide() end
        end
        for i = itemIdx, #biSPanel.itemButtons do
            if biSPanel.itemButtons[i] then biSPanel.itemButtons[i]:Hide() end
        end
    end

    if needsRefresh then
        C_Timer.After(0.5, RefreshBiSPanel)
    end

    content:SetHeight(math.max(yOffset, 400))
    local contentHeight = math.max(yOffset, scrollFrame:GetHeight())
    biSPanel.content:SetHeight(contentHeight)
    local scrollbar = scrollFrame.ScrollBar
    if scrollbar then
        scrollbar:SetMinMaxValues(0, math.max(0, contentHeight - scrollFrame:GetHeight()))
    end
end

local function IsCollectible(itemID)
    local _, _, _, _, _, itemType, itemSubType = GetItemInfoFunc(itemID)
    -- Check for toys, mounts, pets, etc.
    if itemType == "Miscellaneous" and (
       itemSubType == "Companion Pets" or
       itemSubType == "Mount" or
       itemSubType == "Toy") then
        return true
    end
    return false
end

local function HandleJournalClick(button)
    if IsModifiedClick("ALT") and button.itemID then -- Check for Alt key press and valid item ID.
        local source = "Unknown source" 

        if EncounterJournal and EncounterJournal.encounterID then
            local encounterName = EJ_GetEncounterInfo(EncounterJournal.encounterID)
            local instanceName = EJ_GetInstanceInfo()

            if encounterName and instanceName then
                source = instanceName .. " - " .. encounterName
            elseif instanceName then
                source = instanceName
            end
        end
        AddToBiSList(button.itemID, source) -- Add the clicked loot to the BiS list.
    end
end

-- For Merchant items
local function HandleVendorClick(button, merchantItemIndex)
    if IsModifiedClick("ALT") then
        -- Calculate the actual index based on the current page
        local currentPage = MerchantFrame.page
        local actualIndex = ((currentPage - 1) * MERCHANT_ITEMS_PER_PAGE) + merchantItemIndex
        
        local itemLink = GetMerchantItemLink(actualIndex)
        if itemLink then
            local itemID = tonumber(itemLink:match("item:(%d+)"))
            if itemID then
                local vendorName = UnitName("npc")
                local zoneName = GetZoneText()
                local source = zoneName .. " - " .. vendorName
                AddToBiSList(itemID, source)
            end
        end
    end
end

local function MigrateShortNames()
    if not BiSJournalDB or not BiSJournalDB.lists then return end
    
    for key, list in pairs(BiSJournalDB.lists) do
        for slot, items in pairs(list) do
            if type(items) == "table" then
                for i, item in ipairs(items) do
                    if type(item) == "table" and item.fullSource then
                        -- If we have the full source, use it for the shortened source too
                        item.source = item.fullSource
                    end
                end
            end
        end
    end
    
    -- Update version
    BiSJournalDB.config.version = 1.2
end

local function MigrateDatabase()
    if not BiSJournalDB or not BiSJournalDB.lists then return end
    
    for key, list in pairs(BiSJournalDB.lists) do
        for slot, items in pairs(list) do
            if type(items) == "table" then
                for i, item in ipairs(items) do
                    if type(item) ~= "table" then
                        -- Convert to new format
                        items[i] = {
                            id = item,
                            source = "Unknown source"
                        }
                    end
                end
            end
        end
    end
    
    -- Add migration for shortened names
    MigrateShortNames()
    
    -- Update version
    BiSJournalDB.config.version = 1.2
end

local function HookJournalButtons()
    if not EncounterJournal or not EncounterJournal.encounter then
        C_Timer.After(1, HookJournalButtons) -- Retry until Encounter Journal is loaded.
        return
    end
    
    -- Access the correct path to the loot container
    local lootContainer = EncounterJournal.encounter.info.LootContainer
    if not lootContainer then
        print("BiSJournal: LootContainer not found")
        C_Timer.After(1, HookJournalButtons)
        return
    end
    
    local scrollBox = lootContainer.ScrollBox
    if not scrollBox then
        print("BiSJournal: ScrollBox not found")
        C_Timer.After(1, HookJournalButtons)
        return
    end
    
    -- Try to hook both the ScrollBox frames and any child frames
    if scrollBox.ScrollTarget then
        -- Hook the scroll target's children (the actual item buttons)
        for i, child in ipairs({scrollBox.ScrollTarget:GetChildren()}) do
            if child and not child.HookedBiS then
                
                -- Use OnMouseDown instead of PreClick
                child:HookScript("OnMouseDown", function(self, button)
                    if IsModifiedClick("ALT") and self.itemID then
                        -- Store the itemID before UI changes
                        local itemID = self.itemID
                        
                        -- Get source information immediately
                        local source = "Unknown source"
                        local instanceName = EJ_GetInstanceInfo()
                        local bossName = nil
                        
                        if self.encounterID then
                            bossName = EJ_GetEncounterInfo(self.encounterID)
                        elseif self.link and self.link:match("encounterID:(%d+)") then
                            local encounterID = self.link:match("encounterID:(%d+)")
                            bossName = EJ_GetEncounterInfo(tonumber(encounterID))
                        end
                        
                        if instanceName then
                            if bossName then
                                source = instanceName .. " - " .. bossName
                            else
                                source = instanceName .. " - Unknown Boss"
                            end
                        end
                        
                        -- Use a slight delay to ensure the click completes first
                        C_Timer.After(0.1, function()
                            AddToBiSList(itemID, source)
                        end)
                    end
                end)
                
                child.HookedBiS = true
            end
        end
    else
        print("BiSJournal: ScrollTarget not found")
    end
    
    -- Also try the old method as a fallback
    scrollBox:ForEachFrame(function(button)
        if button and not button.HookedBiS then
            
            -- Use OnMouseDown instead of PreClick
            button:HookScript("OnMouseDown", function(self, button)
                if IsModifiedClick("ALT") and self.itemID then
                    -- Same code as above
                    local itemID = self.itemID
                    local source = "Unknown source"
                    local instanceName = EJ_GetInstanceInfo()
                    local bossName = nil
                    
                    if self.encounterID then
                        bossName = EJ_GetEncounterInfo(self.encounterID)
                    elseif self.link and self.link:match("encounterID:(%d+)") then
                        local encounterID = self.link:match("encounterID:(%d+)")
                        bossName = EJ_GetEncounterInfo(tonumber(encounterID))
                    end
                    
                    if instanceName then
                        if bossName then
                            source = instanceName .. " - " .. bossName
                        else
                            source = instanceName .. " - Unknown Boss"
                        end
                    end
                    
                    C_Timer.After(0.1, function()
                        AddToBiSList(itemID, source)
                    end)
                end
            end)
            
            button.HookedBiS = true
        end
    end)
    
    -- Schedule another check to catch any new buttons
    C_Timer.After(5, HookJournalButtons)
end

local function HookMerchantButtons()
    -- Check if merchant frame exists
    if not MerchantFrame then
        C_Timer.After(1, HookMerchantButtons) -- Retry until loaded
        return
    end
    
    -- Hook the merchant update function to handle page changes
    if not MerchantFrame.HookedBiSUpdate then
        hooksecurefunc("MerchantFrame_UpdateMerchantInfo", function()
            -- This runs whenever the merchant page changes
            for i = 1, MERCHANT_ITEMS_PER_PAGE do
                local button = _G["MerchantItem"..i.."ItemButton"]
                if button and not button.HookedBiS then
                    button:HookScript("OnClick", function(self, mouseButton)
                        if mouseButton == "LeftButton" then
                            local merchantItemIndex = i -- Use the loop index directly
                            HandleVendorClick(self, merchantItemIndex)
                        end
                    end)
                    button.HookedBiS = true
                end
            end
        end)
        MerchantFrame.HookedBiSUpdate = true
    end
    
    -- Initial hook for the first page
    for i = 1, MERCHANT_ITEMS_PER_PAGE do
        local button = _G["MerchantItem"..i.."ItemButton"]
        if button and not button.HookedBiS then
            button:HookScript("OnClick", function(self, mouseButton)
                if mouseButton == "LeftButton" then
                    local merchantItemIndex = i -- Use the loop index directly
                    HandleVendorClick(self, merchantItemIndex)
                end
            end)
            button.HookedBiS = true
        end
    end
end

-- Set the default position
local function SetDefaultPosition()
    if biSPanel and EncounterJournal and EncounterJournal:IsShown() then
        biSPanel:ClearAllPoints()
        biSPanel:SetPoint("TOPLEFT", EncounterJournal, "TOPRIGHT", 20, 0)
    else
        -- Default position when Adventure Guide isn't open
        biSPanel:ClearAllPoints()
        biSPanel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

local function GetAllPlayerSpecs()
    local specs = {}
    local numSpecs = GetNumSpecializations()
    for i = 1, numSpecs do
        local specID, specName, _, icon = GetSpecializationInfo(i)
        table.insert(specs, { id = specID, name = specName, icon = icon })
    end
    return specs
end

local function SetDropdownTextToCurrent(specDropdown)
    local specIndex = GetSpecialization()
    if not specIndex then return end
    local currentSpecID = GetSpecializationInfo(specIndex)
    local _, currentName = GetSpecializationInfoByID(currentSpecID)
    if selectedSpecID then
        local specs = GetAllPlayerSpecs()
        for _, spec in ipairs(specs) do
            if spec.id == selectedSpecID then
                UIDropDownMenu_SetText(specDropdown, spec.name)
                return
            end
        end
    else
        UIDropDownMenu_SetText(specDropdown, currentName)
    end
    local label = _G[specDropdown:GetName().."Text"]
    if label then label:SetJustifyH("CENTER") end
end

-- Initialize state
local isLocked = false

-- Create the main panel
local function CreateBiSPanel()
    -- Main panel - no longer parented to EncounterJournal
    biSPanel = CreateFrame("Frame", "BiSJournalPanel", UIParent, "BackdropTemplate,ResizeLayoutFrame")
    biSPanel:SetSize(BiSJournalDB.config.width or 325, BiSJournalDB.config.height or 500)
    biSPanel:SetPoint("CENTER", UIParent, "CENTER", 0, 0) -- Center it on screen initially
    biSPanel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 2 }
    })
    
    -- Apply initial color
    local colorOption = BiSJournalDB.config.colorOption or 1
    if ADDON.colorOptions and ADDON.colorOptions[colorOption] then
        local colorValue = ADDON.colorOptions[colorOption].value
        
        biSPanel:SetBackdropColor(0, 0, 0, BiSJournalDB.config.opacity or 1.0)
    end

    biSPanel:SetMovable(true)
    biSPanel:EnableMouse(true)
    biSPanel:RegisterForDrag("LeftButton")
    biSPanel:SetScript("OnDragStart", biSPanel.StartMoving)
    biSPanel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, xOfs, yOfs = self:GetPoint()
        BiSJournalDB.config.panelPosition = {
            point = point,
            relativePoint = relativePoint,
            xOfs = xOfs,
            yOfs = yOfs
        }
    end)

    local resizeButton = CreateFrame("Button", nil, biSPanel)
    resizeButton:SetSize(16, 16)
    resizeButton:SetPoint("BOTTOMRIGHT", -2, 2)
    resizeButton:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeButton:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeButton:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

    biSPanel:SetResizable(true)
    biSPanel:SetResizeBounds(325, 200, 325, 900)

    if isLocked then
        resizeButton:Hide()
    else
        resizeButton:Show()
    end

    -- Add this after your resize button creation
    resizeButton:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            biSPanel:StartSizing("BOTTOMRIGHT")
            self.isSizing = true
            self:SetScript("OnUpdate", function()
                -- Update content during resize
                local scrollFrame = biSPanel.content:GetParent()
                local panelWidth = biSPanel:GetWidth()
                local panelHeight = biSPanel:GetHeight()
                
                -- Adjust scrollFrame size
                scrollFrame:SetSize(panelWidth - 30, panelHeight - 100)
                
                -- Adjust content width
                biSPanel.content:SetWidth(panelWidth - 50)
            end)
        end
    end)

    resizeButton:SetScript("OnMouseUp", function(self, button)
        biSPanel:StopMovingOrSizing()
        self.isSizing = false
        self:SetScript("OnUpdate", nil)
        
        -- Save the new size
        BiSJournalDB.config.width = biSPanel:GetWidth()
        BiSJournalDB.config.height = biSPanel:GetHeight()
        
        -- Refresh the panel content
        RefreshBiSPanel()
    end)
   
    -- Title
    local title = biSPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetText("BiS Journal")
    title:SetPoint("TOP", 0, -15)

    specDropdown = CreateFrame("Frame", "BiSJournalSpecDropdown", biSPanel, "UIDropDownMenuTemplate")
    specDropdown:SetPoint("BOTTOM", title, "TOP", 0, 7)
    UIDropDownMenu_SetWidth(specDropdown, 180)

    -- Dropdown menu population
    local function InitializeSpecDropdown(self, level)
        local specs = GetAllPlayerSpecs()
        for _, spec in ipairs(specs) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = spec.name
            info.icon = spec.icon
            info.checked = (selectedSpecID == spec.id) or (selectedSpecID == nil and GetSpecializationInfo(GetSpecialization()) == spec.id)
            info.func = function()
                selectedSpecID = spec.id
                UIDropDownMenu_SetText(specDropdown, spec.name)
                -- Ensure the per-spec table exists before refresh
                local currentKey = GetCurrentDBKey()
                if not BiSJournalDB.lists[currentKey] then
                    BiSJournalDB.lists[currentKey] = {}
                end
                RefreshBiSPanel()
            end
            UIDropDownMenu_AddButton(info, level)
        end
        -- Option: 'Current Spec' (resets to auto-follow)
        local info = UIDropDownMenu_CreateInfo()
        info.text = "|cff00ff00Follow My Current Spec|r"
        info.notCheckable = false
        info.checked = (selectedSpecID == nil)
        info.func = function()
            selectedSpecID = nil
            -- Ensure the table for the current spec exists if needed
            local currentKey = GetCurrentDBKey()
            if not BiSJournalDB.lists[currentKey] then
                BiSJournalDB.lists[currentKey] = {}
            end
            SetDropdownTextToCurrent(specDropdown)
            RefreshBiSPanel()
        end
        UIDropDownMenu_AddButton(info, level)
    end
    UIDropDownMenu_Initialize(specDropdown, InitializeSpecDropdown)
    SetDropdownTextToCurrent(specDropdown)

    -- Instructions
    local instructions = biSPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    instructions:SetText("Alt+Click items in the Adventure Guide/Vendor/Chat to add them")
    instructions:SetPoint("TOP", title, "BOTTOM", 0, -10)
    biSPanel.instructions = instructions  -- Add this line here

    -- Scrollframe for items
    local scrollFrame = CreateFrame("ScrollFrame", nil, biSPanel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetSize(270, 400)
    scrollFrame:SetPoint("TOP", instructions, "BOTTOM", 0, -10)
    biSPanel.scrollFrame = scrollFrame  -- Add this line here

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(270, 1) -- Height will be adjusted dynamically
    scrollFrame:SetScrollChild(content)
    biSPanel.content = content

    -- Close button
    local closeButton = CreateFrame("Button", nil, biSPanel, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -5, -5)

    closeButton:SetScript("OnClick", function()
        openedByMinimap = false
        openedBySlashCommmand = false
        biSPanel:Hide()
    end)    

    -- Lock button (add this code)
    local lockButton = CreateFrame("Button", "BiSJournalLockButton", biSPanel)
    lockButton:SetSize(24, 24)
    lockButton:SetPoint("TOPRIGHT", closeButton, "TOPLEFT", -5, 0)

    lockButton.lockedTexture = lockButton:CreateTexture(nil, "ARTWORK")
    lockButton.lockedTexture:SetAllPoints()
    lockButton.lockedTexture:SetTexture("Interface\\Buttons\\LockButton-Locked-Up")
    lockButton.lockedTexture:Hide() -- Initially unlocked

    lockButton.unlockedTexture = lockButton:CreateTexture(nil, "ARTWORK")
    lockButton.unlockedTexture:SetAllPoints()
    lockButton.unlockedTexture:SetTexture("Interface\\Buttons\\LockButton-Unlocked-Up")
    lockButton.unlockedTexture:Show() -- Initially unlocked

    -- Inside CreateBiSPanel() function
    isLocked = BiSJournalDB.config.isLocked

    if isLocked then
        lockButton.lockedTexture:Show()
        lockButton.unlockedTexture:Hide()
    else
        lockButton.lockedTexture:Hide()
        lockButton.unlockedTexture:Show()
    end

    lockButton:SetScript("OnClick", function()
        isLocked = not isLocked
        BiSJournalDB.config.isLocked = isLocked
        if isLocked then
            lockButton.lockedTexture:Show()
            lockButton.unlockedTexture:Hide()
            resizeButton:Hide()
        else
            lockButton.lockedTexture:Hide()
            lockButton.unlockedTexture:Show()
            resizeButton:Show()
        end
        -- Play sound for feedback
        PlaySound(isLocked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end) 

    lockButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if isLocked then
            GameTooltip:SetText("Unlock BiS Journal (Currently Locked)")
            GameTooltip:AddLine("Journal will stay in place and won't snap to other windows", 1, 1, 1)
            GameTooltip:AddLine("Resizing is disabled while locked", 1, 0.5, 0.5)
        else
            GameTooltip:SetText("Lock BiS Journal (Currently Unlocked)")
            GameTooltip:AddLine("Journal will snap to Adventure Guide and vendor windows", 1, 1, 1)
            GameTooltip:AddLine("Resizing is enabled while unlocked", 0.5, 1, 0.5)
        end
        GameTooltip:Show()
    end)

    lockButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local sortDropdown = CreateFrame("Frame", "BiSJournalSortDropdown", biSPanel, "UIDropDownMenuTemplate")
    sortDropdown:SetPoint("TOP", biSPanel, "BOTTOM", 0, 1)
    UIDropDownMenu_SetWidth(sortDropdown, 180)
    UIDropDownMenu_SetText(sortDropdown, "Sort by: " .. sortOptions[1].text)

    UIDropDownMenu_Initialize(sortDropdown, function(self, level)
        for i, option in ipairs(sortOptions) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = option.text
            info.checked = (currentSortType == option.value)
            info.func = function()
                currentSortType = option.value
                UIDropDownMenu_SetText(sortDropdown, "Sort by: " .. option.text)
                RefreshBiSPanel()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    biSPanel.CheckVisibility = function(self)
        if EncounterJournal and EncounterJournal:IsShown() then
            self:Show()
            SetDefaultPosition()
        end
    end
    
    -- Add to OnShow script
    biSPanel:SetScript("OnShow", function()
        local opacity = BiSJournalDB.config.opacity or 1.0
        local colorOption = BiSJournalDB.config.colorOption or 1
        local colorValue = ADDON.colorOptions[colorOption].value
        ADDON:UpdatePanelColor(colorValue)
        C_Timer.After(0.2, RefreshBiSPanel)
        -- Save the state if manually shown
        BiSJournalDB.config.manuallyShown = true
    end)
    
    -- Add to OnHide script
    biSPanel:SetScript("OnHide", function()
        -- Save the state if manually hidden
        BiSJournalDB.config.manuallyShown = false
    end)
    
    -- Hide initially
    biSPanel:Hide()
    RefreshBiSPanel()
end

local function UpdateLockButtonState()
    if lockButton then
        if isLocked then
            lockButton.lockedTexture:Show()
            lockButton.unlockedTexture:Hide()
            if resizeButton then
                resizeButton:Hide()
            end
        else
            lockButton.lockedTexture:Hide()
            lockButton.unlockedTexture:Show()
            if resizeButton then
                resizeButton:Show()
            end
        end
    end
end

local function OnPlayerSpecChanged()
    -- Only auto-switch to new spec if not browsing manually
    if selectedSpecID == nil then
        InitializeDB()
        RefreshBiSPanel()
        if biSPanel and BiSJournalSpecDropdown then
            SetDropdownTextToCurrent(BiSJournalSpecDropdown)
        end
    end
    UpdateLockButtonState()
end

local function AddBiSTooltipInfo(tooltip, itemID)
    if not itemID or not DB_KEY or not biSPanel then return end

    for slot, items in pairs(BiSJournalDB.lists[GetCurrentDBKey()]) do
        for _, itemData in ipairs(items) do
            local storedItemID = type(itemData) == "table" and itemData.id or itemData
            if storedItemID == itemID then
                local colorIndex = BiSJournalDB.config.tooltipColorOption or 1
                local colorOption = ADDON.tooltipColorOptions and ADDON.tooltipColorOptions[colorIndex]
                local colorHex

                if colorOption and colorOption.value == "class" then
                    -- Dynamically get the player's class color
                    local _, class = UnitClass("player")
                    local classColor = RAID_CLASS_COLORS[class]
                    if classColor then
                        colorHex = string.format("FF%02X%02X%02X", classColor.r * 255, classColor.g * 255, classColor.b * 255)
                    else
                        colorHex = "FFFFFFFF" -- fallback to white
                    end
                else
                    colorHex = colorOption and colorOption.hex or "FF00FF00"
                end

                tooltip:AddLine("|c" .. colorHex .. "This is in your BiS Journal!|r")
                return
            end
        end
    end
end

local function HookTooltips()
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        if data.id then
            AddBiSTooltipInfo(tooltip, data.id)
        end
    end)
end


local function HookChatItemLinks()
    -- Store the original SetItemRef function
    local originalSetItemRef = SetItemRef
    
    -- Replace with our custom function
    SetItemRef = function(link, text, button, chatFrame)
        -- Call the original function first to maintain normal functionality
        originalSetItemRef(link, text, button, chatFrame)
        
        -- Check if it's an item link and Alt is being held down
        local linkType, itemID = link:match("^(%a+):(%d+)")
        
        if linkType == "item" and IsAltKeyDown() then
            -- Convert to number
            itemID = tonumber(itemID)
            
            -- Request item data to ensure it's loaded
            C_Item.RequestLoadItemDataByID(itemID)
            
            -- Use a slight delay to allow item data to load
            C_Timer.After(0.2, function()
                local itemName, itemLink = C_Item.GetItemInfo(itemID)
                if itemName then
                    -- Show the popup dialog with the item name
                    StaticPopup_Show("BISJOURNAL_CHAT_SOURCE", itemName, nil, {itemID = itemID, name = itemName})
                else
                    print("|cFFFF0000BiS Journal:|r Unable to retrieve item information. Try again.")
                end
            end)
        end
    end
end

local function HookAdventureGuide()
    -- Hook into the Adventure Guide's OnShow event
    if EncounterJournal then
        -- Optionally hide when Adventure Guide is closed
        EncounterJournal:HookScript("OnHide", function()
            if biSPanel and biSPanel:IsShown() and not openedByMinimap and not openedBySlashCommmand and BiSJournalDB.config.autoHide then
                biSPanel:Hide()
            end
        end)
        EncounterJournal:HookScript("OnShow", function()
            if biSPanel then
                biSPanel:Show()
                if not isLocked then
                    biSPanel:ClearAllPoints()
                    biSPanel:SetPoint("TOPLEFT", EncounterJournal, "TOPRIGHT", 20, 0)
                end
                RefreshBiSPanel()
            end
        end)
    else
        -- If EncounterJournal isn't loaded yet, try again later
        C_Timer.After(1, HookAdventureGuide)
    end
end

-- In BiSJournal.lua (REPLACE the old function with this EXACT code)
function ADDON:UpdatePanelOpacity(value)
    if biSPanel then
        -- Retrieve the currently saved background color
        -- Use default black (0,0,0) if the saved color isn't fully defined yet
        local r = (BiSJournalDB.config.backgroundColor and BiSJournalDB.config.backgroundColor.r) or 0
        local g = (BiSJournalDB.config.backgroundColor and BiSJournalDB.config.backgroundColor.g) or 0
        local b = (BiSJournalDB.config.backgroundColor and BiSJournalDB.config.backgroundColor.b) or 0
        
        -- Apply the SAVED color (r,g,b) with the NEW opacity (value)
        biSPanel:SetBackdropColor(r, g, b, value) 
        
        -- Also update the stored opacity value in the database
        BiSJournalDB.config.opacity = value 
    end
end

-- Add this function to BiSJournal.lua
function ADDON:UpdatePanelScale(value)
    if biSPanel then
        biSPanel:SetScale(value)
        -- Save the scale value to the database
        BiSJournalDB.config.scale = value
    end
end

function GetCurrentExpansionFromUI()
    -- Check which expansion is selected in the dropdown
    local dropdown = EncounterJournal.tierDropDown
    if dropdown then
        return dropdown.selectedID
    end
    return nil
end

function OpenAdventureGuideToSource(instanceName, bossName, expansion)
    if not EncounterJournal_OpenJournal then return end
    
    -- First open the journal
    EncounterJournal_OpenJournal()
    
    -- Set the expansion tier if provided
    if expansion then
        C_Timer.After(0.1, function()
            -- Select the proper expansion in the dropdown
            EJ_SelectTier(expansion)
            
            -- Continue with the search after selecting expansion
            C_Timer.After(0.1, function()
                -- Try both Dungeons and Raids tabs
                if not SearchInTab(true, instanceName, bossName) then
                    -- If not found, try Raids tab
                    C_Timer.After(0.3, function()
                        if not SearchInTab(false, instanceName, bossName) then
                            -- If still not found, try a more flexible search
                            C_Timer.After(0.3, function()
                                if not FlexibleSearchInTabs(instanceName, bossName) then
                                    print("Could not find " .. bossName .. " in " .. instanceName)
                                end
                            end)
                        end
                    end)
                end
            end)
        end)
    else
        -- Original search logic without setting expansion
        C_Timer.After(0.1, function()
            -- Try both Dungeons and Raids tabs
            if not SearchInTab(true, instanceName, bossName) then
                -- If not found, try Raids tab
                C_Timer.After(0.3, function()
                    if not SearchInTab(false, instanceName, bossName) then
                        -- If still not found, try a more flexible search
                        C_Timer.After(0.3, function()
                            if not FlexibleSearchInTabs(instanceName, bossName) then
                                print("Could not find " .. bossName .. " in " .. instanceName)
                            end
                        end)
                    end
                end)
            end
        end)
    end
end

function ADDON:UpdatePanelColor(colorValue)
    if not biSPanel then
        print("Error: biSPanel not found")
        return
    end
    
    local r, g, b = 0, 0, 0 -- Default black
    local opacity = BiSJournalDB.config.opacity or 1.0
    
    if colorValue == "black" then
        r, g, b = 0, 0, 0
    elseif colorValue == "class" then
        -- Get class color
        local _, className = UnitClass("player")
        local classColor = RAID_CLASS_COLORS[className]
        r, g, b = classColor.r, classColor.g, classColor.b
    elseif colorValue == "red" then
        r, g, b = 0.8, 0, 0
    elseif colorValue == "green" then
        r, g, b = 0, 0.8, 0
    elseif colorValue == "blue" then
        r, g, b = 0, 0, 0.8
    elseif colorValue == "purple" then
        r, g, b = 0.7, 0, 0.7
    elseif colorValue == "gold" then
        r, g, b = 1, 0.8, 0
    end
    
    -- Store the color values
    BiSJournalDB.config.backgroundColor = {r = r, g = g, b = b}

    -- Apply the color with current opacity
    biSPanel:SetBackdropColor(r, g, b, opacity)
end

-- Export the current BiS list for this character/spec as a custom string
local function ExportCurrentBiSList()
    local currentKey = GetCurrentDBKey()
    if not currentKey then
        print("BiSJournal: No current spec key; cannot export.")
        return ""
    end

    local list = BiSJournalDB.lists and BiSJournalDB.lists[currentKey]
    if not list then
        print("BiSJournal: No BiS list found for this spec; cannot export.")
        return ""
    end

    local t = {}
    local ownerSpecID
    if currentKey and type(currentKey) == "string" then
        ownerSpecID = select(2, string.match(currentKey, "^(.-)%-(%d+)$"))
    end

    for slot, items in pairs(BiSJournalDB.lists[currentKey]) do
        for _, item in ipairs(items) do
            table.insert(t, table.concat({
                slot,
                item.id,
                item.source,
                item.instanceID or "",
                item.encounterID or "",
                item.difficultyID or "",
                item.instanceName or "",
                item.bossName or "",
                item.expansion or "",
                item.isDungeon == true and "1" or "0",
                item.sourceType or "instance",
                ownerSpecID or ""
            }, ":"))
        end
    end
    local exportString = table.concat(t, ";")
    if exportString == "" then
        print("BiSJournal: Current spec list is empty; nothing to export.")
    end
    return exportString
end

ADDON.ExportCurrentBiSList = ExportCurrentBiSList

local function ImportBiSList(importString)
    if not importString or importString == "" then
        return
    end

    local playerGUID = UnitGUID("player")
    if not playerGUID then
        return
    end

    -- Collect new data keyed by guid-specID so multiple specs can be imported at once
    local newListsByKey = {}

    for entry in string.gmatch(importString, "([^;]+)") do
        -- Allow empty fields; capture up to 12 fields
        local slot, itemID, source, instanceID, encounterID, difficultyID,
              instanceName, bossName, expansion, isDungeonStr, sourceType,
              ownerSpecID =
            entry:match("([^:]*):" ..      -- 1 slot
                        "([^:]*):" ..      -- 2 itemID
                        "([^:]*):" ..      -- 3 source
                        "([^:]*):" ..      -- 4 instanceID
                        "([^:]*):" ..      -- 5 encounterID
                        "([^:]*):" ..      -- 6 difficultyID
                        "([^:]*):" ..      -- 7 instanceName
                        "([^:]*):" ..      -- 8 bossName
                        "([^:]*):" ..      -- 9 expansion
                        "([^:]*):" ..      -- 10 isDungeonStr
                        "([^:]*):" ..      -- 11 sourceType
                        "([^:]*)")         -- 12 ownerSpecID (may be empty)

        if slot and slot ~= "" and itemID and itemID ~= "" then
            -- Unescape any encoded colons in source (if you keep that behavior)
            if source and source ~= "" then
                source = source:gsub("3A", ":")
            end

            -- Determine which spec key this entry should belong to
            local specID = tonumber(ownerSpecID or "")
            local dbKey
            if specID then
                dbKey = playerGUID .. "-" .. specID
            else
                -- Backward‑compat: fall back to current DB key if spec was not exported
                dbKey = GetCurrentDBKey()
            end

            if dbKey then
                newListsByKey[dbKey] = newListsByKey[dbKey] or {}
                newListsByKey[dbKey][slot] = newListsByKey[dbKey][slot] or {}

                local itemTable = {
                    id         = tonumber(itemID),
                    source     = source,
                    fullSource = source,
                    sourceType = (sourceType and sourceType ~= "" and sourceType) or "instance",
                }

                -- Optional numeric fields
                if expansion and expansion ~= "" then
                    itemTable.expansion = tonumber(expansion)
                end
                if isDungeonStr and isDungeonStr ~= "" then
                    itemTable.isDungeon = (isDungeonStr == "1")
                end
                if encounterID and encounterID ~= "" then
                    itemTable.encounterID = tonumber(encounterID)
                end
                if instanceID and instanceID ~= "" then
                    itemTable.instanceID = tonumber(instanceID)
                end
                if difficultyID and difficultyID ~= "" then
                    itemTable.difficultyID = tonumber(difficultyID)
                end

                -- Optional text fields
                if instanceName and instanceName ~= "" then
                    itemTable.instanceName = instanceName
                end
                if bossName and bossName ~= "" then
                    itemTable.bossName = bossName
                end

                table.insert(newListsByKey[dbKey][slot], itemTable)
            end
        end
    end

    -- Merge imported data into the saved variables
    BiSJournalDB.lists = BiSJournalDB.lists or {}

    for key, list in pairs(newListsByKey) do
        -- Overwrite per spec+slot list (change to merge if you prefer)
        BiSJournalDB.lists[key] = list
    end

    -- Refresh panel for whatever spec is currently selected
    RefreshBiSPanel()
end

ADDON.ImportBiSList = ImportBiSList

function SearchInTab(isDungeon, instanceName, bossName)
    local tabIndex = isDungeon and 3 or 4
    PanelTemplates_SetTab(EncounterJournal, tabIndex)
    EJ_ContentTab_Select(tabIndex - 1)
    
    -- Search through all instances
    for i = 1, 100 do
        local id, name = EJ_GetInstanceByIndex(i, not isDungeon)
        if not id then break end
        
        if name == instanceName then
            NavBar_Reset(EncounterJournal.navBar)
            EncounterJournal_DisplayInstance(id)
            
            -- Find the boss
            C_Timer.After(0.2, function()
                for j = 1, 20 do
                    local name, _, encounterID = EJ_GetEncounterInfoByIndex(j)
                    if not name then break end
                    
                    if name == bossName then
                        EncounterJournal_DisplayEncounter(encounterID)
                        
                        -- Switch to the Loot tab
                        C_Timer.After(0.1, function()
                            if EncounterJournal.encounter and EncounterJournal.encounter.info then
                                EncounterJournal.encounter.info.lootTab:Click()
                            end
                        end)
                        return true
                    end
                end
            end)
            return true
        end
    end
    return false
end

function FlexibleSearchInTabs(instanceName, bossName)
    -- Try both tabs with more flexible matching
    for i = 1, 2 do -- Changed to numeric loop
        local isDungeon = (i == 1) -- true first iteration, false second
        local tabIndex = isDungeon and 3 or 4
        PanelTemplates_SetTab(EncounterJournal, tabIndex)
        EJ_ContentTab_Select(tabIndex - 1)

        -- Rest of existing code remains unchanged...
        for i = 1, 100 do
            local id, name = EJ_GetInstanceByIndex(i, not isDungeon)
            if not id then break end
            -- ... existing logic ...
        end
    end
    return false
end

-- Event handling
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("MERCHANT_SHOW")
eventFrame:RegisterEvent("MERCHANT_CLOSED")


eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" and ... == ADDON_NAME then
        BiSJournalDB = BiSJournalDB or {
            lists = {},
            config = {
                version = 1.0,
                minimapPos = nil,
                width = 325,
                height = 500,
            },
        }

        BiSJournalDB.config = BiSJournalDB.config or {}
        BiSJournalDB.config.manuallyOpened = BiSJournalDB.config.manuallyOpened or false
        BiSJournalDB.config.opacity = BiSJournalDB.config.opacity or 1.0
        BiSJournalDB.config.colorOption = BiSJournalDB.config.colorOption or 1
        BiSJournalDB.config.backgroundColor = BiSJournalDB.config.backgroundColor or {r = 0, g = 0, b = 0}
        BiSJournalDB.config.scale = BiSJournalDB.config.scale or 1.0

        openedByMinimap = BiSJournalDB.config.manuallyOpened
        openedBySlashCommmand = false

        if BiSJournalMinimapButton then
            if BiSJournalDB.config and BiSJournalDB.config.showMinimapButton == false then
                BiSJournalMinimapButton:Hide()
            else
                BiSJournalMinimapButton:Show()
            end
        end

        if BiSJournalDB.config.isLocked ~= nil then
            isLocked = BiSJournalDB.config.isLocked
        end

        if BiSJournalDB.config.version <1.1 then
            MigrateDatabase()
        end

        local REQUIRED_MIN_WIDTH = 325
        local REQUIRED_MIN_HEIGHT = 500 -- Or whatever your new minimum height is
        local NEW_VERSION = 1.3

        if not BiSJournalDB.config.version or BiSJournalDB.config.version < NEW_VERSION then
            if BiSJournalDB.config.width and BiSJournalDB.config.width < REQUIRED_MIN_WIDTH then
                BiSJournalDB.config.width = REQUIRED_MIN_WIDTH
            end
            if BiSJournalDB.config.height and BiSJournalDB.config.height < REQUIRED_MIN_HEIGHT then
                BiSJournalDB.config.height = REQUIRED_MIN_HEIGHT
            end
            -- If width/height were never set (maybe a new user), also default:
            BiSJournalDB.config.width = BiSJournalDB.config.width or REQUIRED_MIN_WIDTH
            BiSJournalDB.config.height = BiSJournalDB.config.height or REQUIRED_MIN_HEIGHT

            BiSJournalDB.config.version = NEW_VERSION
        end

        HookAdventureGuide()
        BiSJournalDB.config.autoHide = BiSJournalDB.config.autoHide or true
        ADDON:InitializeOptions()

    elseif event == "PLAYER_LOGIN" then
        InitializeDB()
        CreateBiSPanel()
        HookJournalButtons()
        HookMerchantButtons()
        HookChatItemLinks()
        UpdateLockButtonState()

        if BiSJournalDB.config.colorOption then
            local selectedIndex = BiSJournalDB.config.colorOption
            local selectedColorValue = ADDON.colorOptions[selectedIndex].value
            ADDON:UpdatePanelColor(selectedColorValue)
        end
        

        if BiSJournalDB.config.panelPosition then
            biSPanel:ClearAllPoints()
            biSPanel:SetPoint(
                BiSJournalDB.config.panelPosition.point,
                UIParent,
                BiSJournalDB.config.panelPosition.relativePoint,
                BiSJournalDB.config.panelPosition.xOfs,
                BiSJournalDB.config.panelPosition.yOfs
            )
        end

        if BiSJournalDB.config.scale then
            biSPanel:SetScale(BiSJournalDB.config.scale)
        end

        HookTooltips()

        C_Timer.After(1, function()
            RefreshBiSPanel()
            -- Check if Adventure Guide is already open
            if EncounterJournal and EncounterJournal:IsShown() and biSPanel then
                biSPanel:Show()
                biSPanel:ClearAllPoints()
                biSPanel:SetPoint("TOPLEFT", EncounterJournal, "TOPRIGHT", 20, 0)
            end
        end)

    elseif event == "MERCHANT_SHOW" then
        HookMerchantButtons()
        C_Timer.After(0.1, function()
            if biSPanel then
                biSPanel:Show()
                if not isLocked then
                    biSPanel:ClearAllPoints()
                    biSPanel:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", 20.0)
                end
            end
            RefreshBiSPanel()
        end)

    elseif event == "MERCHANT_CLOSED" then
        if biSPanel and biSPanel:IsShown() and not openedByMinimap and not openedBySlashCommmand and BiSJournalDB.config.autoHide then
            biSPanel:Hide()
        end

    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- Only auto-switch panel if not using manual selection
        if selectedSpecID == nil then
            InitializeDB()
            RefreshBiSPanel()
            if biSPanel and specDropdown then
                SetDropdownTextToCurrent(specDropdown)
            end
        end
        UpdateLockButtonState()
    end
end)

-- Slash command
SLASH_BISJOURNAL1, SLASH_BISJOURNAL2 = "/bj", "/bisjournal"
SlashCmdList["BISJOURNAL"] = function(msg)
    if msg == "config" or msg == "options" then
        Settings.OpenToCategory("BiS Journal")
    else
        biSPanel:Show()
        openedBySlashCommmand = true
        openedByMinimap = false
        RefreshBiSPanel()
    end
end
