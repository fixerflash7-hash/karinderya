-- Karinderya Toolkit | Full Orion Library Version
-- Complete features ported safely into Orion UI

local OrionLib = loadstring(game:HttpGet("https://raw.githubusercontent.com/shlexware/Orion/main/source"))()

-- SERVICES
local ProximityPromptService = game:GetService("ProximityPromptService")
local Players                = game:GetService("Players")
local ReplicatedStorage      = game:GetService("ReplicatedStorage")
local Workspace              = game:GetService("Workspace")
local UserInputService       = game:GetService("UserInputService")
local RunService             = game:GetService("RunService")
local VirtualUser            = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer

-- REMOTES
local Remotes        = ReplicatedStorage:WaitForChild("Remotes")
local ShopRemotes    = Remotes:WaitForChild("ShopRemotes")
local CounterRemotes = Remotes:WaitForChild("CounterRemotes")
local NPCRemotes     = Remotes:WaitForChild("NPCRemotes")
local MenuRemotes    = Remotes:WaitForChild("MenuRemotes")

local GetShopInfo    = ShopRemotes:WaitForChild("GetShopInfo")
local BuyFurniture   = ShopRemotes:WaitForChild("BuyFurniture")
local ShopRestocked  = ShopRemotes:WaitForChild("ShopRestocked")
local BuyIngredient  = ShopRemotes:WaitForChild("BuyIngredient")
local GiveSoftdrink  = ShopRemotes:WaitForChild("GiveSoftdrink")

local GetCounterInfo = CounterRemotes:WaitForChild("GetCounterInfo")
local AssignNPC      = CounterRemotes:WaitForChild("AssignNPC")
local RejectNPC      = CounterRemotes:WaitForChild("RejectNPC")

local RedeemCode              = Remotes:WaitForChild("RedeemCode"):WaitForChild("RedeemCode")
local UpgradeToGoldenPan      = Remotes:WaitForChild("UpgradeToGoldenPan")

local SoftdrinkOrdersUpdated  = NPCRemotes:WaitForChild("SoftdrinkOrdersUpdated")
local AdditionalOrder         = NPCRemotes:WaitForChild("AdditionalOrder")
local NPCDrink                = NPCRemotes:WaitForChild("NPCDrink")

local UnlockMenu  = MenuRemotes:WaitForChild("UnlockMenu")
local ToggleMenu  = MenuRemotes:WaitForChild("ToggleMenu")
local GetMenuData = MenuRemotes:WaitForChild("GetMenuData")

local PropEquipEvent = nil
pcall(function()
    local r = ReplicatedStorage:WaitForChild("Remotes", 5)
    if r then PropEquipEvent = r:FindFirstChild("PropEquipEvent") end
end)

-- MODULE CONFIGS
local Modules           = ReplicatedStorage:WaitForChild("Modules")
local TableConfig       = require(Modules:WaitForChild("TableConfig"))
local ChairConfig       = require(Modules:WaitForChild("ChairConfig"))
local MaterialConfig    = require(Modules:WaitForChild("MaterialConfig"))
local PaintConfig       = require(Modules:WaitForChild("PaintConfig"))
local TileConfig        = require(Modules:WaitForChild("TileConfig"))
local StoveConfig       = require(Modules:WaitForChild("StoveConfig"))
local IngredientsConfig = require(Modules:WaitForChild("IngredientsConfig"))
local FurnitureConfig   = require(Modules:WaitForChild("FurnitureConfig"))
local NPCConfig         = require(Modules:WaitForChild("NPCConfig"))

-- STATE CONFIG
local Config = {
    autoServe          = false,
    autoOrder          = false,
    autoRejectNPC      = false,
    rejectNPCList      = {},
    autoClaimCodes     = false,
    antiMod            = false,
    autoPan            = false,
    autoWash           = false,
    autoSoftdrinks     = false,
    autoBuyIngredients = false,
    autoTP             = false,
    noclip             = false,
    walkSpeed          = 16,
    infJump            = false,
    autoUnlockMenu     = false,
    serveDelay         = 0.01,
    orderDelay         = 0.01,
    washDelay          = 0.3,
}

local pendingSoftdrinkOrders = {}
local softdrinkCooldowns     = {}
local softdrinkStats         = { given = 0, state = "Watching for requests" }
local eventConnections       = {}
local autoBuyThreshold       = 5

-- NPC RARITIES
local npcRarityList = {}
local npcRaritySeen = {}
for _, v in pairs(NPCConfig.Types) do
    if type(v) == "table" then
        local rarity = v.Rarity or "Unknown"
        if not npcRaritySeen[rarity] then
            npcRaritySeen[rarity] = true
            table.insert(npcRarityList, rarity)
        end
    end
end
table.sort(npcRarityList)

-- HELPER FUNCTIONS
local function getPlot()
    for _, child in ipairs(Workspace:GetChildren()) do
        if string.find(child.Name, "^Karenderya") and child:GetAttribute("Owner") == LocalPlayer.UserId then
            return child
        end
    end
end

local function getCash()
    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    if leaderstats then
        local Cash = leaderstats:FindFirstChild("Cash")
        if Cash then return Cash.Value end
    end
    return 0
end

local function getCharacter()
    return LocalPlayer.Character, LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
end

local function getHRP()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function teleportTo(cf)
    local hrp = getHRP()
    if hrp then hrp.CFrame = cf end
end

