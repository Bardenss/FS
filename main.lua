local webhook = Window:Tab({
    Title = "Webhook",
    Icon = "send",
    Locked = false,
})

-- Variabel lokal untuk menyimpan data
local WEB_SERVER_URL = "https://bantaigunung.my.id/webhookfish.php" -- URL ke script PHP Anda
local API_KEY = "GN-88-99-JJ" -- API Key yang sama dengan di PHP
local isWebhookEnabled = false
local SelectedRarityCategories = {}
local SelectedWebhookItemNames = {} -- Variabel baru untuk filter nama

-- Kita butuh daftar nama item (Copy fungsi helper ini ke dalam tab webhook atau taruh di global scope)
local function getWebhookItemOptions()
    local itemNames = {}
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local itemsContainer = ReplicatedStorage:FindFirstChild("Items")
    if itemsContainer then
        for _, itemObject in ipairs(itemsContainer:GetChildren()) do
            local itemName = itemObject.Name
            if type(itemName) == "string" and #itemName >= 3 and itemName:sub(1, 3) ~= "!!!" then
                table.insert(itemNames, itemName)
            end
        end
    end
    table.sort(itemNames)
    return itemNames
end

local RarityList = {"Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret", "Trophy", "Collectible", "DEV"}

local REObtainedNewFishNotification = GetRemote(RPath, "RE/ObtainedNewFishNotification")
local HttpService = game:GetService("HttpService")
local WebhookStatusParagraph -- Forward declaration

-- ============================================================
-- 🖼️ SISTEM CACHE GAMBAR (BARU)
-- ============================================================
local ImageURLCache = {} -- Table untuk menyimpan Link Gambar (ID -> URL)

-- FUNGSI HELPER: Format Angka (Updated: Full Digit dengan Titik)
local function FormatNumber(n)
    n = math.floor(n) -- Bulatkan ke bawah biar ga ada desimal aneh
    -- Logic: Balik string -> Tambah titik tiap 3 digit -> Balik lagi
    local formatted = tostring(n):reverse():gsub("%d%d%d", "%1."):reverse()
    -- Hapus titik di paling depan jika ada (clean up)
    return formatted:gsub("^%.", "")
end

local function UpdateWebhookStatus(title, content, icon)
    if WebhookStatusParagraph then
        WebhookStatusParagraph:SetTitle(title)
        WebhookStatusParagraph:SetDesc(content)
    end
end

-- FUNGSI GET IMAGE DENGAN CACHE
local function GetRobloxAssetImage(assetId)
    if not assetId or assetId == 0 then return nil end
    
    -- 1. Cek Cache dulu!
    if ImageURLCache[assetId] then
        return ImageURLCache[assetId]
    end
    
    -- 2. Jika tidak ada di cache, baru panggil API
    local url = string.format("https://thumbnails.roblox.com/v1/assets?assetIds=%d&size=420x420&format=Png&isCircular=false", assetId)
    local success, response = pcall(game.HttpGet, game, url)
    
    if success then
        local ok, data = pcall(HttpService.JSONDecode, HttpService, response)
        if ok and data and data.data and data.data[1] and data.data[1].imageUrl then
            local finalUrl = data.data[1].imageUrl
            
            -- 3. Simpan ke Cache agar request berikutnya instan
            ImageURLCache[assetId] = finalUrl
            return finalUrl
        end
    end
    return nil
end

-- FUNGSI UNTUK MENGIRIM KE SERVER WEB (BUKAN DISCORD LANGSUNG)
local function sendToWebServer(embed_data, webhook_type)
    local payload = {
        api_key = API_KEY,
        embed = embed_data,
        webhook_type = webhook_type -- Tambahkan tipe webhook ke payload
    }
    
    local json_data = HttpService:JSONEncode(payload)
    
    if typeof(request) == "function" then
        local success, response = pcall(function()
            return request({
                Url = WEB_SERVER_URL,
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = json_data
            })
        end)
        
        if success then
            local ok, result = pcall(HttpService.JSONDecode, HttpService, response.Body)
            if ok and result and result.status == "success" then
                 return true, "Sent to server"
            elseif ok and result and result.status == "error" then
                return false, "Server Error: " .. (result.message or "Unknown")
            else
                return false, "Server responded with invalid JSON or unexpected format"
            end
        elseif response and response.StatusCode then
            return false, "Server Error: " .. response.StatusCode
        elseif not success then
            return false, "Error: " .. tostring(response)
        end
    end
    return false, "No Request Func"
