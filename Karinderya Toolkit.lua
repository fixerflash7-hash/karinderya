-- Karinderya Toolkit by KnorkzykiiPH
-- Cleaned & deobfuscated
-- discord.gg/syncrypt
-- SERVICES
local ProximityPromptService = game:GetService("ProximityPromptService")
local Players                = game:GetService("Players")
local ReplicatedStorage      = game:GetService("ReplicatedStorage")
local Workspace              = game:GetService("Workspace")
local UserInputService       = game:GetService("UserInputService")
local RunService             = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
-- REMOTES
local Remotes       = ReplicatedStorage:WaitForChild("Remotes")
local ShopRemotes   = Remotes:WaitForChild("ShopRemotes")
local CounterRemotes = Remotes:WaitForChild("CounterRemotes")
local NPCRemotes    = Remotes:WaitForChild("NPCRemotes")
local MenuRemotes   = Remotes:WaitForChild("MenuRemotes")

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

-- optional remotes
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
local FoodConfig        = require(Modules:WaitForChild("FoodConfig"))
local IngredientsConfig = require(Modules:WaitForChild("IngredientsConfig"))
local FurnitureConfig   = require(Modules:WaitForChild("FurnitureConfig"))
local NPCConfig         = require(Modules:WaitForChild("NPCConfig"))
-- WIND UI INIT
local WindUI = nil
local _, result = pcall(function()
    return loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
end)
WindUI = result

pcall(function()
    WindUI:Notify({
        Title   = "Script Executed!",
        Content = "Script Loading...",
        Duration = 3.2,
    })
end)

task.wait(({ 0.3, 0.6, 0.9, 1.2 })[math.random(1, 4)])
-- NPC RARITY LIST (from NPCConfig)
local npcRarityList   = {}
local npcRaritySeen   = {}
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
-- STATE
local pendingSoftdrinkOrders = {}  -- current queue of softdrink flavors to deliver
local softdrinkCooldowns     = {}  -- per-flavor cooldown timestamps
local softdrinkStats         = { given = 0, state = "Watching for requests" }
local eventConnections       = {}  -- active RBXScriptConnections to clean up

local Config = {
    autoServe         = false,
    autoOrder         = false,
    autoRejectNPC     = false,
    rejectNPCList     = {},
    autoClaimCodes    = false,
    antiMod           = false,
    autoPan           = false,
    autoWash          = false,
    autoSoftdrinks    = false,
    autoBuyIngredients = false,
    autoTP            = false,
    noclip            = false,
    walkSpeed         = 16,
    infJump           = false,
    autoUnlockMenu    = false,
    serveDelay        = 0.01,
    orderDelay        = 0.01,
    washDelay         = 0.3,
}
-- UTILITY FUNCTIONS
-- returns the player's Karenderya plot
local function getPlot()
    for _, child in ipairs(Workspace:GetChildren()) do
        if string.find(child.Name, "^Karenderya") and child:GetAttribute("Owner") == LocalPlayer.UserId then
            return child
        end
    end
end

-- returns current cash balance
local function getCash()
    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    if leaderstats then
        local Cash = leaderstats:FindFirstChild("Cash")
        if Cash then return Cash.Value end
    end
    return 0
end

-- returns character and humanoid
local function getCharacter()
    return LocalPlayer.Character, LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
end

-- teleports character to a CFrame
local function teleportTo(cf)
    local char = LocalPlayer.Character
    if char then
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then hrp.CFrame = cf end
    end
end

-- returns HumanoidRootPart or nil
local function getHRP()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

-- resolves a softdrink ingredient key from a loose string
local function resolveSoftdrinkKey(raw)
    if not raw then return "Kola" end
    local normalized = tostring(raw):lower():gsub("%s+", "")
    for k in pairs(IngredientsConfig or {}) do
        if normalized == tostring(k):lower():gsub("%s+", "") then
            return k
        end
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
-- MUTEX (prevents concurrent teleport/action overlap)
local mutexLocked = false
local function acquireMutex()
    while mutexLocked do task.wait(0.05) end
    mutexLocked = true
    return function() mutexLocked = false end
end
-- SOFTDRINK EVENT CONNECTIONS
-- clear old connections
for _, conn in ipairs(eventConnections) do pcall(function() conn:Disconnect() end) end
eventConnections = {}

table.insert(eventConnections, SoftdrinkOrdersUpdated.OnClientEvent:Connect(function(orders)
    if type(orders) == "table" then
        pendingSoftdrinkOrders = {}
        for _, v in pairs(orders) do
            table.insert(pendingSoftdrinkOrders, resolveSoftdrinkKey(v))
        end
    end
end))

table.insert(eventConnections, AdditionalOrder.OnClientEvent:Connect(function(_, flavor)
    if flavor ~= nil then
        table.insert(pendingSoftdrinkOrders, resolveSoftdrinkKey(flavor))
    end
end))

table.insert(eventConnections, NPCDrink.OnClientEvent:Connect(function(_, flavor)
    softdrinkStats.given += 1
    softdrinkStats.state = string.format("Delivered %s!", resolveSoftdrinkKey(flavor))
end))
-- INGREDIENT HELPERS
-- buy one unit of an ingredient if affordable
local function buyOneIngredient(ingredKey)
    local data = IngredientsConfig[ingredKey]
    if not data or not data.Cost then return false end
    if getCash() - data.Cost < 5000 then return false end
    local ok, res = pcall(function() return BuyIngredient:InvokeServer(ingredKey, 1, "Cash") end)
    return ok and res
end

-- deliver the next softdrink order
local function deliverNextSoftdrink()
    if not Config.autoSoftdrinks or #pendingSoftdrinkOrders == 0 then return false end

    local flavor   = pendingSoftdrinkOrders[1]
    local key      = resolveSoftdrinkKey(flavor)
    local now      = os.clock()

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
            softdrinkStats.state    = key .. " out of stock"
            return false
        end
    end

    local ok, res, err = pcall(function() return GiveSoftdrink:InvokeServer(key) end)
    if ok and res then
        table.remove(pendingSoftdrinkOrders, 1)
        softdrinkStats.given += 1
        softdrinkStats.state = string.format("Delivered %s!", key)
        return true
    end

    if tostring(err):match("Nobody") or tostring(err):match("ordered") then
        table.remove(pendingSoftdrinkOrders, 1)
    end
    softdrinkStats.state = string.format("%s: %s", key, tostring(err or res))
    return false