local function resolveSoftdrinkKey(raw)
    if not raw then return "Kola" end
    local normalized = tostring(raw):lower():gsub("%s+", "")
    for k in pairs(IngredientsConfig or {}) do
        if normalized == tostring(k):lower():gsub("%s+", "") then return k end
    end
    if normalized == "cola" or normalized == "kola" then
        return (not IngredientsConfig.Kola) and tostring(raw) or "Kola"
    end
    if normalized == "suprise" or normalized == "surprise" then
        return (not IngredientsConfig.Suprise) and tostring(raw) or "Suprise"
    end
    if normalized == "loyal" then return "Loyal" end
    return tostring(raw)
end

-- MUTEX
local mutexLocked = false
local function acquireMutex()
    while mutexLocked do task.wait(0.05) end
    mutexLocked = true
    return function() mutexLocked = false end
end

-- SOFTDRINK LISTENERS
for _, conn in ipairs(eventConnections) do pcall(function() conn:Disconnect() end) end
eventConnections = {}

table.insert(eventConnections, SoftdrinkOrdersUpdated.OnClientEvent:Connect(function(orders)
    if type(orders) == "table" then
        pendingSoftdrinkOrders = {}
        for _, v in pairs(orders) do table.insert(pendingSoftdrinkOrders, resolveSoftdrinkKey(v)) end
    end
end))

table.insert(eventConnections, AdditionalOrder.OnClientEvent:Connect(function(_, flavor)
    if flavor ~= nil then table.insert(pendingSoftdrinkOrders, resolveSoftdrinkKey(flavor)) end
end))

table.insert(eventConnections, NPCDrink.OnClientEvent:Connect(function(_, flavor)
    softdrinkStats.given += 1
    softdrinkStats.state = string.format("Delivered %s!", resolveSoftdrinkKey(flavor))
end))

-- INGREDIENT & DRINK FUNCTIONS
local function buyOneIngredient(ingredKey)
    local data = IngredientsConfig[ingredKey]
    if not data or not data.Cost then return false end
    if getCash() - data.Cost < 5000 then return false end
    local ok, res = pcall(function() return BuyIngredient:InvokeServer(ingredKey, 1, "Cash") end)
    return ok and res
end

local function deliverNextSoftdrink()
    if not Config.autoSoftdrinks or #pendingSoftdrinkOrders == 0 then return false end
    local flavor = pendingSoftdrinkOrders[1]
    local key    = resolveSoftdrinkKey(flavor)
    local now    = os.clock()

    if now < (softdrinkCooldowns[key] or 0) then return false end
    softdrinkCooldowns[key] = now + 1.5

    local Ingredients = LocalPlayer:FindFirstChild("Ingredients")
    local slot        = Ingredients and Ingredients:FindFirstChild(key)

    if not slot or slot.Value <= 0 then
        buyOneIngredient(key)
        task.wait(0.2)
        Ingredients = LocalPlayer:FindFirstChild("Ingredients")
        slot        = Ingredients and Ingredients:FindFirstChild(key)
        if not slot or slot.Value <= 0 then
            softdrinkCooldowns[key] = now + 5
            return false
        end
    end

    local ok, res, err = pcall(function() return GiveSoftdrink:InvokeServer(key) end)
    if ok and res then
        table.remove(pendingSoftdrinkOrders, 1)
        softdrinkStats.given += 1
        return true
    end
    if tostring(err):match("Nobody") or tostring(err):match("ordered") then
        table.remove(pendingSoftdrinkOrders, 1)
    end
    return false
end

-- TRASH SYSTEM
local trashNames = { BoyBawang = true, Dirt = true, Leaves = true, Pizza = true, Plastic = true, Tsinelas = true }
local trashInstantPickup = true
local lastCleanedTrash   = nil

local function isTrashPrompt(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") then return false end
    if prompt:GetAttribute("IsTrash") == true then return true end
    local parent = prompt.Parent
    return parent and parent:GetAttribute("IsTrash") == true
end

local function getPartFromInstance(inst)
    if not inst then return nil end
    if inst:IsA("BasePart") then return inst end
    if inst:IsA("Model") then return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true) end
    return inst:FindFirstChildWhichIsA("BasePart", true)
end

local function patchTrashPrompt(prompt)
    pcall(function()
        if isTrashPrompt(prompt) and trashInstantPickup then prompt.HoldDuration = 0 end
    end)
end

local function equipBroom(equip)
    if not PropEquipEvent then return end
    pcall(function() PropEquipEvent:FireServer("Broom", equip) end)
end

local function interactWithPrompt(prompt)
    if not prompt or not prompt.Parent then return false end
    patchTrashPrompt(prompt)
    equipBroom(true)

    while prompt and prompt.Parent do
        if typeof(fireproximityprompt) == "function" then
            pcall(function() fireproximityprompt(prompt) end)
            task.wait(0.02)
        else
            pcall(function() prompt:InputHoldBegin() end)
            local holdDur = prompt.HoldDuration
            local t0      = os.clock()
            while holdDur > os.clock() - t0 do
                task.wait(0.02)
                if not prompt or not prompt.Parent then break end
            end
            pcall(function() prompt:InputHoldEnd() end)
        end
        task.wait(0.02)
    end
    equipBroom(false)
    return true
end

local function findNearestTrash()
    local hrp = getHRP()
    if not hrp then return nil end
    local nearest, nearestDist = nil, math.huge
    for _, desc in ipairs(Workspace:GetDescendants()) do
        if trashNames[desc.Name] then
            local part = getPartFromInstance(desc)
            if part then
                local dist = (hrp.Position - part.Position).Magnitude
                if dist < nearestDist then
                    nearest = desc
                    nearestDist = dist
                end
            end
        end
    end
    return nearest
