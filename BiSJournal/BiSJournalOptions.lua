local ADDON_NAME, ADDON = ...

-- Add these FIRST before anything else
StaticPopupDialogs["BISJOURNAL_EXPORT"] = {
    text = "Copy the string below (Ctrl+C):",
    button1 = OKAY,
    hasEditBox = true,
    editBoxWidth = 350,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnShow = function(self, data)
        local box = _G[self:GetName() .. "EditBox"]
        if not box then return end

        box:SetText(data or "")
        box:HighlightText()
        box:SetFocus()
    end,
}

StaticPopupDialogs["BISJOURNAL_IMPORT"] = {
    text = "Paste your import string below:",
    button1 = "Import",
    button2 = CANCEL,
    hasEditBox = true,
    editBoxWidth = 350,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnShow = function(self)
        local box = self.editBox or self.EditBox or _G[self:GetName() .. "EditBox"]
        if not box then return end

        box:SetText("")
        box:SetFocus()
    end,

    OnAccept = function(self)
        local box = self.editBox or self.EditBox or _G[self:GetName() .. "EditBox"]
        if not box then return end

        ADDON.ImportBiSList(box:GetText())
    end,
}

ADDON.colorOptions = {
    { text = "Black", value = "black" },
    { text = "Class Color", value = "class" },
    -- Add more color options
    { text = "Red", value = "red" },
    { text = "Green", value = "green" },
    { text = "Blue", value = "blue" },
    { text = "Purple", value = "purple" },
    { text = "Gold", value = "gold" }
}

ADDON.tooltipColorOptions = {
    { text = "Green", value = "green", hex = "FF00FF00" },
    { text = "Class Color", value = "class" },
    { text = "Gold", value = "gold", hex = "FFFFD700" },
    { text = "Red", value = "red", hex = "FFFF3030" },
    { text = "Blue", value = "blue", hex = "FF3399FF" },
    { text = "Purple", value = "purple", hex = "FFAA00FF" },
    { text = "White", value = "white", hex = "FFFFFFFF" },
}