end
-- NPC / DINING TRACKING
local seenNPCs = {}
local function trackNPC(npcName)
    if npcName and npcName ~= "" then seenNPCs[npcName] = true end
end
local function isTrackedNPC(npc)
    return seenNPCs[npc.Name] == true
end

task.spawn(function()
    while true do
        local plot = getPlot()
        if plot then
            local diningPlot = plot:FindFirstChild("DiningPlot1")
            if diningPlot then
                for _, child in ipairs(diningPlot:GetChildren()) do
                    if child:IsA("Model") then
                        local occ1 = child:GetAttribute("OccupiedBy1")
                        local occ2 = child:GetAttribute("OccupiedBy2")
                        if occ1 then trackNPC(occ1) end
                        if occ2 then trackNPC(occ2) end
                    end
                end
            end
        end
        task.wait(1)
    end
end)
-- TRASH SYSTEM
local trashNames = {
    BoyBawang = true,
    Dirt      = true,
    Leaves    = true,
    Pizza     = true,
    Plastic   = true,
    Tsinelas  = true,
}
local trashInstantPickup   = true
local lastCleanedTrash     = nil

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

local function getPartFromPrompt(prompt)
    local parent = prompt and prompt.Parent
    if not parent then return nil end
    if parent:IsA("BasePart") then return parent end
    if parent:IsA("Model") then return parent.PrimaryPart or parent:FindFirstChildWhichIsA("BasePart", true) end
    return parent:FindFirstChildWhichIsA("BasePart", true)
end