end

local function cleanTrashObject(obj)
    local part = getPartFromInstance(obj)
    if not part then return false end
    local targetPos = part.Position + Vector3.new(0, 3, 0)
    local prompt    = nil

    while obj and obj.Parent do
        teleportTo(CFrame.new(targetPos))
        local t0 = os.clock()
        while os.clock() - t0 < 0.15 do
            prompt = obj:FindFirstChildWhichIsA("ProximityPrompt", true)
            if prompt then break end
            task.wait(0.02)
        end
        if prompt then break end
        task.wait(0.01)
    end
    if prompt then interactWithPrompt(prompt) end
    lastCleanedTrash = obj
    return true
end

task.spawn(function()
    while true do
        if Config.autoTP then
            local trash = findNearestTrash()
            if trash and trash ~= lastCleanedTrash then
                pcall(function() cleanTrashObject(trash) end)
                task.wait(0.1)
            elseif not trash then
                lastCleanedTrash = nil
            end
        end
        task.wait(0.1)
    end
end)

pcall(function()
    ProximityPromptService.PromptShown:Connect(patchTrashPrompt)
    for _, v in ipairs(ProximityPromptService:GetRegisteredPrompts()) do patchTrashPrompt(v) end
end)

-- NOCLIP
local noclipConnection = nil
local function setNoclip(enabled)
    if noclipConnection then noclipConnection:Disconnect(); noclipConnection = nil end
    if not enabled then return end
    noclipConnection = RunService.Heartbeat:Connect(function()
        local char = LocalPlayer.Character
        if not char then return end
        for _, part in ipairs(char:GetChildren()) do
            if part:IsA("BasePart") then part.CanCollide = false end
        end
    end)
end

-- ANTI-MOD
local GROUP_ID   = 985559810
local staffRanks = { Dev = true, Admin = true }
local function isStaff(player)
    if not player or player == LocalPlayer then return false end
    local ok, role = pcall(function() return player:GetRoleInGroup(GROUP_ID) end)
    return ok and staffRanks[role] == true
end

Players.PlayerAdded:Connect(function(player)
    if Config.antiMod and isStaff(player) then LocalPlayer:Kick("Staff detected") end
end)

-- TRACKED NPCS & AUTO PAN
local seenNPCs = {}
local function trackNPC(npcName) if npcName and npcName ~= "" then seenNPCs[npcName] = true end end
local function isTrackedNPC(npc) return seenNPCs[npc.Name] == true end

task.spawn(function()
    while true do
        local plot = getPlot()
        if plot and plot:FindFirstChild("DiningPlot1") then
            for _, child in ipairs(plot.DiningPlot1:GetChildren()) do
                if child:IsA("Model") then
                    local o1 = child:GetAttribute("OccupiedBy1")
                    local o2 = child:GetAttribute("OccupiedBy2")
                    if o1 then trackNPC(o1) end
                    if o2 then trackNPC(o2) end
                end
            end
        end
        task.wait(1)
    end
end)

local panToolNames = { pan = true, goldenpan = true, vippan = true }
local panReturning, panChasing = false, false
local function findPanTool()
    for _, container in ipairs({ LocalPlayer:FindFirstChild("Backpack"), LocalPlayer.Character }) do
        if container then
            for _, tool in ipairs(container:GetChildren()) do
                if tool:IsA("Tool") and panToolNames[string.lower(tool.Name)] then return tool end
            end
        end
    end
end

task.spawn(function()
    while task.wait(0.5) do
        if not Config.autoPan then
            panReturning, panChasing = false, false
        else
            local char, humanoid = getCharacter()
            if char and humanoid then
                local ClientNPCs    = Workspace:FindFirstChild("ClientNPCs")
                local runawayTarget = nil

                if ClientNPCs then
                    for _, child in ipairs(ClientNPCs:GetChildren()) do
                        if child:IsA("Model") and child:GetAttribute("IsRunaway") == true and isTrackedNPC(child) then
                            runawayTarget = child; break
                        end
                    end
                end

                if not runawayTarget then
                    if panChasing and not panReturning then
                        panReturning = true; panChasing = false
                        local tool = findPanTool()
                        if tool and tool.Parent == char then humanoid:UnequipTools() end
                        task.wait(0.15)
                        local plot = getPlot()
                        local counter = plot and plot:FindFirstChild("Counter")
                        if counter then
                            local cp = counter:IsA("BasePart") and counter or counter:FindFirstChildWhichIsA("BasePart", true)
                            if cp then
                                local rel = acquireMutex()
                                teleportTo(cp.CFrame * CFrame.new(0, 3, 0))
                                rel()
                            end
                        end
                    end
                else
                    local npcRoot = runawayTarget:FindFirstChild("HumanoidRootPart") or runawayTarget.PrimaryPart
                    panChasing = true; panReturning = false
                    if npcRoot then
                        local tool = findPanTool()
                        if tool then
                            if char ~= tool.Parent then humanoid:EquipTool(tool); task.wait(0.2) end
                            local rel = acquireMutex()
                            teleportTo(npcRoot.CFrame * CFrame.new(0, 0, -1.8))
                            task.wait(0.12)
                            if tool.Parent == char then tool:Activate() end
                            rel()
                            task.wait(0.25)
                        end
                    end
                end
            end
        end
    end
end)

-- INGREDIENT UI HELPERS
local sortedIngredients = {}
local ingredientBusy    = {}

for k, v in pairs(IngredientsConfig) do
    if type(v) == "table" and v.Cost then table.insert(sortedIngredients, k) end
