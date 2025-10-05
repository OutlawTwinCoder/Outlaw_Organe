local ESX = exports['es_extended']:getSharedObject()

local missions = {} -- [src] = { netId=..., coords=vector3, startedAt=os.time(), harvested=0, given={}, canSecond=false, lastDispatchAt=0 }
local heat = {}     -- [src] = { value=0, updatedAt=os.time() }
local invOpen = {}  -- [src] = true/false
local profiles = {} -- [src] = profile table persisted in DB

local defaultDelivered = {}
for name, _ in pairs(Config.ItemDetails) do
    defaultDelivered[name] = 0
end

local function now() return os.time() end

local function cloneDelivered()
    local copy = {}
    for k, v in pairs(defaultDelivered) do copy[k] = v end
    return copy
end

local function getIdentifier(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return nil end
    return xPlayer.getIdentifier()
end

local function getReputationTier(points)
    local tiers = (Config.Reputation and Config.Reputation.Tiers) or {}
    if #tiers == 0 then return 1, { threshold = 0, label = 'Novice', bonus = 0.0 } end
    local idx, current = 1, tiers[1]
    for i, tier in ipairs(tiers) do
        if points >= (tier.threshold or 0) then
            idx = i
            current = tier
        else
            break
        end
    end
    local nextTier = tiers[idx + 1]
    return idx, current, nextTier
end

local function getPriceMultiplier(points)
    local _, tier = getReputationTier(points or 0)
    return 1.0 + (tier.bonus or 0.0)
end

local function ensureProfile(src)
    if not src then return nil end
    local cached = profiles[src]
    if cached then return cached end

    local identifier = getIdentifier(src)
    if not identifier then return nil end

    local row = MySQL.single.await('SELECT * FROM outlaw_organ_profiles WHERE identifier = ?', {identifier})
    if not row then
        local delivered = json.encode(cloneDelivered())
        MySQL.insert.await('INSERT INTO outlaw_organ_profiles (identifier, reputation, contracts, total_quality, delivered, upgrades) VALUES (?, ?, ?, ?, ?, ?)', {
            identifier, 0, 0, 0, delivered, json.encode({})
        })
        row = {
            reputation = 0,
            contracts = 0,
            total_quality = 0,
            delivered = delivered,
            upgrades = json.encode({})
        }
    end

    local delivered = json.decode(row.delivered or '{}') or {}
    for name, defaultVal in pairs(defaultDelivered) do
        if delivered[name] == nil then delivered[name] = defaultVal end
    end

    local upgrades = json.decode(row.upgrades or '{}') or {}
    if type(upgrades) ~= 'table' then upgrades = {} end

    cached = {
        identifier = identifier,
        reputation = row.reputation or 0,
        totalQuality = row.total_quality or 0,
        contracts = row.contracts or 0,
        delivered = delivered,
        upgrades = upgrades
    }
    profiles[src] = cached
    return cached
end

local function saveProfile(src)
    local profile = profiles[src]
    if not profile or not profile.identifier then return end
    MySQL.update.await('UPDATE outlaw_organ_profiles SET reputation = ?, contracts = ?, total_quality = ?, delivered = ?, upgrades = ? WHERE identifier = ?', {
        profile.reputation or 0,
        profile.contracts or 0,
        profile.totalQuality or 0,
        json.encode(profile.delivered or cloneDelivered()),
        json.encode(profile.upgrades or {}),
        profile.identifier
    })
end

local function getUpgradeBonuses(profile, scalpelType)
    if not profile or not scalpelType then return 0, 0 end
    local tiers = Config.Scalpel.Upgrades and Config.Scalpel.Upgrades[scalpelType]
    if not tiers or #tiers == 0 then return 0, 0 end
    local current = (profile.upgrades and profile.upgrades[scalpelType]) or 0
    local bonusQ, bonusTTL = 0, 0
    for i = 1, math.min(current, #tiers) do
        local data = tiers[i]
        bonusQ = bonusQ + (data.bonusQuality or 0)
        bonusTTL = bonusTTL + (data.bonusTTL or 0)
    end
    return bonusQ, bonusTTL
end

local function hasDeliveredRequirements(profile, req)
    if not req then return true end
    for item, count in pairs(req) do
        if (profile.delivered[item] or 0) < count then
            return false
        end
    end
    return true
end

local function buildUpgradeState(profile)
    local data = {}
    for kind, tiers in pairs(Config.Scalpel.Upgrades or {}) do
        local entry = { current = (profile and profile.upgrades and profile.upgrades[kind]) or 0, tiers = {} }
        for index, tier in ipairs(tiers) do
            entry.tiers[index] = {
                index = index,
                id = tier.id,
                label = tier.label,
                description = tier.description,
                reputation = tier.reputation or 0,
                organs = tier.organs or {},
                bonusQuality = tier.bonusQuality or 0,
                bonusTTL = tier.bonusTTL or 0
            }
        end
        data[kind] = entry
    end
    return data
end

lib.callback.register('outlaw_organ:getDealerData', function(src)
    local profile = ensureProfile(src)
    if not profile then return nil end
    local tierIndex, tierData, nextTier = getReputationTier(profile.reputation or 0)
    local delivered = cloneDelivered()
    for item, _ in pairs(delivered) do
        delivered[item] = profile.delivered[item] or 0
    end
    local nextData = nil
    if nextTier then
        nextData = {
            label = nextTier.label,
            threshold = nextTier.threshold or 0,
            remaining = math.max(0, (nextTier.threshold or 0) - (profile.reputation or 0))
        }
    end
    return {
        reputation = profile.reputation or 0,
        totalQuality = profile.totalQuality or 0,
        contracts = profile.contracts or 0,
        tier = tierIndex,
        tierLabel = tierData.label,
        multiplier = getPriceMultiplier(profile.reputation or 0),
        nextTier = nextData,
        delivered = delivered,
        upgrades = buildUpgradeState(profile),
        scalpelPrices = Config.Scalpel.Prices or {},
        itemDetails = Config.ItemDetails
    }
end)

lib.callback.register('outlaw_organ:upgradeScalpel', function(src, kind)
    local profile = ensureProfile(src)
    if not profile then return false, 'Profil introuvable' end
    local tiers = Config.Scalpel.Upgrades and Config.Scalpel.Upgrades[kind]
    if not tiers or #tiers == 0 then return false, 'Amélioration indisponible' end
    profile.upgrades = profile.upgrades or {}
    local current = profile.upgrades[kind] or 0
    local nextTier = tiers[current + 1]
    if not nextTier then return false, 'Déjà au niveau maximal' end
    if (profile.reputation or 0) < (nextTier.reputation or 0) then
        return false, 'Réputation insuffisante'
    end
    if not hasDeliveredRequirements(profile, nextTier.organs) then
        return false, 'Livraisons insuffisantes'
    end

    profile.upgrades[kind] = current + 1
    saveProfile(src)
    return true, nextTier.label
end)

local function updateHeat(src, delta)
    heat[src] = heat[src] or { value = 0, updatedAt = now() }
    local h = heat[src]
    local minutes = (now() - h.updatedAt) / 60
    local decay = (Config.Heat.DecayPerMinute or 5) * minutes
    h.value = math.max(0, (h.value or 0) - decay)
    if delta and delta ~= 0 then h.value = h.value + delta end
    h.updatedAt = now()
    return h.value
end

local function getPoliceTargets()
    local targets = {}
    for _, xPlayer in pairs(ESX.GetExtendedPlayers()) do
        local job = xPlayer.getJob() and xPlayer.getJob().name or 'unemployed'
        for _, j in ipairs(Config.PoliceJobs or {'police'}) do
            if job == j then table.insert(targets, xPlayer.source) break end
        end
    end
    return targets
end

local function policeDispatch(coords, reason)
    local list = getPoliceTargets()
    for _, src in ipairs(list) do
        TriggerClientEvent('outlaw_organ:policePing', src, coords, reason or 'Activité suspecte')
    end
end

local function sendWebhook(title, description, color)
    if not Config.DiscordWebhook or Config.DiscordWebhook == 'REPLACE_ME' then return end
    local embed = {{
        title = title, description = description, color = color or 15158332,
        footer = { text = 'Outlaw_OrganHarvest' },
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ')
    }}
    PerformHttpRequest(Config.DiscordWebhook, function() end, 'POST', json.encode({ embeds = embed }), {['Content-Type'] = 'application/json'})
end

local function cooldownRemaining(src)
    local m = missions[src]
    if not m or not m.startedAt then return 0 end
    local passed = now() - (m.startedAt or 0)
    local remain = Config.MissionCooldown - passed
    return remain > 0 and remain or 0
end

RegisterNetEvent('outlaw_organ:startMission', function()
    local src = source
    local remain = cooldownRemaining(src)
    if remain > 0 then
        return TriggerClientEvent('ox_lib:notify', src, {title='Organes', description=('Attends %ss avant une nouvelle mission.'):format(remain), type='error'})
    end
    local zone = Config.SpawnZones[math.random(#Config.SpawnZones)]
    missions[src] = { netId = nil, coords = zone, startedAt = now(), harvested = 0, given = {}, canSecond = false, lastDispatchAt = 0 }
    TriggerClientEvent('outlaw_organ:missionAssigned', src, zone)
    sendWebhook('Mission organes assignée', ('**Joueur:** %s\n**Zone:** (%.1f, %.1f, %.1f)'):format(GetPlayerName(src), zone.x, zone.y, zone.z), 3447003)
end)

RegisterNetEvent('outlaw_organ:registerTarget', function(netId, coords)
    local src = source
    missions[src] = missions[src] or { startedAt = now(), harvested = 0, given = {} }
    missions[src].netId = netId
    missions[src].coords = coords
end)

local function countItem(src, name) return exports.ox_inventory:Search(src, 'count', name) or 0 end
local function removeItem(src, name, count) return exports.ox_inventory:RemoveItem(src, name, count or 1) end
local function hasItem(src, name) return countItem(src, name) > 0 end

local function playerHasScalpel(src)
    if Config.Scalpel and Config.Scalpel.basic and hasItem(src, Config.Scalpel.basic) then return 'basic' end
    if Config.Scalpel and Config.Scalpel.pro and hasItem(src, Config.Scalpel.pro) then return 'pro' end
    return false
end

local function baseQualityFromCause(causeHash)
    local j = GetHashKey
    local Q = Config.QualityByKill
    if causeHash == j('WEAPON_KNIFE') or causeHash == j('WEAPON_SWITCHBLADE') or causeHash == j('WEAPON_DAGGER') then
        return Q.knife
    elseif causeHash == j('WEAPON_UNARMED') or causeHash == j('WEAPON_BAT') or causeHash == j('WEAPON_CROWBAR') then
        return Q.melee
    elseif causeHash == j('WEAPON_PISTOL') or causeHash == j('WEAPON_COMBATPISTOL') or causeHash == j('WEAPON_PISTOL_MK2') then
        return Q.pistol
    elseif causeHash == j('WEAPON_CARBINERIFLE') or causeHash == j('WEAPON_ASSAULTRIFLE') or causeHash == j('WEAPON_SPECIALCARBINE') then
        return Q.rifle
    elseif causeHash == j('WEAPON_PUMPSHOTGUN') or causeHash == j('WEAPON_SAWNOFFSHOTGUN') then
        return Q.shotgun
    elseif causeHash == j('WEAPON_GRENADE') or causeHash == j('WEAPON_STICKYBOMB') or causeHash == j('WEAPON_RPG') then
        return Q.explosion
    elseif causeHash == j('WEAPON_RUN_OVER_BY_CAR') or causeHash == j('WEAPON_RAMMED_BY_CAR') then
        return Q.vehicle
    end
    return Q.other
end

local function pickOrganName(exclude, profile)
    local pool, sum = {}, 0
    exclude = exclude or {}
    local tierIndex = 1
    if profile then tierIndex = select(1, getReputationTier(profile.reputation or 0)) end
    for k, v in pairs(Config.ItemDetails) do
        local limit = Config.ItemDetails[k].limit or 1
        local neededTier = Config.ItemDetails[k].repTier or 1
        if tierIndex >= neededTier and ((exclude[k] or 0) < limit) then
            local price = math.max(1, tonumber(v.price) or 1)
            local w = math.floor(1000 / price)
            if w < 1 then w = 1 end
            sum = sum + w
            table.insert(pool, {name=k, weight=w})
        end
    end
    if sum <= 0 then return 'organe' end
    local r, acc = math.random(1, sum), 0
    for _, it in ipairs(pool) do
        acc = acc + it.weight
        if r <= acc then return it.name end
    end
    return 'organe'
end

-- Compute remaining percentage (0-100) from per-item TTL metadata
local function computeDurability(meta, t)
    t = t or now()
    local born = tonumber(meta and meta.born or t) or t
    local ttl  = tonumber(meta and meta.ttl or Config.OrganDecaySeconds or 600) or 600
    local exp  = tonumber(meta and meta.expires or (born + ttl)) or (born + ttl)
    local remain = exp - t
    local ratio = remain > 0 and (remain / ttl) or 0
    return math.max(0, math.min(100, math.floor(ratio * 100)))
end

-- Refresh all organ items durability bars for a player
local function refreshOrganBarsForPlayer(src)
    if not src then return end
    for itemName, _ in pairs(Config.ItemDetails) do
        local slots = exports.ox_inventory:GetSlotsWithItem(src, itemName) or {}
        for _, slot in pairs(slots) do
            local dur = computeDurability(slot.metadata, now())
            exports.ox_inventory:SetDurability(src, slot.slot, dur)
        end
    end
end

-- Live sync while inventory is open
AddEventHandler('ox_inventory:openedInventory', function(playerId, inventoryId)
    invOpen[playerId] = true
    -- Immediate refresh
    refreshOrganBarsForPlayer(playerId)
    -- Periodic refresh while open
    CreateThread(function()
        while invOpen[playerId] do
            Wait(3000)
            refreshOrganBarsForPlayer(playerId)
        end
    end)
end)

AddEventHandler('ox_inventory:closedInventory', function(playerId, inventoryId)
    invOpen[playerId] = false
end)

RegisterNetEvent('outlaw_organ:harvest', function(netId, causeHash)
    local src = source
    local mission = missions[src]
    if not mission or not mission.netId or mission.netId ~= netId then
        return TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Aucune cible valide.', type='error'})
    end

    local ent = NetworkGetEntityFromNetworkId(netId)
    if not ent or ent == 0 or not DoesEntityExist(ent) then
        return TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='La cible est introuvable.', type='error'})
    end

    local pedCoords = GetEntityCoords(ent)
    local plyCoords = GetEntityCoords(GetPlayerPed(src))
    if #(pedCoords - plyCoords) > 5.0 then
        return TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Tu es trop loin de la cible.', type='error'})
    end

    local scalpelType = playerHasScalpel(src)
    if not scalpelType then
        return TriggerClientEvent('ox_lib:notify', src, {title='Organes', description=('Tu as besoin d’un %s.'):format(Config.Scalpel.basic), type='error'})
    end

    local profile = ensureProfile(src)

    if mission.harvested >= 1 and not mission.canSecond then
        return TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Plus rien à prélever sur ce corps.', type='error'})
    end

    if mission.harvested == 0 then
        local canSecond = false
        if scalpelType == 'pro' and math.random() < (Config.SecondHarvestChance or 0.15) then canSecond = true end
        mission.canSecond = canSecond
    end

    local bonusQuality, bonusTTL = getUpgradeBonuses(profile, scalpelType)

    local base = 80 + baseQualityFromCause(causeHash or 0)
    if scalpelType == 'pro' then base = base + (Config.Scalpel.proQualityBonus or 10) end
    base = base + bonusQuality
    base = math.max(20, math.min(100, base))

    local ttl = Config.OrganDecaySeconds or 600
    if hasItem(src, Config.CoolerItem) then ttl = ttl + (Config.CoolerBonusSeconds or 300) end
    if Config.IcepackItem and hasItem(src, Config.IcepackItem) then ttl = ttl + (Config.IcepackBonusSeconds or 120) end
    if Config.Scalpel.kit and hasItem(src, Config.Scalpel.kit) then
        ttl = ttl + (Config.Scalpel.kitExtraSeconds or 180)
        removeItem(src, Config.Scalpel.kit, 1)
    end
    ttl = ttl + bonusTTL

    mission.given = mission.given or {}
    local organ = pickOrganName(mission.given, profile)

    local born = now()
    local expires = born + ttl
    local metadata = { quality = base, born = born, ttl = ttl, expires = expires }

    -- Add item and set initial durability to 100%, then sync loop will take care
    exports.ox_inventory:AddItem(src, organ, 1, metadata, nil, function(success, response)
        if not success then
            return TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Inventaire plein.', type='error'})
        end
        if response and response.slot then
            -- Set initial durability according to TTL (should be 100 just after creation)
            local dur = computeDurability(metadata, now())
            exports.ox_inventory:SetDurability(src, response.slot, dur)
        end

        mission.harvested = (mission.harvested or 0) + 1
        mission.given[organ] = (mission.given[organ] or 0) + 1

        if Config.Heat and Config.Heat.Enable then
            local val = updateHeat(src, Config.Heat.AddOnHarvest or 20)
            if val >= (Config.Heat.DispatchThreshold or 50) then
                if (mission.lastDispatchAt or 0) + (Config.Heat.DispatchCooldownSeconds or 90) <= now() then
                    mission.lastDispatchAt = now()
                    policeDispatch(pedCoords, 'Activité suspecte / prélèvement d’organes')
                end
            end
        end

        if Config.Risk and Config.Risk.InfectionChanceNoGloves and (not hasItem(src, Config.Risk.GlovesItem)) then
            if math.random() < Config.Risk.InfectionChanceNoGloves then
                TriggerClientEvent('outlaw_organ:applyInfection', src, Config.Risk.InfectionDuration or 600, Config.Risk.InfectionSprintMultiplier or 0.9)
            end
        end

        sendWebhook('Prélèvement', ('**Joueur:** %s\n**Item:** %s\n**Qualité:** %d%%\n**TTL:** %ss\n**Coords:** (%.1f, %.1f, %.1f)'):format(GetPlayerName(src), organ, metadata.quality, metadata.ttl, pedCoords.x, pedCoords.y, pedCoords.z), 5763719)

        local done = false
        if mission.harvested >= 1 and not mission.canSecond then
            done = true
        elseif mission.harvested >= 2 then
            done = true
        end

        if done then
            TriggerClientEvent('outlaw_organ:clearTarget', src)
            missions[src].netId = nil
            missions[src].startedAt = now()
            if profile then
                profile.contracts = (profile.contracts or 0) + 1
                saveProfile(src)
            end
        end

        TriggerClientEvent('ox_lib:notify', src, {title='Organes', description=('Récolte: %s (%d%%)'):format(organ, base), type='success'})
    end)
end)

RegisterNetEvent('outlaw_organ:sellOrgans', function()
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    local profile = ensureProfile(src)
    local oldTier = profile and select(1, getReputationTier(profile.reputation or 0)) or 1
    local multiplier = profile and getPriceMultiplier(profile.reputation or 0) or 1.0

    local total = 0
    local t = now()
    local qualityEarned = 0

    for name, data in pairs(Config.ItemDetails) do
        local slots = exports.ox_inventory:Search(src, 'slots', name) or {}
        for _, slot in pairs(slots) do
            local price = tonumber(data.price) or 0
            local q = 100
            if slot.metadata then
                local born = tonumber(slot.metadata.born or t)
                local ttl  = tonumber(slot.metadata.ttl or Config.OrganDecaySeconds or 600)
                local quality0 = tonumber(slot.metadata.quality or 100)
                local exp = tonumber(slot.metadata.expires or (born + ttl))
                local remain = exp - t
                if remain <= 0 then
                    q = 10
                else
                    local ratio = remain / ttl
                    q = math.max(10, math.min(100, math.floor(quality0 * ratio)))
                end
            end
            local final = math.floor(price * multiplier * (q / 100))
            total = total + final
            qualityEarned = qualityEarned + q
            if profile then
                profile.delivered[name] = (profile.delivered[name] or 0) + 1
            end
            exports.ox_inventory:RemoveItem(src, name, 1, nil, slot.slot)
        end
    end

    if total <= 0 then
        return TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Tu n’as rien à vendre.', type='error'})
    end

    if profile then
        local qualityPoints = math.floor(qualityEarned * (Config.Reputation.PointsPerQuality or 1.0))
        profile.totalQuality = (profile.totalQuality or 0) + qualityEarned
        profile.reputation = (profile.reputation or 0) + qualityPoints
        saveProfile(src)
        local newTier = select(1, getReputationTier(profile.reputation or 0))
        if newTier > oldTier then
            local _, tierData = getReputationTier(profile.reputation or 0)
            TriggerClientEvent('ox_lib:notify', src, {title='Réputation', description=('Nouveau rang: %s (+%d%% prix)'):format(tierData.label, math.floor((tierData.bonus or 0) * 100)), type='success'})
        end
    end

    if Config.UseBlackMoney then xPlayer.addAccountMoney('black_money', total) else xPlayer.addMoney(total) end
    TriggerClientEvent('ox_lib:notify', src, {title='Organes', description=('Vente: $%s'):format(total), type='success'})
    sendWebhook('Vente d’organes', ('**Joueur:** %s\n**Montant:** $%s'):format(GetPlayerName(src), total), 15844367)
end)

RegisterNetEvent('outlaw_organ:buyTool', function(kind)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    local item, price = nil, 0
    if kind == 'basic' then item = Config.Scalpel.basic; price = (Config.Scalpel.Prices and Config.Scalpel.Prices.basic) or 250
    elseif kind == 'pro' then item = Config.Scalpel.pro; price = (Config.Scalpel.Prices and Config.Scalpel.Prices.pro) or 1500
    elseif kind == 'kit' then item = Config.Scalpel.kit; price = (Config.Scalpel.Prices and Config.Scalpel.Prices.kit) or 400 end

    if not item or item == '' then
        return TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Indisponible.', type='error'})
    end

    if xPlayer.getMoney() < price then
        return TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Pas assez d’argent.', type='error'})
    end

    local ok = exports.ox_inventory:AddItem(src, item, 1)
    if not ok then
        return TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Inventaire plein.', type='error'})
    end

    xPlayer.removeMoney(price)
    TriggerClientEvent('ox_lib:notify', src, {title='Organes', description=('Achat: %s'):format(item), type='success'})
end)

RegisterNetEvent('outlaw_organ:witnessDispatch', function(coords)
    if not coords then return end
    policeDispatch(coords, 'Appel citoyen: activité suspecte / organes')
    sendWebhook('Témoin', ('Activité suspecte repérée en (%.1f, %.1f, %.1f)'):format(coords.x, coords.y, coords.z), 15158332)
end)

RegisterNetEvent('esx:playerLoaded', function(playerId, xPlayer)
    ensureProfile(playerId)
end)

AddEventHandler('playerDropped', function()
    local src = source
    if profiles[src] then saveProfile(src) end
    missions[src] = nil
    heat[src] = nil
    invOpen[src] = nil
    profiles[src] = nil
end)

RegisterCommand('organreset', function(src, args, raw)
    if src == 0 then return end
    missions[src] = nil
    TriggerClientEvent('outlaw_organ:clearTarget', src)
    TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Reset effectué.', type='success'})
end, false)