-- set trash prompt hold to 0 for instant pickup
local function patchTrashPrompt(prompt)
    pcall(function()
        if isTrashPrompt(prompt) and trashInstantPickup then
            prompt.HoldDuration = 0
        end
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
                    nearest     = desc
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

-- patch all registered proximity prompts for instant trash pickup
pcall(function()
    ProximityPromptService.PromptShown:Connect(patchTrashPrompt)
    for _, v in ipairs(ProximityPromptService:GetRegisteredPrompts()) do
        patchTrashPrompt(v)
    end
end)
-- NOCLIP
local noclipConnection = nil
local function setNoclip(enabled)
    if noclipConnection then
        noclipConnection:Disconnect()
        noclipConnection = nil
    end
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
local GROUP_ID    = 985559810
local staffRanks  = { Dev = true, Admin = true }

local function isStaff(player)
    if not player or player == LocalPlayer then return false end
    local ok, role = pcall(function() return player:GetRoleInGroup(GROUP_ID) end)
    return ok and staffRanks[role] == true
end

Players.PlayerAdded:Connect(function(player)
    if not Config.antiMod then return end
    if isStaff(player) then LocalPlayer:Kick("Staff detected") end
end)
-- AUTO PAN
local panToolNames = { pan = true, goldenpan = true, vippan = true }
local panReturning = false
local panChasing   = false

local function findPanTool()
    for _, container in ipairs({ LocalPlayer:FindFirstChild("Backpack"), LocalPlayer.Character }) do
        if container then
            for _, tool in ipairs(container:GetChildren()) do
                if tool:IsA("Tool") and panToolNames[string.lower(tool.Name)] then
                    return tool
                end
            end
        end
    end
    return nil
end

task.spawn(function()
    while task.wait(0.5) do
        if not Config.autoPan then
            panReturning = false
            panChasing   = false
        else
            local char, humanoid = getCharacter()
            if char and humanoid then
                local ClientNPCs   = Workspace:FindFirstChild("ClientNPCs")
                local runawayTarget = nil

                if ClientNPCs then
                    for _, child in ipairs(ClientNPCs:GetChildren()) do
                        if not Config.autoPan then break end
                        if child:IsA("Model") and child:GetAttribute("IsRunaway") == true and isTrackedNPC(child) then
                            runawayTarget = child
                            break
                        end
                    end
                end

                if not runawayTarget then
                    if panChasing and not panReturning then
                        panReturning = true
                        panChasing   = false
                        local tool = findPanTool()
                        pcall(function()
                            if tool and tool.Parent == char then humanoid:UnequipTools() end
                        end)
                        task.wait(0.15)

                        if Config.autoPan then
                            local plot   = getPlot()
                            local counter = plot and plot:FindFirstChild("Counter")
                            if counter then
                                local counterPart = counter:IsA("BasePart") and counter
                                    or counter:FindFirstChildWhichIsA("BasePart", true)
                                if counterPart and Config.autoPan then
                                    local release = acquireMutex()
                                    pcall(function()
                                        if Config.autoPan then
                                            teleportTo(counterPart.CFrame * CFrame.new(0, 3, 0))
                                        end
                                    end)
                                    pcall(release)
                                end
                            end
                        end
                    end
                else
                    local npcRoot = runawayTarget:FindFirstChild("HumanoidRootPart") or runawayTarget.PrimaryPart
                    panChasing    = true
                    panReturning  = false

                    if npcRoot and npcRoot.Parent then
                        local tool = findPanTool()
                        if tool then
                            if char ~= tool.Parent then
                                pcall(function() humanoid:EquipTool(tool) end)
                                task.wait(0.2)
                            end
                            if Config.autoPan then
                                local release = acquireMutex()
                                pcall(function()
                                    if npcRoot.Parent and Config.autoPan then
                                        teleportTo(npcRoot.CFrame * CFrame.new(0, 0, -1.8))
                                    end
                                    task.wait(0.12)
                                    if Config.autoPan and tool.Parent == char then
                                        tool:Activate()
                                    end
                                end)
                                pcall(release)
                                task.wait(0.25)
                            end
                        end
                    end
                end
            end
        end
    end
end)
-- INGREDIENT STOCK HELPERS
local sortedIngredients  = {}
local ingredientUIRefs   = {}  -- key -> WindUI paragraph element
local ingredientBusy     = {}  -- key -> bool (purchase in-flight)
local autoBuyThreshold   = 5

for k, v in pairs(IngredientsConfig) do
    if type(v) == "table" and v.Cost then
        table.insert(sortedIngredients, k)
    end
end
table.sort(sortedIngredients, function(a, b)
    return tostring(a):lower() < tostring(b):lower()
end)

local function getMaxStock(ingredKey)
    local data = IngredientsConfig[ingredKey]
    if not data then return 100 end
    return tonumber(data.MaxStock or data.Max or data.Capacity or data.Limit) or 100
end

local function getCurrentStock(ingredKey)
    local Ingredients = LocalPlayer:FindFirstChild("Ingredients")
    if not Ingredients then return 0 end
    local slot = Ingredients:FindFirstChild(ingredKey)
    return slot and tonumber(slot.Value) or 0
end

local function updateIngredientLabel(ingredKey)
    local uiRef = ingredientUIRefs[ingredKey]
    if not uiRef then return end
    local cur  = getCurrentStock(ingredKey)
    local max  = getMaxStock(ingredKey)
    local pct  = (max > 0) and math.clamp(cur / max * 100, 0, 100) or 0
    uiRef:SetDesc(string.format("%d / %d (%d%%)", cur, max, math.floor(pct + 0.5)))
end

local function updateAllIngredientLabels()
    for _, k in ipairs(sortedIngredients) do
        updateIngredientLabel(k)
    end
end

-- buy a specific quantity of an ingredient
local function buyIngredientAmount(ingredKey, quantity)
    if ingredientBusy[ingredKey] then return false end
    local data = IngredientsConfig[ingredKey]
    if not data or not data.Cost then return false end

    local qty  = math.floor(tonumber(quantity) or 0)
    if qty <= 0 then return false end

    local cur    = getCurrentStock(ingredKey)
    local needed = math.min(qty, math.max(0, getMaxStock(ingredKey) - cur))
    if needed <= 0 then return false end

    ingredientBusy[ingredKey] = true
    local ok, res = pcall(function() return BuyIngredient:InvokeServer(ingredKey, needed, "Cash") end)
    task.wait(0.2)
    ingredientBusy[ingredKey] = nil
    updateIngredientLabel(ingredKey)
    return ok and res ~= false
end

-- buy up to max stock
local function buyIngredientMax(ingredKey)
    local cur    = getCurrentStock(ingredKey)
    local needed = math.max(0, getMaxStock(ingredKey) - cur)
    if needed <= 0 then return false end
    return buyIngredientAmount(ingredKey, needed)
end
-- SHOP ITEM HELPERS
local shopItems      = {}  -- compositeKey -> item data table
local shopUIRefs     = {}  -- compositeKey -> WindUI paragraph element
local shopBusy       = {}  -- compositeKey -> bool

local autoBuyTables    = false; local selectedTables    = {}
local autoBuyChairs    = false; local selectedChairs    = {}
local autoBuyMaterials = false; local selectedMaterials = {}
local autoBuyPaints    = false; local selectedPaints    = {}
local autoBuyTiles     = false; local selectedTiles     = {}
local autoBuyStoves    = false; local selectedStoves    = {}

local autoBuyCooldowns = {}

local function makeCompositeKey(category, key)
    return tostring(category) .. ":" .. tostring(key)
end

-- resolve config for a shop item by category
local function getItemConfigByCategory(category, key)
    local configs = {
        Tables    = TableConfig,
        Chairs    = ChairConfig,
        Materials = MaterialConfig,
        Paints    = PaintConfig,
        Tiles     = TileConfig,
        Stoves    = StoveConfig,
    }
    local cfg = configs[category]
    if not cfg then return nil end
    if cfg.Get then
        local ok, res = pcall(function() return cfg:Get(key) end)
        if ok and res then return res end
    end
    return cfg[key]
end

-- get display name of a shop item
local function getItemDisplayName(item)
    if not item then return "Unknown" end
    local cfg = item.Config
    if type(cfg) == "table" then
        return tostring(cfg.DisplayName or cfg.Name or item.Key)
    end
    return tostring(item.Key)
end

-- get item config via FurnitureConfig or fallback
local function resolveItemConfig(systemType, category, key)
    if FurnitureConfig and FurnitureConfig.GetItemConfig then
        local ok, res = pcall(function() return FurnitureConfig:GetItemConfig(systemType, category, key) end)
        if ok and res then return res end
    end
    return getItemConfigByCategory(category, key)
end

-- parse one category of shop response into shopItems
local function parseShopCategory(shopData, category)
    local entries = shopData and shopData[category]
    if type(entries) ~= "table" then return end

    for _, v in ipairs(entries) do
        if type(v) == "table" and v.Key ~= nil then
            local key        = tostring(v.Key)
            local systemType = v.SystemType
            if category == "Tables" or category == "Chairs" then
                systemType = "Dining"
            elseif category == "Stoves" then
                systemType = "Kitchen"
            end

            local compositeKey = makeCompositeKey(category, key)
            local itemConfig   = resolveItemConfig(systemType, category, key)

            shopItems[compositeKey] = {
                Key        = key,
                Category   = category,
                SystemType = systemType,
                Stock      = tonumber(v.Stock)           or 0,
                Price      = tonumber(v.Price or v.Cost) or 0,
                Config     = itemConfig,
            }
        end
    end
end

local shopCategories = { "Tables", "Chairs", "Materials", "Paints", "Tiles", "Stoves" }

-- full refresh of shopItems from server
local function refreshShopItems()
    local ok, data = pcall(function() return GetShopInfo:InvokeServer() end)
    if not ok or type(data) ~= "table" then return false end
    shopItems = {}
    for _, cat in ipairs(shopCategories) do
        parseShopCategory(data, cat)
    end
    return true
end

-- partial refresh (only update stock/price, update UI labels)
local function refreshShopStockOnly()
    local ok, data = pcall(function() return GetShopInfo:InvokeServer() end)
    if not ok or type(data) ~= "table" then return false end

    for _, cat in ipairs(shopCategories) do
        local entries = data[cat]
        if type(entries) == "table" then
            for _, v in ipairs(entries) do
                if type(v) == "table" and v.Key ~= nil then
                    local key          = tostring(v.Key)
                    local compositeKey = makeCompositeKey(cat, key)
                    local newStock     = tonumber(v.Stock) or 0

                    if shopItems[compositeKey] then
                        shopItems[compositeKey].Stock = newStock
                        local num = tonumber(v.Price or v.Cost)
                        if num then shopItems[compositeKey].Price = num end
                    end

                    local uiRef = shopUIRefs[compositeKey]
                    if uiRef then
                        if newStock > 0 then
                            uiRef:SetDesc("Stock: " .. tostring(newStock))
                        else
                            uiRef:SetDesc("Stock: 0 | SOLD OUT")
                        end
                    end
                end
            end
        end
    end
    return true
end

-- get item price
local function getItemPrice(item)
    if not item then return 0 end
    local cfg = item.Config
    if type(cfg) == "table" then
        local num = tonumber(cfg.Price or cfg.Cost)
        if num then return num end
    end
    return tonumber(item.Price or item.Cost) or 0
end

-- buy one shop item
local function buyShopItem(item, notify)
    if not item then return false end
    local key          = tostring(item.Key)
    local category     = tostring(item.Category)
    local compositeKey = makeCompositeKey(category, key)

    if shopBusy[compositeKey] then return false end
    if (tonumber(item.Stock) or 0) <= 0 then return false end

    shopBusy[compositeKey] = true

    local systemType = item.SystemType
    if category == "Tables" or category == "Chairs" then systemType = "Dining"
    elseif category == "Stoves" then systemType = "Kitchen" end

    local ok, res = pcall(function() return BuyFurniture:InvokeServer(systemType, category, key) end)
    shopBusy[compositeKey] = nil

    if ok and res then
        if notify then
            pcall(function()
                WindUI:Notify({
                    Title    = "Shop",
                    Content  = "Bought " .. tostring(getItemDisplayName(item)),
                    Duration = 1.2,
                })
            end)
        end
        task.spawn(function()
            task.wait(0.15)
            refreshShopItems()
            refreshShopStockOnly()
        end)
        return true
    end

    task.spawn(function() refreshShopStockOnly() end)
    return false
end

-- find an item in shopItems by category + display name
local function findShopItem(category, displayName)
    local name = tostring(displayName)
    for _, item in pairs(shopItems) do
        if item.Category == category and name == getItemDisplayName(item) then
            return item
        end
    end
    return nil
end

-- get sorted display names for a category
local function getItemNamesByCategory(category)
    local names = {}
    for _, item in pairs(shopItems) do
        if item.Category == category then
            table.insert(names, getItemDisplayName(item))
        end
    end
    table.sort(names)
    return names
end

-- auto buy loop helper: buy selected items from a category if enabled
local function autoBuyCategory(category, enabled, selectedNames)
    if not enabled then return end
    if type(selectedNames) ~= "table" or #selectedNames == 0 then return end

    for _, name in ipairs(selectedNames) do
        local item = findShopItem(category, name)
        if item and (tonumber(item.Stock) or 0) > 0 then
            local compositeKey = makeCompositeKey(item.Category, item.Key)
            local now          = os.clock()
            if now - (autoBuyCooldowns[compositeKey] or 0) >= 1 then
                autoBuyCooldowns[compositeKey] = now
                task.spawn(function() buyShopItem(item, false) end)
            end
        end
    end
end
-- WIND UI WINDOW
local Window = WindUI:CreateWindow({
    Title          = "Karinderya Toolkit",
    Icon           = "utensils",
    Author         = "By KnorkzykiiPH",
    Folder         = "Karinderya",
    Size           = UDim2.fromOffset(580, 460),
    MinSize        = Vector2.new(560, 350),
    MaxSize        = Vector2.new(850, 560),
    ToggleKey      = Enum.KeyCode.LeftShift,
    Transparent    = true,
    Theme          = "Dark",
    Resizable      = true,
    SideBarWidth   = 200,
    HideSearchBar  = true,
    ScrollBarEnabled = true,
})

Window:EditOpenButton({
    Title          = "Open Karinderya",
    Icon           = "utensils",
    CornerRadius   = UDim.new(0, 20),
    StrokeThickness = 1.4,
    OnlyMobile     = false,
    Enabled        = true,
    Draggable      = true,
})

Window:Tag({ Title = "FREEMIUM", Icon = "badge-check",  Color = Color3.fromHex("#00E676"), Radius = 13 })
Window:Tag({ Title = "v1.3.4",   Icon = "git-branch",   Color = Color3.fromHex("#7C4DFF"), Radius = 13 })
-- TABS
local HomeTab        = Window:Tab({ Title = "Home",        Icon = "house" })
local MainTab        = Window:Tab({ Title = "Main",        Icon = "utensils" })
local ShopTab        = Window:Tab({ Title = "Shop",        Icon = "shopping-cart" })
local IngredientsTab = Window:Tab({ Title = "Ingredients", Icon = "apple" })
local PlayerTab      = Window:Tab({ Title = "Player",      Icon = "user" })
local SettingsTab    = Window:Tab({ Title = "Settings",    Icon = "settings" })
local ModsTab        = Window:Tab({ Title = "Mods",        Icon = "shield" })
local ConfigTab      = Window:Tab({ Title = "Config",      Icon = "save" })
-- HOME TAB
HomeTab:Paragraph({ Title = "Thank you for choosing to use my script!", Desc = "" })
HomeTab:Paragraph({ Title = "Development",   Desc = "5 days of development, testing, and improvements." })
HomeTab:Paragraph({ Title = "Add & Follow Me On", Desc = "Roblox: KnorkzykiiPH & Tiktok: _jsephmols" })
HomeTab:Paragraph({ Title = "Creator",       Desc = "_jsephmols" })

local discordLink = "https://discord.gg/2PeDVr6pt"
HomeTab:Button({
    Title = "Join Discord",
    Desc  = "Copy the Discord invite link",
    Callback = function()
        if pcall(function()
            if setclipboard then setclipboard(discordLink); return end
            if toclipboard   then toclipboard(discordLink);  return end
            error("Clipboard function unavailable")
        end) then
            WindUI:Notify({ Title = "Discord Link Copied", Content = "Discord invite link copied to clipboard.", Duration = 3 })
        else
            WindUI:Notify({ Title = "Copy Failed", Content = "Your executor does not support clipboard.", Duration = 4 })
        end
    end,
})

HomeTab:Paragraph({ Title = "Features",
    Desc = "Auto Serve Food & Auto Assign Customers | Auto Collect Trash | Auto Serve Drinks (Requires Chiller) | Auto Wash Dishes | Auto Claim Codes | Auto Unlock Menu | Auto Buy Ingredients | Auto Unlock Tables | AND MORE" })
HomeTab:Paragraph({ Title = "Player Features", Desc = "WalkSpeed | Infinite Jump | NoClip | Anti AFK | Teleports" })
HomeTab:Paragraph({ Title = "Utilities",       Desc = "Config Save/Load | Delay Settings" })
-- MAIN TAB
MainTab:Section({ Title = "Auto Serve" })

MainTab:Toggle({
    Title    = "Auto Serve Food",
    Desc     = "Automatically serve prepared food",
    Value    = false,
    Flag     = "AutoServe",
    Callback = function(v) Config.autoServe = v end,
})
MainTab:Toggle({
    Title    = "Auto Assign Customers",
    Desc     = "Automatically assign customers to tables",
    Value    = false,
    Flag     = "AutoOrder",
    Callback = function(v) Config.autoOrder = v end,
})
MainTab:Toggle({
    Title    = "Auto Serve Drinks",
    Desc     = "Automatically fulfill drink orders (Requires Chiller)",
    Value    = false,
    Flag     = "AutoSoftdrinks",
    Callback = function(v) Config.autoSoftdrinks = v end,
})
MainTab:Toggle({
    Title    = "Auto Reject Selected Rarities",
    Desc     = "Reject NPCs based on their rarity",
    Value    = false,
    Flag     = "AutoRejectNPC",
    Callback = function(v) Config.autoRejectNPC = v end,
})
MainTab:Dropdown({
    Title    = "Reject Rarities",
    Desc     = "Select which NPC rarities should be rejected",
    Values   = npcRarityList,
    Value    = {},
    Multi    = true,
    AllowNone = true,
    Flag     = "RejectRarities",
    Callback = function(selected)
        Config.rejectNPCList = {}
        if type(selected) == "table" then
            for _, v in ipairs(selected) do Config.rejectNPCList[v] = true end
        end
    end,
})

MainTab:Section({ Title = "Auto Wash & Pan" })

MainTab:Toggle({
    Title    = "Auto Wash Dishes",
    Desc     = "Automatically washes dirty dishes.",
    Value    = false,
    Flag     = "AutoWash",
    Callback = function(v) Config.autoWash = v end,
})
MainTab:Toggle({
    Title    = "Auto Pan",
    Desc     = "Automatically hits NPCs who don't pay. Supports Pan, Golden Pan, and VIP Pan.",
    Value    = false,
    Flag     = "AutoPan",
    Callback = function(v) Config.autoPan = v end,
})

MainTab:Section({ Title = "Auto Trash" })

MainTab:Toggle({
    Title    = "Auto TP & Instant CLEAN",
    Desc     = "Instantly TP to and clean spawned trash anywhere on the map.",
    Value    = false,
    Callback = function(v)
        Config.autoTP       = v
        trashInstantPickup  = v
    end,
})

MainTab:Section({ Title = "Other" })

MainTab:Button({
    Title = "Upgrade to Golden Pan",
    Icon  = "sparkles",
    Callback = function()
        pcall(function() UpgradeToGoldenPan:InvokeServer() end)
    end,
})
MainTab:Toggle({
    Title    = "Auto Claim Codes",
    Value    = false,
    Flag     = "AutoClaimCodes",
    Callback = function(v) Config.autoClaimCodes = v end,
})

MainTab:Section({ Title = "Furniture & Menu" })

MainTab:Toggle({
    Title    = "Auto Unlock Menu",
    Value    = false,
    Flag     = "AutoUnlockMenu",
    Callback = function(v) Config.autoUnlockMenu = v end,
})
MainTab:Button({
    Title = "Enable All Menus",
    Icon  = "book-open",
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
    end,
})
-- PLAYER TAB
PlayerTab:Section({ Title = "Movement" })

local walkSpeedSlider = PlayerTab:Slider({
    Title = "WalkSpeed",
    Value = { Min = 16, Max = 100, Default = 16 },
    Step  = 1,
    Flag  = "WalkSpeed",
    Callback = function(v)
        Config.walkSpeed = v
        local _, hum = getCharacter()
        if hum then hum.WalkSpeed = v end
    end,
})

PlayerTab:Button({
    Title = "Reset WalkSpeed",
    Icon  = "rotate-ccw",
    Callback = function()
        Config.walkSpeed = 16
        local _, hum = getCharacter()
        if hum then hum.WalkSpeed = 16 end
        pcall(function() if walkSpeedSlider.SetValue then walkSpeedSlider:SetValue(16) end end)
        pcall(function() WindUI:SetValue("WalkSpeed", 16) end)
        pcall(function() WindUI.Flags.WalkSpeed = 16 end)
    end,
})

PlayerTab:Toggle({
    Title    = "Infinite Jump",
    Value    = false,
    Flag     = "InfJump",
    Callback = function(v) Config.infJump = v end,
})
PlayerTab:Toggle({
    Title    = "NoClip",
    Value    = false,
    Flag     = "NoClip",
    Callback = function(v)
        Config.noclip = v
        setNoclip(v)
    end,
})
PlayerTab:Button({
    Title = "Anti AFK",
    Callback = function()
        local VirtualUser = game:GetService("VirtualUser")
        local env         = getgenv()
        if env.__AntiAFK_Connection then
            pcall(function() env.__AntiAFK_Connection:Disconnect() end)
            env.__AntiAFK_Connection = nil
        end
        env.__AntiAFK_Connection = LocalPlayer.Idled:Connect(function()
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new(0, 0))
            end)
        end)
        pcall(function()
            WindUI:Notify({ Title = "Anti AFK", Content = "Anti AFK is now running!", Duration = 4.5 })
        end)
    end,
})