end
table.sort(sortedIngredients, function(a, b) return tostring(a):lower() < tostring(b):lower() end)

local function getMaxStock(k)
    local d = IngredientsConfig[k]
    return tonumber(d and (d.MaxStock or d.Max or d.Capacity or d.Limit)) or 100
end

local function getCurrentStock(k)
    local ing = LocalPlayer:FindFirstChild("Ingredients")
    local slot = ing and ing:FindFirstChild(k)
    return slot and tonumber(slot.Value) or 0
end

local function buyIngredientAmount(ingredKey, quantity)
    if ingredientBusy[ingredKey] then return false end
    local data = IngredientsConfig[ingredKey]
    if not data or not data.Cost then return false end

    local qty = math.floor(tonumber(quantity) or 0)
    if qty <= 0 then return false end

    local cur    = getCurrentStock(ingredKey)
    local needed = math.min(qty, math.max(0, getMaxStock(ingredKey) - cur))
    if needed <= 0 then return false end

    ingredientBusy[ingredKey] = true
    local ok, res = pcall(function() return BuyIngredient:InvokeServer(ingredKey, needed, "Cash") end)
    task.wait(0.2)
    ingredientBusy[ingredKey] = nil
    return ok and res ~= false
end

-- SHOP UI HELPERS
local shopItems        = {}
local shopBusy         = {}
local autoBuyTables, selectedTables       = false, {}
local autoBuyChairs, selectedChairs       = false, {}
local autoBuyMaterials, selectedMaterials = false, {}
local autoBuyPaints, selectedPaints       = false, {}
local autoBuyTiles, selectedTiles         = false, {}
local autoBuyStoves, selectedStoves       = false, {}
local autoBuyCooldowns = {}

local function makeCompositeKey(category, key) return tostring(category) .. ":" .. tostring(key) end

local function getItemConfigByCategory(category, key)
    local cfgs = { Tables = TableConfig, Chairs = ChairConfig, Materials = MaterialConfig, Paints = PaintConfig, Tiles = TileConfig, Stoves = StoveConfig }
    local cfg = cfgs[category]
    if not cfg then return nil end
    if cfg.Get then local ok, res = pcall(function() return cfg:Get(key) end); if ok and res then return res end end
    return cfg[key]
end

local function getItemDisplayName(item)
    if not item then return "Unknown" end
    local cfg = item.Config
    if type(cfg) == "table" then return tostring(cfg.DisplayName or cfg.Name or item.Key) end
    return tostring(item.Key)
end

local function resolveItemConfig(systemType, category, key)
    if FurnitureConfig and FurnitureConfig.GetItemConfig then
        local ok, res = pcall(function() return FurnitureConfig:GetItemConfig(systemType, category, key) end)
        if ok and res then return res end
    end
    return getItemConfigByCategory(category, key)
end

local function refreshShopItems()
    local ok, data = pcall(function() return GetShopInfo:InvokeServer() end)
    if not ok or type(data) ~= "table" then return false end
    shopItems = {}
    local shopCategories = { "Tables", "Chairs", "Materials", "Paints", "Tiles", "Stoves" }
    for _, cat in ipairs(shopCategories) do
        local entries = data[cat]
        if type(entries) == "table" then
            for _, v in ipairs(entries) do
                if type(v) == "table" and v.Key ~= nil then
                    local key = tostring(v.Key)
                    local systemType = v.SystemType
                    if cat == "Tables" or cat == "Chairs" then systemType = "Dining"
                    elseif cat == "Stoves" then systemType = "Kitchen" end
                    shopItems[makeCompositeKey(cat, key)] = {
                        Key = key, Category = cat, SystemType = systemType,
                        Stock = tonumber(v.Stock) or 0, Price = tonumber(v.Price or v.Cost) or 0,
                        Config = resolveItemConfig(systemType, cat, key)
                    }
                end
            end
        end
    end
    return true
end

local function buyShopItem(item)
    if not item then return false end
    local key, category = tostring(item.Key), tostring(item.Category)
    local compKey = makeCompositeKey(category, key)
    if shopBusy[compKey] or (tonumber(item.Stock) or 0) <= 0 then return false end

    shopBusy[compKey] = true
    local systemType = item.SystemType
    if category == "Tables" or category == "Chairs" then systemType = "Dining"
    elseif category == "Stoves" then systemType = "Kitchen" end

    local ok, res = pcall(function() return BuyFurniture:InvokeServer(systemType, category, key) end)
    shopBusy[compKey] = nil
    if ok and res then task.spawn(refreshShopItems) return true end
    return false
end

local function findShopItem(category, displayName)
    for _, item in pairs(shopItems) do
        if item.Category == category and displayName == getItemDisplayName(item) then return item end
    end
end

local function getItemNamesByCategory(category)
    local names = {}
    for _, item in pairs(shopItems) do
        if item.Category == category then table.insert(names, getItemDisplayName(item)) end
    end
    table.sort(names)
    return names
end

local function autoBuyCategory(category, enabled, selectedNames)
    if not enabled or type(selectedNames) ~= "table" or #selectedNames == 0 then return end
    for _, name in ipairs(selectedNames) do
        local item = findShopItem(category, name)
        if item and (tonumber(item.Stock) or 0) > 0 then
            local compKey = makeCompositeKey(item.Category, item.Key)
            local now = os.clock()
            if now - (autoBuyCooldowns[compKey] or 0) >= 1 then
                autoBuyCooldowns[compKey] = now
                task.spawn(function() buyShopItem(item) end)
            end
        end
    end