end

local function getRarityColor(rarity)
    local r = rarity:upper()
    if r == "SECRET" then return 0xFFD700 end
    if r == "MYTHIC" then return 0x9400D3 end
    if r == "LEGENDARY" then return 0xFF4500 end
    if r == "EPIC" then return 0x8A2BE2 end
    if r == "RARE" then return 0x0000FF end
    if r == "UNCOMMON" then return 0x00FF00 end
    return 0x00BFFF
end

local function shouldNotify(fishRarityUpper, fishMetadata, fishName)
    -- Cek Filter Rarity
    if #SelectedRarityCategories > 0 and table.find(SelectedRarityCategories, fishRarityUpper) then
        return true
    end

    -- Cek Filter Nama (Fitur Baru)
    if #SelectedWebhookItemNames > 0 and table.find(SelectedWebhookItemNames, fishName) then
        return true
    end

    -- Cek Mutasi
    if _G.NotifyOnMutation and (fishMetadata.Shiny or fishMetadata.VariantId) then
             return true
    end
    
    return false
end

-- FUNGSI UNTUK MENGIRIM PESAN IKAN AKTUAL (FIXED PATH: {"Coins"})
local function onFishObtained(itemId, metadata, fullData)
    local success, results = pcall(function()
        local dummyItem = {Id = itemId, Metadata = metadata}
        local fishName, fishRarity = GetFishNameAndRarity(dummyItem)
        local fishRarityUpper = fishRarity:upper()

        -- --- START: Ambil Data Embed Umum ---
        local fishWeight = string.format("%.2fkg", metadata.Weight or 0)
        local mutationString = GetItemMutationString(dummyItem)
        local mutationDisplay = mutationString ~= "" and mutationString or "N/A"
        local itemData = ItemUtility:GetItemData(itemId)
        
        -- Handling Image
        local assetId = nil
        if itemData and itemData.Data then
            local iconRaw = itemData.Data.Icon or itemData.Data.ImageId
            if iconRaw then
                assetId = tonumber(string.match(tostring(iconRaw), "%d+"))
            end
        end

        local imageUrl = assetId and GetRobloxAssetImage(assetId)
        if not imageUrl then
            imageUrl = "https://tr.rbxcdn.com/53eb9b170bea9855c45c9356fb33c070/420/420/Image/Png" 
        end
        
        local basePrice = itemData and itemData.SellPrice or 0
        local sellPrice = basePrice * (metadata.SellMultiplier or 1)
        local formattedSellPrice = string.format("%s$", FormatNumber(sellPrice))
        
        -- 1. GET TOTAL CAUGHT (Untuk Footer)
        local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
        local caughtStat = leaderstats and leaderstats:FindFirstChild("Caught")
        local caughtDisplay = caughtStat and FormatNumber(caughtStat.Value) or "N/A"

        -- 2. GET CURRENT COINS (FIXED LOGIC BASED ON DUMP)
        local currentCoins = 0
        local replion = GetPlayerDataReplion()
        
        if replion then
            -- Cara 1: Ambil Path Resmi dari Module (Paling Aman)
            local success_curr, CurrencyConfig = pcall(function()
                return require(game:GetService("ReplicatedStorage").Modules.CurrencyUtility.Currency)
            end)

            if success_curr and CurrencyConfig and CurrencyConfig["Coins"] then
                -- Path adalah table: { "Coins" }
                -- Replion library di game ini support passing table path langsung
                currentCoins = replion:Get(CurrencyConfig["Coins"].Path) or 0
            else
                -- Cara 2: Fallback Manual (Root "Coins", bukan "Currency/Coins")
                -- Kita coba unpack table manual atau string langsung
                currentCoins = replion:Get("Coins") or replion:Get({"Coins"}) or 0
            end
        else
            -- Fallback Terakhir: Leaderstats
            if leaderstats then
                local coinStat = leaderstats:FindFirstChild("Coins") or leaderstats:FindFirstChild("C$")
                currentCoins = coinStat and coinStat.Value or 0
            end
        end

        local formattedCoins = FormatNumber(currentCoins)
        -- --- END: Ambil Data Embed Umum ---

        
        -- ************************************************************
        -- 1. LOGIKA WEBHOOK PRIBADI (USER'S WEBHOOK) - KIRIM KE SERVER
        -- ************************************************************
        local isUserFilterMatch = shouldNotify(fishRarityUpper, metadata, fishName)

        if isWebhookEnabled and isUserFilterMatch then
            local title_private = string.format("<:TEXTURENOBG:1438662703722790992> BantaiXmarV | Webhook\n\n<a:ChipiChapa:1438661193857503304> New Fish Caught! (%s)", fishName)
            
            local embed = {
                title = title_private,
                description = string.format("Found by **%s**.", LocalPlayer.DisplayName or LocalPlayer.Name),
                color = getRarityColor(fishRarityUpper),
                fields = {
                    { name = "<a:ARROW:1438758883203223605> Fish Name", value = string.format("`%s`", fishName), inline = true },
                    { name = "<a:ARROW:1438758883203223605> Rarity", value = string.format("`%s`", fishRarityUpper), inline = true },
                    { name = "<a:ARROW:1438758883203223605> Weight", value = string.format("`%s`", fishWeight), inline = true },
                    
                    { name = "<a:ARROW:1438758883203223605> Mutation", value = string.format("`%s`", mutationDisplay), inline = true },
                    { name = "<a:coines:1438758976992051231> Sell Price", value = string.format("`%s`", formattedSellPrice), inline = true },
                    { name = "<a:coines:1438758976992051231> Current Coins", value = string.format("`%s`", formattedCoins), inline = true },
                },
                thumbnail = { url = imageUrl },
                footer = {
                    text = string.format("BantaiXmarV Webhook • Total Caught: %s • %s", caughtDisplay, os.date("%Y-%m-%d %H:%M:%S"))
                }
            }
            local success_send, message = sendToWebServer(embed, "private") -- Kirim dengan tipe 'private'
            
            if success_send then
                UpdateWebhookStatus("Webhook Aktif", "Terkirim ke server: " .. fishName, "check")
            else
                UpdateWebhookStatus("Webhook Gagal", "Error: " .. message, "x")
            end
        end

        -- ************************************************************
        -- 2. LOGIKA WEBHOOK GLOBAL (COMMUNITY WEBHOOK) - KIRIM KE SERVER
        -- ************************************************************
        local isGlobalTarget = table.find({"SECRET", "TROPHY", "COLLECTIBLE", "DEV"}, fishRarityUpper)

        if isGlobalTarget then 
            local playerName = LocalPlayer.DisplayName or LocalPlayer.Name
            local censoredPlayerName = CensorName(playerName)
            
            local title_global = string.format("<:TEXTURENOBG:1438662703722790992> BantaiXmarV | Global Tracker\n\n<a:globe:1438758633151266818> GLOBAL CATCH! %s", fishName)

            local globalEmbed = {
                title = title_global,
                description = string.format("Pemain **%s** baru saja menangkap ikan **%s**!", censoredPlayerName, fishRarityUpper),
                color = getRarityColor(fishRarityUpper),
                fields = {
                    { name = "<a:ARROW:1438758883203223605> Rarity", value = string.format("`%s`", fishRarityUpper), inline = true },
                    { name = "<a:ARROW:1438758883203223605> Weight", value = string.format("`%s`", fishWeight), inline = true },
                    { name = "<a:ARROW:1438758883203223605> Mutation", value = string.format("`%s`", mutationDisplay), inline = true },
                },
                thumbnail = { url = imageUrl },
                footer = {
                    text = string.format("BantaiXmarV Community| Player: %s | %s", censoredPlayerName, os.date("%Y-%m-%d %H:%M:%S"))
                }
            }
            
            -- Kirim ke server dengan tipe 'global'
            sendToWebServer(globalEmbed, "global")
        end
        
        return true
    end)
    
    if not success then
        warn("[BantaiXmarV Webhook] Error processing fish data:", results)
    end
end

if REObtainedNewFishNotification then
    REObtainedNewFishNotification.OnClientEvent:Connect(function(itemId, metadata, fullData)
        pcall(function() onFishObtained(itemId, metadata, fullData) end)
    end)
end

-- =================================================================
-- UI IMPLEMENTATION (LANJUTAN)
-- =================================================================
local webhooksec = webhook:Section({
    Title = "Webhook Setup",
    TextSize = 20,
    FontWeight = Enum.FontWeight.SemiBold,
})

-- Input field untuk webhook URL DIHAPUS karena URL sekarang ke server PHP

webhook:Divider()
    
local ToggleNotif = Reg("tweb",webhooksec:Toggle({
    Title = "Enable Fish Notifications",
    Desc = "Aktifkan/nonaktifkan pengiriman notifikasi ikan.",
    Value = false,
    Icon = "cloud-upload",
    Callback = function(state)
        isWebhookEnabled = state
        if state then
            WindUI:Notify({ Title = "Webhook ON!", Duration = 4, Icon = "check" })
            UpdateWebhookStatus("Status: Listening", "Menunggu tangkapan ikan...", "ear")
        else
            WindUI:Notify({ Title = "Webhook OFF!", Duration = 4, Icon = "x" })
            UpdateWebhookStatus("Webhook Status", "Aktifkan 'Enable Fish Notifications' untuk mulai mendengarkan tangkapan ikan.", "info")
        end
    end
}))

local dwebname = Reg("drweb", webhooksec:Dropdown({
    Title = "Filter by Specific Name",
    Desc = "Notifikasi khusus untuk nama ikan tertentu",
    Values = getWebhookItemOptions(),
    Value = SelectedWebhookItemNames,
    Multi = true,
    AllowNone = true,
    Callback = function(names)
        SelectedWebhookItemNames = names or {} 
    end
}))

local dwebrar = Reg("rarwebd", webhooksec:Dropdown({
    Title = "Rarity to Notify",
    Desc = "Hanya notifikasi ikan rarity yang dipilih.",
    Values = RarityList, -- Menggunakan list yang sudah distandarisasi
    Value = SelectedRarityCategories,
    Multi = true,
    AllowNone = true,
    Callback = function(categories)
        SelectedRarityCategories = {}
        for _, cat in ipairs(categories or {}) do
            table.insert(SelectedRarityCategories, cat:upper()) 
        end
    end
}))

WebhookStatusParagraph = webhooksec:Paragraph({
    Title = "Webhook Status",
    Content = "Aktifkan 'Enable Fish Notifications' untuk mulai mendengarkan tangkapan ikan.",
    Icon = "info",
})
    

local teswebbut = webhooksec:Button({
    Title = "Test Webhook (Pribadi)",
    Icon = "send",
    Desc = "Mengirim Webhook Test ke webhook pribadi.",
    Callback = function()
        local testEmbed = {
            title = "BantaiXmarV Webhook Test",
            description = "Success <a:ChipiChapa:1438661193857503304>",
            color = 0x00FF00,
            fields = {
                { name = "Name Player", value = LocalPlayer.DisplayName or LocalPlayer.Name, inline = true },
                { name = "Status", value = "Success", inline = true },
                { name = "Cache System", value = "Active ✅", inline = true }
            },
            footer = {
                text = "BantaiXmarV Webhook Test"
            }
        }
        local success, message = sendToWebServer(testEmbed, "private") -- Test webhook pribadi
        if success then
             WindUI:Notify({ Title = "Test Sukses!", Content = "Cek channel Discord Anda. " .. message, Duration = 4, Icon = "check" })
        else
             WindUI:Notify({ Title = "Test Gagal!", Content = "Cek console (Output) untuk error. " .. message, Duration = 5, Icon = "x" })
        end
    end
})

local testGlobalWebhookButton = webhooksec:Button({
    Title = "Test Webhook (Global)",
    Icon = "globe",
    Desc = "Mengirim Webhook Test ke webhook global.",
    Callback = function()
        local testEmbed = {
            title = "BantaiXmarV Global Webhook Test",
            description = "Success <a:globe:1438758633151266818>",
            color = 0x00FF00,
            fields = {
                { name = "Name Player", value = LocalPlayer.DisplayName or LocalPlayer.Name, inline = true },
                { name = "Status", value = "Success", inline = true },
                { name = "Cache System", value = "Active ✅", inline = true }
            },
            footer = {
                text = "BantaiXmarV Global Webhook Test"
            }
        }
        local success, message = sendToWebServer(testEmbed, "global") -- Test webhook global
        if success then
             WindUI:Notify({ Title = "Test Global Sukses!", Content = "Cek channel Discord global Anda. " .. message, Duration = 4, Icon = "check" })
        else
             WindUI:Notify({ Title = "Test Global Gagal!", Content = "Cek console (Output) untuk error. " .. message, Duration = 5, Icon = "x" })
        end
    end
})
end