PlayerTab:Section({ Title = "Teleports" })

PlayerTab:Button({
    Title = "Teleport to Counter",
    Callback = function()
        local plot = getPlot()
        if not plot then return end
        local counter = plot:FindFirstChild("Counter")
        if counter then
            local comp = counter:FindFirstChild("Comp", true)
            if comp then teleportTo(comp.CFrame * CFrame.new(0, 3, 0)) end
        end
    end,
})
PlayerTab:Button({
    Title = "Teleport to Kitchen",
    Callback = function()
        local plot = getPlot()
        if not plot then return end
        local kitchen = plot:FindFirstChild("KitchenPlot1")
        if kitchen then
            local first = kitchen:GetChildren()[1]
            if first then teleportTo(first:GetPivot() * CFrame.new(0, 3, 0)) end
        end
    end,
})
PlayerTab:Button({
    Title = "Teleport to Serve Area",
    Callback = function()
        local plot = getPlot()
        if not plot then return end
        local serve = plot:FindFirstChild("Serve")
        if serve then
            local first = serve:GetChildren()[1]
            if first then teleportTo(first:GetPivot() * CFrame.new(0, 3, 0)) end
        end
    end,
})
PlayerTab:Button({
    Title = "Teleport to NPC Spawn",
    Callback = function()
        local plot = getPlot()
        if not plot then return end
        local spawn = plot:FindFirstChild("NpcSpawn")
        if spawn then teleportTo(spawn:GetPivot() * CFrame.new(0, 3, 0)) end
    end,
})
PlayerTab:Button({
    Title = "Teleport to Grocery",
    Callback = function()
        local grocery = Workspace:FindFirstChild("Grocery")
        if grocery then
            local comp = grocery:FindFirstChild("Comp", true)
            if comp then teleportTo(comp.CFrame * CFrame.new(0, 3, 0)) end
        end
    end,
})
-- SETTINGS TAB
SettingsTab:Section({ Title = "Delay Settings" })