end

-- SETUP ORION WINDOW & TABS
local Window = OrionLib:MakeWindow({
    Name = "Karinderya Toolkit | Orion UI",
    HidePremium = false,
    SaveConfig = true,
    ConfigFolder = "KarinderyaConfig"
})

local HomeTab        = Window:MakeTab({Name = "Home", Icon = "rbxassetid://4483345998", PremiumOnly = false})
local MainTab        = Window:MakeTab({Name = "Main", Icon = "rbxassetid://4483345998", PremiumOnly = false})
local ShopTab        = Window:MakeTab({Name = "Shop", Icon = "rbxassetid://4483345998", PremiumOnly = false})
local IngredientsTab = Window:MakeTab({Name = "Ingredients", Icon = "rbxassetid://4483345998", PremiumOnly = false})
local PlayerTab      = Window:MakeTab({Name = "Player", Icon = "rbxassetid://4483345998", PremiumOnly = false})
local SettingsTab    = Window:MakeTab({Name = "Settings", Icon = "rbxassetid://4483345998", PremiumOnly = false})
local ModsTab        = Window:MakeTab({Name = "Mods", Icon = "rbxassetid://4483345998", PremiumOnly = false})

-- HOME TAB
HomeTab:AddSection({Name = "Information"})
HomeTab:AddParagraph("Welcome", "Kumpletong Karinderya script na binuo at inayos para sa Orion Library UI!")
HomeTab:AddParagraph("Creator", "KnorkzykiiPH | Roblox: KnorkzykiiPH | TikTok: _jsephmols")
HomeTab:AddButton({
    Name = "Copy Discord Link",
    Callback = function()
        setclipboard("https://discord.gg/2PeDVr6pt")
        OrionLib:MakeNotification({Name = "Copied!", Content = "Discord link copied to clipboard.", Time = 3})
    end
})

-- MAIN TAB
MainTab:AddSection({Name = "Auto Serve & Orders"})
MainTab:AddToggle({Name = "Auto Serve Food", Default = false, Callback = function(v) Config.autoServe = v end})
MainTab:AddToggle({Name = "Auto Assign Customers", Default = false, Callback = function(v) Config.autoOrder = v end})
MainTab:AddToggle({Name = "Auto Serve Drinks", Default = false, Callback = function(v) Config.autoSoftdrinks = v end})

MainTab:AddSection({Name = "NPC Filter & Reject"})
MainTab:AddToggle({Name = "Auto Reject Selected Rarities", Default = false, Callback = function(v) Config.autoRejectNPC = v end})
MainTab:AddDropdown({
    Name = "Reject Rarities",
    Default = "",
    Options = npcRarityList,
    Callback = function(v)
        Config.rejectNPCList = {}
        if type(v) == "table" then
            for _, rarity in ipairs(v) do Config.rejectNPCList[rarity] = true end
        elseif type(v) == "string" and v ~= "" then
            Config.rejectNPCList[v] = true
        end
    end
})

MainTab:AddSection({Name = "Auto Cleaning & Pan"})
MainTab:AddToggle({Name = "Auto Wash Dishes", Default = false, Callback = function(v) Config.autoWash = v end})
MainTab:AddToggle({Name = "Auto Pan", Default = false, Callback = function(v) Config.autoPan = v end})
MainTab:AddToggle({
    Name = "Auto TP & Instant Clean Trash",
    Default = false,
    Callback = function(v)
        Config.autoTP = v
        trashInstantPickup = v
    end
})

MainTab:AddSection({Name = "Menus & Codes"})
MainTab:AddToggle({Name = "Auto Unlock Menu", Default = false, Callback = function(v) Config.autoUnlockMenu = v end})
MainTab:AddToggle({Name = "Auto Claim Codes", Default = false, Callback = function(v) Config.autoClaimCodes = v end})
MainTab:AddButton({
    Name = "Enable All Menus",
    Callback = function()
        task.spawn(function()
            local ok, data = pcall(function() return GetMenuData:InvokeServer() end)
            if not ok or not data then return end
            local unlocked = data.UnlockedMenus or {}
            for _, menuName in ipairs({ "LUGAW", "SILOG", "SILOG 2", "LUTONG BAHAY", "Pasta Meal" }) do
                if unlocked[menuName] == true then
                    pcall(function() ToggleMenu:InvokeServer(menuName, true) end)
                    task.wait(0.25)
                end
            end
        end)
    end
})
MainTab:AddButton({
    Name = "Upgrade to Golden Pan",
    Callback = function() pcall(function() UpgradeToGoldenPan:InvokeServer() end) end
})

-- PLAYER TAB
PlayerTab:AddSection({Name = "Movement & Utilities"})
PlayerTab:AddSlider({
    Name = "WalkSpeed",
    Min = 16, Max = 100, Default = 16, Increment = 1,
    Callback = function(v)
        Config.walkSpeed = v
        local _, hum = getCharacter()
        if hum then hum.WalkSpeed = v end
    end
})
PlayerTab:AddToggle({Name = "Infinite Jump", Default = false, Callback = function(v) Config.infJump = v end})
PlayerTab:AddToggle({Name = "NoClip", Default = false, Callback = function(v) Config.noclip = v; setNoclip(v) end})
PlayerTab:AddButton({
    Name = "Anti AFK",
    Callback = function()
        LocalPlayer.Idled:Connect(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new(0,0))
        end)
        OrionLib:MakeNotification({Name = "Anti AFK", Content = "Anti AFK is running!", Time = 3})
    end
})