local function CreateOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "BiS Journal"

    local scrollFrame = CreateFrame("ScrollFrame", "BiSJournalOptionsScrollFrame", panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 3, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", -27, 16)

    -- Create the scroll child frame that will contain all your options
    local scrollChild = CreateFrame("Frame", "BiSJournalOptionsScrollChild")
    scrollChild:SetWidth(scrollFrame:GetWidth() - 20)
    scrollChild:SetHeight(800)-- Set this to a height that accommodates all your options

    scrollFrame:SetScrollChild(scrollChild)
    
    local title = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 26, -16)
    title:SetText("BiS Journal Options")

    -- Show Minimap Button checkbox
    local showMinimapCheckbox = CreateFrame("CheckButton", nil, scrollChild, "InterfaceOptionsCheckButtonTemplate")
    showMinimapCheckbox:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 10, -10)
    showMinimapCheckbox.Text:SetText("Show Minimap Button")
    showMinimapCheckbox:SetChecked(BiSJournalDB.config.showMinimapButton ~= false) -- Default ON
    showMinimapCheckbox:SetScript("OnClick", function(self)
        BiSJournalDB.config.showMinimapButton = self:GetChecked()
        if minimapButton then
            if self:GetChecked() then
                minimapButton:Show()
                minimapButton:SetAlpha(1)
            else
                minimapButton:Hide()
                minimapButton:SetAlpha(0)
            end
        end
    end)
    
    local autoHideCheckbox = CreateFrame("CheckButton", nil, scrollChild, "InterfaceOptionsCheckButtonTemplate")
    autoHideCheckbox:SetPoint("TOPLEFT", showMinimapCheckbox, "BOTTOMLEFT", 0, -10)
    autoHideCheckbox.Text:SetText("Auto-hide when Adventure Guide or Vendor is closed")
    autoHideCheckbox:SetChecked(BiSJournalDB.config.autoHide)
    autoHideCheckbox:SetScript("OnClick", function(self)
        BiSJournalDB.config.autoHide = self:GetChecked()
    end)

    local category = Settings.RegisterCanvasLayoutCategory(panel, "BiS Journal")
    Settings.RegisterAddOnCategory(category)

    local opacitySlider = CreateFrame("Slider", "BiSJournalOpacitySlider", scrollChild, "OptionsSliderTemplate")
    opacitySlider:SetPoint("TOPLEFT", autoHideCheckbox, "BOTTOMLEFT", 10, -30)
    opacitySlider:SetMinMaxValues(0, 100)
    opacitySlider:SetValueStep(10)
    opacitySlider:SetValue((BiSJournalDB.config.opacity or 1.0) * 100)
    opacitySlider.High:SetText("100%")
    opacitySlider.Low:SetText("0%")
    opacitySlider.Text:SetText("Background Opacity")
    
    opacitySlider:SetScript("OnValueChanged", function(self, value)
        local opacity = value / 100
        BiSJournalDB.config.opacity = opacity
        ADDON:UpdatePanelOpacity(opacity)
    end)

    -- Add this after your opacity slider in BiSJournalOptions.lua
    local scaleSlider = CreateFrame("Slider", "BiSJournalScaleSlider", scrollChild, "OptionsSliderTemplate")
    scaleSlider:SetPoint("TOPLEFT", opacitySlider, "TOPRIGHT", 50, 0)
    scaleSlider:SetMinMaxValues(50, 200)
    scaleSlider:SetValueStep(10)
    scaleSlider:SetValue((BiSJournalDB.config.scale or 1.0) * 100)
    scaleSlider:SetWidth(150)
    scaleSlider.High:SetText("200%")
    scaleSlider.Low:SetText("50%")
    scaleSlider.Text:SetText("Panel Scale")

    scaleSlider:SetScript("OnValueChanged", function(self, value)
        local scale = value / 100
        BiSJournalDB.config.scale = scale
        ADDON:UpdatePanelScale(scale)
    end)

        -- Add after your opacity slider
    local colorDropdown = CreateFrame("Frame", "BiSJournalColorDropdown", scrollChild, "UIDropDownMenuTemplate")
    colorDropdown:SetPoint("TOPLEFT", opacitySlider, "BOTTOMLEFT", -5, -40)
    colorDropdown.colorOptions = ADDON.colorOptions
    local colorDropdownText = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    colorDropdownText:SetPoint("BOTTOMLEFT", colorDropdown, "TOPLEFT", 20, 5)
    colorDropdownText:SetText("Background Color:")

    UIDropDownMenu_SetWidth(colorDropdown, 120)
    UIDropDownMenu_SetText(colorDropdown, ADDON.colorOptions[BiSJournalDB.config.colorOption or 1].text)

    UIDropDownMenu_Initialize(colorDropdown, function(self, level)
        for i, option in ipairs(colorDropdown.colorOptions) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = option.text
            info.value = option.value
            info.func = function()
                BiSJournalDB.config.colorOption = i
                UIDropDownMenu_SetText(colorDropdown, option.text)

                local selectedColorValue = ADDON.colorOptions[i].value
                ADDON:UpdatePanelColor(selectedColorValue)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    -- Tooltip Color Dropdown
    local tooltipColorDropdown = CreateFrame("Frame", "BiSJournalTooltipColorDropdown", scrollChild, "UIDropDownMenuTemplate")
    tooltipColorDropdown:SetPoint("TOPLEFT", colorDropdown, "TOPRIGHT", 50, 0)
    tooltipColorDropdown.colorOptions = ADDON.tooltipColorOptions

    local tooltipColorDropdownText = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    tooltipColorDropdownText:SetPoint("BOTTOMLEFT", tooltipColorDropdown, "TOPLEFT", 20, 5)
    tooltipColorDropdownText:SetText("Tooltip Color:")

    UIDropDownMenu_SetWidth(tooltipColorDropdown, 120)
    UIDropDownMenu_SetText(tooltipColorDropdown, ADDON.tooltipColorOptions[BiSJournalDB.config.tooltipColorOption or 1].text)

    UIDropDownMenu_Initialize(tooltipColorDropdown, function(self, level)
        for i, option in ipairs(tooltipColorDropdown.colorOptions) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = option.text
            info.value = option.value
            info.func = function()
                BiSJournalDB.config.tooltipColorOption = i
                UIDropDownMenu_SetText(tooltipColorDropdown, option.text)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    -- Export Label
    local exportLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    exportLabel:SetPoint("TOPLEFT", colorDropdown, "BOTTOMLEFT", 10, -30)
    exportLabel:SetText("Export String:")

    -- Export Button
    local exportButton = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
    exportButton:SetText("Export BiS List")
    exportButton:SetSize(120, 22)
    exportButton:SetPoint("TOPLEFT", exportLabel, "BOTTOMLEFT", 0, -5)
    exportButton:SetScript("OnClick", function()
        local exportString = ADDON.ExportCurrentBiSList()
        StaticPopup_Show("BISJOURNAL_EXPORT", nil, nil, exportString)
    end)

    -- Import Label
    local importLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    importLabel:SetPoint("TOPLEFT", exportLabel, "TOPRIGHT", 150, 0)
    importLabel:SetText("Import String:")

    -- Import Button
    local importButton = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
    importButton:SetText("Import BiS List")
    importButton:SetSize(120, 22)
    importButton:SetPoint("TOPLEFT", importLabel, "BOTTOMLEFT", 0, -5)
    importButton:SetScript("OnClick", function()
        StaticPopup_Show("BISJOURNAL_IMPORT")
    end)

    -- Add a divider before the Manual Item Addition section
    local divider = scrollChild:CreateTexture(nil, "ARTWORK")
    divider:SetAtlas("Options_HorizontalDivider", true)
    divider:SetPoint("TOPLEFT", exportButton, "BOTTOMLEFT", -15, -20)
    divider:SetWidth(scrollFrame:GetWidth() - 40)

    -- Manual Item Addition Section Header
    local manualAddHeader = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    manualAddHeader:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 40, -15)
    manualAddHeader:SetText("Add Items Manually")

    -- Instructions
    local manualAddInstructions = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    manualAddInstructions:SetPoint("TOPLEFT", manualAddHeader, "BOTTOMLEFT", 10, -10)
    manualAddInstructions:SetText("Enter an item ID to add items not found in the Adventure Guide or from vendors.")

    -- Item ID Label
    local itemIDLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    itemIDLabel:SetPoint("TOPLEFT", manualAddInstructions, "BOTTOMLEFT", 10, -15)
    itemIDLabel:SetText("Item ID:")

    -- Item ID Input Box
    local itemIDBox = CreateFrame("EditBox", "BiSJournalItemIDInput", scrollChild, "InputBoxTemplate")
    itemIDBox:SetSize(150, 24)
    itemIDBox:SetPoint("TOPLEFT", itemIDLabel, "BOTTOMLEFT", 0, -5)
    itemIDBox:SetAutoFocus(false)
    itemIDBox:SetNumeric(true)
    itemIDBox:SetMaxLetters(10)

    -- Add placeholder text functionality
    itemIDBox.placeholderText = "Enter an item ID"
    itemIDBox:SetText(itemIDBox.placeholderText)
    itemIDBox:SetTextColor(0.5, 0.5, 0.5) -- Gray color for placeholder
    itemIDBox:SetScript("OnEditFocusGained", function(self)
        if self:GetText() == self.placeholderText then
            self:SetText("")
            self:SetTextColor(1, 1, 1) -- White color for actual input
        end
    end)
    itemIDBox:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then
            self:SetText(self.placeholderText)
            self:SetTextColor(0.5, 0.5, 0.5) -- Gray color for placeholder
        end
    end)

    -- Preview Frame
    local previewFrame = CreateFrame("Frame", nil, scrollChild)
    previewFrame:SetSize(40, 40)
    previewFrame:SetPoint("LEFT", itemIDBox, "RIGHT", 25, 0)

    local previewIcon = previewFrame:CreateTexture(nil, "ARTWORK")
    previewIcon:SetAllPoints()
    previewIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

    local previewName = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    previewName:SetPoint("LEFT", previewFrame, "RIGHT", 10, 0)

    -- Source Label
    local sourceLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    sourceLabel:SetPoint("TOPLEFT", itemIDBox, "BOTTOMLEFT", 0, -15)
    sourceLabel:SetText("Source (e.g., \"World Quest - Expansion Name\" Source - Location):")

    -- Source Input Box
    local sourceBox = CreateFrame("EditBox", "BiSJournalSourceInput", scrollChild, "InputBoxTemplate")
    sourceBox:SetSize(300, 24)
    sourceBox:SetPoint("TOPLEFT", sourceLabel, "BOTTOMLEFT", 0, -5)
    sourceBox:SetAutoFocus(false)
    sourceBox:SetMaxLetters(100)

    -- Quick Templates text
    local sourceTemplateDropdownText = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    sourceTemplateDropdownText:SetPoint("TOPLEFT", sourceBox, "BOTTOMLEFT", 0, -15)
    sourceTemplateDropdownText:SetText("Quick Templates:")

    -- Source Template Dropdown
    local sourceTemplateDropdown = CreateFrame("Frame", "BiSJournalSourceTemplateDropdown", scrollChild, "UIDropDownMenuTemplate")
    sourceTemplateDropdown:SetPoint("TOPLEFT", sourceTemplateDropdownText, "BOTTOMLEFT", -5, -5)

    -- Add Button
    local addButton = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
    addButton:SetSize(100, 22)
    addButton:SetPoint("TOPLEFT", sourceTemplateDropdown, "BOTTOMLEFT", 15, -15)
    addButton:SetText("Add Item")

    -- Configure the dropdown
    UIDropDownMenu_SetWidth(sourceTemplateDropdown, 150)
    UIDropDownMenu_SetText(sourceTemplateDropdown, "Select Source")

    local sourceTemplates = {
        { text = "World Quest", value = "World Quest - (Type Expansion Here)" },
        { text = "Delve", value = "Delve - The War Within" },
        { text = "PvP Reward", value = "PvP Reward - (Type Expansion Here)" },
        { text = "Crafted", value = "Crafted Item - (Type Expansion Here)" },
        { text = "Trading Post", value = "Trading Post" },
        { text = "World Drop", value = "World Drop - (Type Zone Here)" }
    }

    UIDropDownMenu_Initialize(sourceTemplateDropdown, function(self, level)
        for i, template in ipairs(sourceTemplates) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = template.text
            info.value = template.value
            info.func = function()
                sourceBox:SetText(template.value)
                UIDropDownMenu_SetText(sourceTemplateDropdown, template.text)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    -- Update preview when item ID changes
    itemIDBox:SetScript("OnTextChanged", function(self)
        local itemID = tonumber(self:GetText())
        if not itemID or itemID == 0 then
            previewIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            previewName:SetText("Enter an item ID")
            return
        end
        
        RequestLoadItemDataByIDFunc(itemID)
        C_Timer.After(0.2, function()
            local itemName, itemLink, itemRarity, _, _, _, _, _, _, itemTexture = C_Item.GetItemInfoFunc(itemID)
            if itemName then
                previewIcon:SetTexture(itemTexture)
                previewName:SetText(itemLink or itemName)
            else
                previewIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                previewName:SetText("Item not found")
            end
        end)
    end)

    -- Add Button functionality
    addButton:SetScript("OnClick", function()
        local itemID = tonumber(itemIDBox:GetText())
        local source = sourceBox:GetText()
        
        if not itemID or itemID == 0 then
            print("|cFFFF0000BiS Journal:|r Please enter a valid item ID.")
            return
        end
        
        if not source or source == "" then
            source = "Manual Addition"
        end
        
        -- Request item data to ensure it exists
        C_Item.RequestLoadItemDataByID(itemID)
        
        -- Use a slight delay to allow item data to load
        C_Timer.After(0.5, function()
            local itemName = C_Item.GetItemInfo(itemID)
            if not itemName then
                print("|cFFFF0000BiS Journal:|r Invalid item ID or item data not available.")
                return
            end
            
            -- Call your AddToBiSList function
            AddToBiSList(itemID, source)
            
            -- Clear the input boxes
            itemIDBox:SetText("")
            sourceBox:SetText("")
        end)
    end)

    -- Update preview when item ID changes
    itemIDBox:SetScript("OnTextChanged", function(self)
        local itemID = tonumber(self:GetText())
        if not itemID or itemID == 0 then
            previewIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            previewName:SetText("Enter an item ID")
            return
        end
        
        C_Item.RequestLoadItemDataByID(itemID)
        C_Timer.After(0.2, function()
            local itemName, itemLink, itemRarity, _, _, _, _, _, _, itemTexture = C_Item.GetItemInfo(itemID)
            if itemName then
                previewIcon:SetTexture(itemTexture)
                previewName:SetText(itemLink or itemName)
            else
                previewIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                previewName:SetText("Item not found")
            end
        end)
    end)


end
    

function ADDON:InitializeOptions()
    CreateOptionsPanel()
end