SettingsTab:Slider({
    Title = "Serve Delay",
    Value = { Min = 0.01, Max = 2, Default = Config.serveDelay },
    Step  = 0.01,
    Flag  = "ServeDelay",
    Callback = function(v) Config.serveDelay = v end,
})
SettingsTab:Slider({
    Title = "Order Delay",
    Value = { Min = 0.1, Max = 2, Default = Config.orderDelay },
    Step  = 0.1,
    Flag  = "OrderDelay",
    Callback = function(v) Config.orderDelay = v end,
})
SettingsTab:Slider({
    Title = "Wash Delay",
    Value = { Min = 0.1, Max = 2, Default = Config.washDelay },
    Step  = 0.1,
    Flag  = "WashDelay",
    Callback = function(v) Config.washDelay = v end,
})
-- MODS TAB
ModsTab:Section({ Title = "Anti Mod" })

ModsTab:Toggle({
    Title    = "Instantly leaves when staff or higher ups join",
    Desc     = "Working (BETA)",
    Value    = false,
    Callback = function(v)
        Config.antiMod = v
        if v then
            for _, player in ipairs(Players:GetPlayers()) do
                if isStaff(player) then
                    LocalPlayer:Kick("Staff detected")
                    return
                end
            end
        end
    end,
})
-- CONFIG TAB
ConfigTab:Section({ Title = "Configuration" })