PlayerTab:AddSection({Name = "Teleports"})
PlayerTab:AddButton({
    Name = "Teleport to Counter",
    Callback = function()
        local plot = getPlot()
        if plot and plot:FindFirstChild("Counter") then
            local comp = plot.Counter:FindFirstChild("Comp", true)
            if comp then teleportTo(comp.CFrame * CFrame.new(0, 3, 0)) end
        end
    end
})
PlayerTab:AddButton({
    Name = "Teleport to Kitchen",
    Callback = function()
        local plot = getPlot()
        if plot and plot:FindFirstChild("KitchenPlot1") then
            local first = plot.KitchenPlot1:GetChildren()[1]
            if first then teleportTo(first:GetPivot() * CFrame.new(0, 3, 0)) end
        end
    end
})
PlayerTab:AddButton({
    Name = "Teleport to Serve Area",
    Callback = function()
        local plot = getPlot()
        if plot and plot:FindFirstChild("Serve") then
            local first = plot.Serve:GetChildren()[1]
            if first then teleportTo(first:GetPivot() * CFrame.new(0, 3, 0)) end
        end
    end
})
PlayerTab:AddButton({
    Name = "Teleport to Grocery",
    Callback = function()
        local grocery = Workspace:FindFirstChild("Grocery")
        if grocery then
            local comp = grocery:FindFirstChild("Comp", true)
            if comp then teleportTo(comp.CFrame * CFrame.new(0, 3, 0)) end
        end
    end
})

-- SETTINGS TAB
SettingsTab:AddSection({Name = "Delays"})
SettingsTab:AddSlider({
    Name = "Serve Delay", Min = 0.01, Max = 2, Default = Config.serveDelay, Increment = 0.01,
    Callback = function(v) Config.serveDelay = v end
})
SettingsTab:AddSlider({
    Name = "Order Delay", Min = 0.1, Max = 2, Default = Config.orderDelay, Increment = 0.1,
    Callback = function(v) Config.orderDelay = v end
})
SettingsTab:AddSlider({
    Name = "Wash Delay", Min = 0.1, Max = 2, Default = Config.washDelay, Increment = 0.1,
    Callback = function(v) Config.washDelay = v end
})

-- MODS TAB
ModsTab:AddSection({Name = "Anti Mod"})
ModsTab:AddToggle({
    Name = "Anti Mod (Kick when staff joins)",
    Default = false,
    Callback = function(v)
        Config.antiMod = v
        if v then
            for _, player in ipairs(Players:GetPlayers()) do
                if isStaff(player) then LocalPlayer:Kick("Staff detected") return end
            end
        end
    end
})

-- INGREDIENTS TAB
IngredientsTab:AddSection({Name = "Ingredient Auto Buy"})
IngredientsTab:AddSlider({
    Name = "Buy Threshold (%)", Min = 5, Max = 30, Default = 5, Increment = 1,
    Callback = function(v) autoBuyThreshold = v end
})
IngredientsTab:AddToggle({
    Name = "Auto Buy Ingredients", Default = false,
    Callback = function(v) Config.autoBuyIngredients = v end
})

IngredientsTab:AddSection({Name = "Buy Ingredients Manually"})
for _, ingredKey in ipairs(sortedIngredients) do
    local key = ingredKey
    IngredientsTab:AddButton({
        Name = "Buy " .. tostring(key),
        Callback = function() buyIngredientAmount(key, 1) end
    })
end

-- SHOP TAB
refreshShopItems()

ShopTab:AddSection({Name = "Auto Buy Furniture"})
ShopTab:AddToggle({Name = "Auto Buy Tables", Default = false, Callback = function(v) autoBuyTables = v end})
ShopTab:AddDropdown({
    Name = "Select Tables", Default = "", Options = getItemNamesByCategory("Tables"),
    Callback = function(v) selectedTables = type(v) == "table" and v or {v} end
})

ShopTab:AddToggle({Name = "Auto Buy Chairs", Default = false, Callback = function(v) autoBuyChairs = v end})
ShopTab:AddDropdown({
    Name = "Select Chairs", Default = "", Options = getItemNamesByCategory("Chairs"),
    Callback = function(v) selectedChairs = type(v) == "table" and v or {v} end
})

ShopTab:AddToggle({Name = "Auto Buy Materials", Default = false, Callback = function(v) autoBuyMaterials = v end})
ShopTab:AddDropdown({
    Name = "Select Materials", Default = "", Options = getItemNamesByCategory("Materials"),
    Callback = function(v) selectedMaterials = type(v) == "table" and v or {v} end
})

ShopTab:AddToggle({Name = "Auto Buy Stoves", Default = false, Callback = function(v) autoBuyStoves = v end})
ShopTab:AddDropdown({
    Name = "Select Stoves", Default = "", Options = getItemNamesByCategory("Stoves"),
    Callback = function(v) selectedStoves = type(v) == "table" and v or {v} end
})

ShopRestocked.OnClientEvent:Connect(function()
    task.wait(0.2)
    refreshShopItems()
end)

-- RUNTIME LOOPS