local ConfigManager = Window.ConfigManager
local savedConfig   = ConfigManager and ConfigManager:CreateConfig("Karinderya")

ConfigTab:Button({
    Title = "Save Config",
    Icon  = "save",
    Callback = function()
        if savedConfig then savedConfig:Save() end
    end,
})
ConfigTab:Button({
    Title = "Load Config",
    Icon  = "folder-open",
    Callback = function()
        if savedConfig then savedConfig:Load() end
    end,
})
ConfigTab:Paragraph({ Title = "WindUI", Desc = "WindUI interface with saved element flags" })
-- INGREDIENTS TAB
IngredientsTab:Slider({
    Title = "Buy Threshold",
    Desc  = "Automatically buy when stock reaches this percentage or lower",
    Value = { Min = 5, Max = 30, Default = 5 },
    Step  = 1,
    Flag  = "AutoBuyThreshold",
    Callback = function(v) autoBuyThreshold = math.clamp(tonumber(v) or 5, 5, 30) end,
})
IngredientsTab:Toggle({
    Title    = "Auto Buy",
    Desc     = "Automatically buy ingredients when stock is at or below the threshold",
    Value    = false,
    Flag     = "AutoBuyIngredients",
    Callback = function(v) Config.autoBuyIngredients = v end,
})

IngredientsTab:Section({ Title = "Ingredients" })

for _, ingredKey in ipairs(sortedIngredients) do
    local key      = ingredKey
    local maxStock = getMaxStock(key)
    local section  = IngredientsTab:Section({ Title = tostring(key) })
    local paragraph = section:Paragraph({
        Title = "Stock",
        Desc  = string.format("0 / %d (0%%)", maxStock),
    })
    section:Button({
        Title    = "Buy " .. tostring(key),
        Icon     = "shopping-cart",
        Callback = function() buyIngredientAmount(key, 1) end,
    })
    section:Button({
        Title    = "Buy Max",
        Icon     = "shopping-cart",
        Callback = function() buyIngredientMax(key) end,
    })
    ingredientUIRefs[key] = paragraph
end

updateAllIngredientLabels()

task.spawn(function()
    while true do task.wait(30); updateAllIngredientLabels() end
end)
-- SHOP TAB
refreshShopItems()

ShopTab:Section({ Title = "Auto Buy" })