-- Auto Serve & Softdrinks Loop
task.spawn(function()
    while true do
        if Config.autoServe then
            local count = 0
            local plot  = getPlot()
            if plot then
                local diningPlot = plot:FindFirstChild("DiningPlot1")
                if diningPlot then
                    for _, tableModel in ipairs(diningPlot:GetChildren()) do
                        if count >= 8 then break end
                        if tableModel:IsA("Model") then
                            for _, desc in ipairs(tableModel:GetDescendants()) do
                                if count >= 8 then break end
                                if desc:IsA("ProximityPrompt") and desc.Enabled and string.sub(desc.ActionText, 1, 5) == "Serve" then
                                    local parent = desc.Parent
                                    if parent and parent:IsA("BasePart") then
                                        local rel = acquireMutex()
                                        teleportTo(parent.CFrame * CFrame.new(0, 3, 0))
                                        task.wait(0.15)
                                        pcall(function() fireproximityprompt(desc) end)
                                        rel()
                                        count += 1
                                        task.wait(Config.serveDelay)
                                    end
                                end
                            end
                        end
                    end
                end

                local serveArea = plot:FindFirstChild("Serve")
                if serveArea then
                    for _, desc in ipairs(serveArea:GetDescendants()) do
                        if count >= 8 then break end
                        if desc:IsA("ProximityPrompt") and desc.Enabled then
                            local parent = desc.Parent
                            if parent and parent:IsA("BasePart") then
                                local rel = acquireMutex()
                                teleportTo(parent.CFrame * CFrame.new(0, 3, 0))
                                task.wait(0.15)
                                pcall(function() fireproximityprompt(desc) end)
                                rel()
                                count += 1
                                task.wait(Config.serveDelay)
                            end
                        end
                    end
                end
            end

            if Config.autoSoftdrinks then
                for _ = 1, 5 do
                    if not deliverNextSoftdrink() then break end
                    task.wait(0.1)
                end
            end
        end
        task.wait(0.3)
    end
end)

-- Auto Assign Customers Loop
task.spawn(function()
    local tookOrder = false
    while true do
        if Config.autoOrder then
            for _ = 1, 15 do
                if not Config.autoOrder then break end
                local plot = getPlot()
                if not plot then break end

                local ok, counterData, slots = pcall(function() return GetCounterInfo:InvokeServer() end)
                local failed = not ok or not counterData or not slots

                if failed then
                    local counter = plot:FindFirstChild("Counter")
                    if counter then
                        local comp = counter:FindFirstChild("Comp", true)
                        if comp then
                            for _, v in ipairs(comp:GetDescendants()) do
                                if v:IsA("ProximityPrompt") and v.Enabled then
                                    local action = tostring(v.ActionText)
                                    if string.find(action, "Take Order") or string.find(action, "Take") then
                                        local parent = v.Parent
                                        if parent and parent:IsA("BasePart") then
                                            local rel = acquireMutex()
                                            teleportTo(parent.CFrame * CFrame.new(0, 3, 0))
                                            task.wait(0.01)
                                            pcall(function() fireproximityprompt(v) end)
                                            rel()
                                            tookOrder = true
                                        end
                                    end
                                end
                                if tookOrder then break end
                            end
                        end
                    end
                    if not tookOrder then break end
                end

                if tookOrder then break end

                local npcId   = counterData.NpcId or counterData.TemplateName or ""
                local npcName = counterData.TemplateName or ""
                if npcId == "" or npcName == "" then break end

                local npcData  = NPCConfig.Types[npcName]
                local rarity   = npcData and npcData.Rarity or "Unknown"
                local shouldReject = Config.autoRejectNPC and next(Config.rejectNPCList) ~= nil and Config.rejectNPCList[rarity]

                if shouldReject then
                    pcall(function() RejectNPC:FireServer(npcId) end)
                    task.wait(0.5)
                    break
                end

                trackNPC(npcId)

                local assigned = false
                for _, slot in ipairs(slots) do
                    if slot.Slot and slot.Seat and pcall(function()
                        AssignNPC:FireServer({ Slot = slot.Slot, Seat = slot.Seat, NPCName = npcId, NpcId = npcId })
                    end) then
                        assigned = true
                        break
                    end
                end
                if not assigned then break end
                task.wait(0.05)
            end
        end
        tookOrder = false
        task.wait(0.5)
    end
end)