ShopTab:Toggle({
    Title    = "Auto Buy Table",
    Desc     = "Automatically buy selected tables",
    Value    = false,
    Callback = function(v) autoBuyTables = v end,
})
ShopTab:Dropdown({
    Title    = "Select Tables",
    Desc     = "Select multiple tables",
    Values   = getItemNamesByCategory("Tables"),
    Value    = {},
    Multi    = true,
    AllowNone = true,
    Callback = function(v) selectedTables = type(v) == "table" and v or {} end,
})
ShopTab:Toggle({
    Title    = "Auto Buy Chair",
    Desc     = "Automatically buy selected chairs",
    Value    = false,
    Callback = function(v) autoBuyChairs = v end,
})
ShopTab:Dropdown({
    Title    = "Select Chairs",
    Desc     = "Select multiple chairs",
    Values   = getItemNamesByCategory("Chairs"),
    Value    = {},
    Multi    = true,
    AllowNone = true,
    Callback = function(v) selectedChairs = type(v) == "table" and v or {} end,
})
ShopTab:Toggle({
    Title    = "Auto Buy Material",
    Desc     = "Automatically buy selected materials",
    Value    = false,
    Callback = function(v) autoBuyMaterials = v end,
})
ShopTab:Dropdown({
    Title    = "Select Materials",
    Desc     = "Select multiple materials",
    Values   = getItemNamesByCategory("Materials"),
    Value    = {},
    Multi    = true,
    AllowNone = true,
    Callback = function(v) selectedMaterials = type(v) == "table" and v or {} end,
})
ShopTab:Toggle({
    Title    = "Auto Buy Paint",
    Desc     = "Automatically buy selected paints",
    Value    = false,
    Callback = function(v) autoBuyPaints = v end,
})
ShopTab:Dropdown({
    Title    = "Select Paints",
    Desc     = "Select multiple paints",
    Values   = getItemNamesByCategory("Paints"),
    Value    = {},
    Multi    = true,
    AllowNone = true,
    Callback = function(v) selectedPaints = type(v) == "table" and v or {} end,
})
ShopTab:Toggle({
    Title    = "Auto Buy Tile",
    Desc     = "Automatically buy selected tiles",
    Value    = false,
    Callback = function(v) autoBuyTiles = v end,
})
ShopTab:Dropdown({
    Title    = "Select Tiles",
    Desc     = "Select multiple tiles",
    Values   = getItemNamesByCategory("Tiles"),
    Value    = {},
    Multi    = true,
    AllowNone = true,
    Callback = function(v) selectedTiles = type(v) == "table" and v or {} end,
})
ShopTab:Toggle({
    Title    = "Auto Buy Stove",
    Desc     = "Automatically buy selected stoves",
    Value    = false,
    Callback = function(v) autoBuyStoves = v end,
})
ShopTab:Dropdown({
    Title    = "Select Stoves",
    Desc     = "Select multiple stoves",
    Values   = getItemNamesByCategory("Stoves"),
    Value    = {},
    Multi    = true,
    AllowNone = true,
    Callback = function(v) selectedStoves = type(v) == "table" and v or {} end,
})

-- shop item listings per category
local shopSections = {
    { Name = "Table",    Category = "Tables"    },
    { Name = "Chair",    Category = "Chairs"    },
    { Name = "Material", Category = "Materials" },
    { Name = "Paint",    Category = "Paints"    },
    { Name = "Tile",     Category = "Tiles"     },
    { Name = "Stove",    Category = "Stoves"    },
}

for _, group in ipairs(shopSections) do
    ShopTab:Section({ Title = group.Name })

    local sortedItems = {}
    for id, item in pairs(shopItems) do
        if item.Category == group.Category then
            table.insert(sortedItems, { Id = id, Item = item })
        end
    end
    table.sort(sortedItems, function(a, b)
        return getItemDisplayName(a.Item) < getItemDisplayName(b.Item)
    end)

    for _, entry in ipairs(sortedItems) do
        local item        = entry.Item
        local displayName = getItemDisplayName(item)
        local price       = getItemPrice(item)
        local stock       = tonumber(item.Stock) or 0

        local itemSection = ShopTab:Section({ Title = displayName })

        local priceDesc = "Price: $" .. tostring(price)
        if item.Config and item.Config.Description then
            priceDesc = priceDesc .. "\n" .. tostring(item.Config.Description)
        end
        itemSection:Paragraph({ Title = displayName, Desc = priceDesc })

        local stockDesc = stock > 0 and ("Stock: " .. tostring(stock)) or "Stock: 0 | OUT OF STOCK"
        local stockPara = itemSection:Paragraph({ Title = "Stock", Desc = stockDesc })
        shopUIRefs[entry.Id] = stockPara

        local capturedItem = item
        itemSection:Button({
            Title    = "Buy",
            Icon     = "shopping-cart",
            Callback = function() buyShopItem(capturedItem, true) end,
        })
    end
end

refreshShopStockOnly()

ShopRestocked.OnClientEvent:Connect(function()
    task.wait(0.2)
    refreshShopItems()
    refreshShopStockOnly()
end)
-- RUNTIME LOOPS
-- auto serve food + softdrinks
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
                                if desc:IsA("ProximityPrompt") and desc.Enabled
                                and string.sub(desc.ActionText, 1, 5) == "Serve" then
                                    local parent = desc.Parent
                                    if parent and parent:IsA("BasePart") then
                                        local release = acquireMutex()
                                        teleportTo(parent.CFrame * CFrame.new(0, 3, 0))
                                        task.wait(0.15)
                                        fireproximityprompt(desc)
                                        release()
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
                            local parent  = desc.Parent
                            local isValid = parent and parent:IsA("BasePart")
                            if isValid then
                                local release = acquireMutex()
                                teleportTo(parent.CFrame * CFrame.new(0, 3, 0))
                                task.wait(0.15)
                                fireproximityprompt(desc)
                                release()
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

-- auto assign customers
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
                    if not counter then break end
                    local comp = counter:FindFirstChild("Comp", true)
                    if not comp then break end

                    for _, v in ipairs(comp:GetDescendants()) do
                        if not (v:IsA("ProximityPrompt") and v.Enabled) then continue end
                        local action = tostring(v.ActionText)
                        if string.find(action, "Take Order") or string.find(action, "Take") then
                            local parent = v.Parent
                            if not (parent and parent:IsA("BasePart")) then continue end
                            local release = acquireMutex()
                            teleportTo(parent.CFrame * CFrame.new(0, 3, 0))
                            task.wait(0.01)
                            pcall(function() fireproximityprompt(v) end)
                            release()
                            tookOrder = true
                        end
                        if tookOrder then break end
                    end
                    if not tookOrder then break end
                end

                if tookOrder then break end

                local npcId   = counterData.NpcId or counterData.TemplateName or ""
                local npcName = counterData.TemplateName or ""
                if npcId == "" or npcName == "" then break end

                local npcData  = NPCConfig.Types[npcName]
                local rarity   = npcData and npcData.Rarity or "Unknown"
                local shouldReject = Config.autoRejectNPC
                    and next(Config.rejectNPCList) ~= nil
                    and Config.rejectNPCList[rarity]

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

-- auto claim codes
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