-- Auto Wash Dishes Loop
task.spawn(function()
    while true do
        if Config.autoWash then
            local plot = getPlot()
            if plot then
                local sink = plot:FindFirstChild("Sink")
                local searchAreas = {}
                if plot:FindFirstChild("DiningPlot1") then table.insert(searchAreas, plot.DiningPlot1) end
                if plot:FindFirstChild("Serve") then table.insert(searchAreas, plot.Serve) end

                for _, area in ipairs(searchAreas) do
                    for _, desc in ipairs(area:GetDescendants()) do
                        if desc:IsA("ProximityPrompt") and desc.Enabled then
                            local actionText = desc.ActionText:lower()
                            local objectText = desc.ObjectText:lower()
                            local isDirty = string.find(objectText, "dirty") or string.find(objectText, "dish") or string.find(actionText, "wash") or string.find(actionText, "pick")

                            if isDirty then
                                local parent = desc.Parent
                                if parent and parent:IsA("BasePart") then
                                    local rel = acquireMutex()
                                    teleportTo(parent.CFrame * CFrame.new(0, 3, 0))
                                    task.wait(0.6)
                                    pcall(function() if desc.Enabled then fireproximityprompt(desc) end end)
                                    rel()
                                    task.wait(0.3)

                                    local gotTool = false
                                    for _ = 1, 20 do
                                        local char = LocalPlayer.Character
                                        if char and char:FindFirstChildOfClass("Tool") then gotTool = true; break end
                                        task.wait(0.1)
                                    end

                                    if gotTool and sink then
                                        task.wait(0.15)
                                        for _, v in ipairs(sink:GetDescendants()) do
                                            if v:IsA("ProximityPrompt") and v.Enabled then
                                                local act = v.ActionText:lower()
                                                if string.find(act, "put") or string.find(act, "place") or v.Name == "Put" then
                                                    local rel2 = acquireMutex()
                                                    teleportTo(v.Parent.CFrame * CFrame.new(0, 3, 0))
                                                    task.wait(0.2)
                                                    pcall(function() if v.Enabled then fireproximityprompt(v) end end)
                                                    rel2()
                                                    task.wait(0.5)
                                                    break
                                                end
                                            end
                                        end
                                    end

                                    pcall(function()
                                        local char = LocalPlayer.Character
                                        if char then
                                            local tool = char:FindFirstChildOfClass("Tool")
                                            if tool then tool.Parent = LocalPlayer.Backpack end
                                        end
                                    end)
                                end
                            end
                        end
                    end
                end

                if sink then
                    for _ = 1, 20 do
                        local washPrompt = nil
                        for _, v in ipairs(sink:GetDescendants()) do
                            if v:IsA("ProximityPrompt") and v.Enabled then
                                local act, obj = v.ActionText:lower(), v.ObjectText:lower()
                                if string.find(act, "wash") or string.find(act, "clean") or string.find(act, "scrub") or string.find(obj, "dish") or string.find(obj, "dirty") or string.find(obj, "plate") then
                                    washPrompt = v; break
                                end
                            end
                        end

                        if not washPrompt or not washPrompt.Parent or not washPrompt.Parent:IsA("BasePart") then break end

                        local rel = acquireMutex()
                        teleportTo(washPrompt.Parent.CFrame * CFrame.new(0, 3, 0))
                        task.wait(0.6)

                        local t0, holdBegun = os.clock(), false
                        while washPrompt and washPrompt.Parent and washPrompt.Enabled and os.clock() - t0 < 6 do
                            if not holdBegun and pcall(function() washPrompt:InputHoldBegin() end) then holdBegun = true end
                            task.wait(0.1)
                            if holdBegun and washPrompt.Parent and washPrompt.Enabled then
                                pcall(function() washPrompt:InputHoldBegin() end)
                            else
                                holdBegun = false
                            end
                        end
                        pcall(function() if washPrompt and washPrompt.Parent then washPrompt:InputHoldEnd() end end)
                        rel()
                        task.wait(0.5)
                    end
                end
            end
        end
        task.wait(Config.washDelay)
    end
end)

-- Auto Buy Ingredients Loop
task.spawn(function()
    while true do
        if Config.autoBuyIngredients then
            for _, key in ipairs(sortedIngredients) do
                if not ingredientBusy[key] then
                    local cur = getCurrentStock(key)
                    local max = getMaxStock(key)
                    if max > 0 and cur < max and (cur / max * 100) <= autoBuyThreshold then
                        buyIngredientAmount(key, 1)
                        task.wait(0.75)
                    end
                end
            end
        end
        task.wait(0.5)
    end
end)

-- Auto Buy Shop Furniture Loop
task.spawn(function()
    while true do
        autoBuyCategory("Tables",    autoBuyTables,    selectedTables)
        autoBuyCategory("Chairs",    autoBuyChairs,    selectedChairs)
        autoBuyCategory("Materials", autoBuyMaterials, selectedMaterials)
        autoBuyCategory("Paints",    autoBuyPaints,    selectedPaints)
        autoBuyCategory("Tiles",     autoBuyTiles,     selectedTiles)
        autoBuyCategory("Stoves",    autoBuyStoves,    selectedStoves)
        task.wait(1)
    end
end)

-- Auto Unlock Menu Loop
task.spawn(function()
    local menuRequirements = {
        { Name = "SILOG", Requirement = 100, UnlockedKey = "SILOG" },
        { Name = "SILOG 2", Requirement = 400, UnlockedKey = "SILOG 2" },
        { Name = "LUTONG BAHAY", Requirement = 670, UnlockedKey = "LUTONG BAHAY" },
        { Name = "Pasta Meal", Requirement = 1994, UnlockedKey = "Pasta Meal" },
    }
    while true do
        if Config.autoUnlockMenu then
            local ok, data = pcall(function() return GetMenuData:InvokeServer() end)
            if ok and data then
                local totalServed = tonumber(data.TotalServed) or 0
                local unlocked    = data.UnlockedMenus or {}
                for _, menu in ipairs(menuRequirements) do
                    if totalServed >= menu.Requirement and unlocked[menu.UnlockedKey] ~= true then
                        local success, res = pcall(function() return UnlockMenu:InvokeServer(menu.Name) end)
                        if success and res == true then
                            unlocked[menu.UnlockedKey] = true
                            task.wait(1)
                        end
                    end
                end
            end
        end
        task.wait(15)
    end
end)

-- Auto Claim Codes Loop
task.spawn(function()
    local claimedCodes = {}
    while true do
        if Config.autoClaimCodes then
            for _, code in ipairs({ "BATINATAYOHA", "2MVISITS", "50KCCU", "BAKARENEPAIRYAN" }) do
                if not claimedCodes[code] then
                    pcall(function() RedeemCode:FireServer(code) end)
                    claimedCodes[code] = true
                    task.wait(3)
                end
            end
        end
        task.wait(10)
    end
end)

-- PLAYER INPUT CONNECTIONS
UserInputService.JumpRequest:Connect(function()
    if Config.infJump then
        local _, hum = getCharacter()
        if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end
end)

-- INITIALIZE ORION
OrionLib:Init()