-- auto wash dishes
task.spawn(function()
    while true do
        if Config.autoWash then
            local plot = getPlot()
            if plot then
                local sink = plot:FindFirstChild("Sink")

                -- pick up dirty dishes from tables
                local searchAreas = {}
                local diningPlot  = plot:FindFirstChild("DiningPlot1")
                local serveArea   = plot:FindFirstChild("Serve")
                if diningPlot then table.insert(searchAreas, diningPlot) end
                if serveArea  then table.insert(searchAreas, serveArea) end

                for _, area in ipairs(searchAreas) do
                    for _, desc in ipairs(area:GetDescendants()) do
                        if not (desc:IsA("ProximityPrompt") and desc.Enabled) then continue end

                        local actionText = desc.ActionText:lower()
                        local objectText = desc.ObjectText:lower()
                        local isDirty    = string.find(objectText, "dirty") or string.find(objectText, "dish")
                            or string.find(actionText, "wash") or string.find(actionText, "pick")

                        if isDirty then
                            local parent = desc.Parent
                            if parent and parent:IsA("BasePart") then
                                local release = acquireMutex()
                                teleportTo(parent.CFrame * CFrame.new(0, 3, 0))
                                task.wait(0.6)
                                pcall(function()
                                    if desc.Enabled then fireproximityprompt(desc) end
                                end)
                                release()
                                task.wait(0.3)

                                -- wait for tool to appear in hand
                                local gotTool = false
                                for _ = 1, 20 do
                                    local char = LocalPlayer.Character
                                    if char and char:FindFirstChildOfClass("Tool") then
                                        gotTool = true; break
                                    end
                                    task.wait(0.1)
                                end

                                -- put it in the sink
                                if gotTool and sink then
                                    task.wait(0.15)
                                    for _, v in ipairs(sink:GetDescendants()) do
                                        if not (v:IsA("ProximityPrompt") and v.Enabled) then continue end
                                        local act = v.ActionText:lower()
                                        if string.find(act, "put") or string.find(act, "place") or v.Name == "Put" then
                                            local r2 = acquireMutex()
                                            teleportTo(v.Parent.CFrame * CFrame.new(0, 3, 0))
                                            task.wait(0.2)
                                            pcall(function()
                                                if v.Enabled then fireproximityprompt(v) end
                                            end)
                                            r2()
                                            task.wait(0.5)
                                            break
                                        end
                                    end
                                end

                                -- unequip tool
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

                -- wash dirty dishes at the sink
                if sink then
                    for _ = 1, 20 do
                        local washPrompt = nil
                        for _, v in ipairs(sink:GetDescendants()) do
                            if not (v:IsA("ProximityPrompt") and v.Enabled) then continue end
                            local act = v.ActionText:lower()
                            local obj = v.ObjectText:lower()
                            if string.find(act, "wash") or string.find(act, "clean")
                            or string.find(act, "scrub")
                            or string.find(obj, "dish") or string.find(obj, "dirty") or string.find(obj, "plate") then
                                washPrompt = v; break
                            end
                        end

                        if not washPrompt then break end
                        local parent = washPrompt.Parent
                        if not parent or not parent:IsA("BasePart") then break end

                        local release = acquireMutex()
                        teleportTo(parent.CFrame * CFrame.new(0, 3, 0))
                        task.wait(0.6)

                        local t0        = os.clock()
                        local holdBegun = false
                        while true do
                            local stillValid = washPrompt and washPrompt.Parent and washPrompt.Enabled
                                and os.clock() - t0 < 6
                            if not stillValid then break end

                            if not holdBegun and pcall(function() washPrompt:InputHoldBegin() end) then
                                holdBegun = true
                            end
                            task.wait(0.1)

                            if holdBegun and (washPrompt.Parent and washPrompt.Enabled) then
                                pcall(function() washPrompt:InputHoldBegin() end)
                            else
                                holdBegun = false
                            end
                        end

                        pcall(function()
                            if washPrompt and washPrompt.Parent then washPrompt:InputHoldEnd() end
                        end)
                        release()
                        task.wait(0.5)
                    end
                end
            end
        end

        task.wait(Config.washDelay)
    end
end)

-- auto buy ingredients loop
task.spawn(function()
    while true do
        if Config.autoBuyIngredients then
            for _, key in ipairs(sortedIngredients) do
                if not ingredientBusy[key] then
                    local cur = getCurrentStock(key)
                    local max = getMaxStock(key)
                    if max > 0 and cur < max and cur / max * 100 <= autoBuyThreshold then
                        buyIngredientAmount(key, 1)
                        task.wait(0.75)
                    end
                end
            end
        end
        task.wait(0.5)
    end
end)

-- auto buy shop items loop
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

-- auto unlock menu loop
task.spawn(function()
    local menuRequirements = {
        { Name = "SILOG",       Requirement = 100,  UnlockedKey = "SILOG"       },
        { Name = "SILOG 2",     Requirement = 400,  UnlockedKey = "SILOG 2"     },
        { Name = "LUTONG BAHAY",Requirement = 670,  UnlockedKey = "LUTONG BAHAY"},
        { Name = "Pasta Meal",  Requirement = 1994, UnlockedKey = "Pasta Meal"  },
    }

    while true do
        if Config.autoUnlockMenu then
            local ok, data = pcall(function() return GetMenuData:InvokeServer() end)
            if ok and data then
                local totalServed = tonumber(data.TotalServed) or 0
                local unlocked    = data.UnlockedMenus or {}

                for _, menu in ipairs(menuRequirements) do
                    local canUnlock = totalServed >= menu.Requirement and unlocked[menu.UnlockedKey] ~= true
                    if canUnlock then
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
-- CHARACTER / INPUT CONNECTIONS
LocalPlayer.CharacterAdded:Connect(function(character)
    local hum = character:WaitForChild("Humanoid", 10)
    if hum then hum.WalkSpeed = Config.walkSpeed end
end)

local _, currentHumanoid = getCharacter()
if currentHumanoid then currentHumanoid.WalkSpeed = Config.walkSpeed end

UserInputService.JumpRequest:Connect(function()
    if Config.infJump then
        local _, hum = getCharacter()
        if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end
end)
-- STARTUP NOTIFICATION
task.defer(function()
    task.wait(0.5)
    pcall(function()
        WindUI:Notify({
            Title    = "Script Loaded",
            Content  = "Thank you for choosing to use my script",
            Duration = 8,
        })
    end)
end)
