local ESX = exports['es_extended']:getSharedObject()

local missions = {} -- [src] = { netId=..., coords=vector3, startedAt=os.time(), harvested=0, given={}, canSecond=false, lastDispatchAt=0 }
local heat = {}     -- [src] = { value=0, updatedAt=os.time() }
local invOpen = {}  -- [src] = true/false
local playerIdentifiers = {} -- [src] = identifier
local statsCache = {} -- [identifier] = { reputation=0, contracts=0, deliveries={}, unlocks={} }

local function deepcopy(obj)
    if type(obj) ~= 'table' then return obj end
    local res = {}
    for k, v in pairs(obj) do res[k] = deepcopy(v) end
    return res
end

local scalpelTiersOrdered, scalpelTierIndex = {}, {}
do
    for name, data in pairs(Config.ScalpelTiers or {}) do
        if data.item then
            local entry = {
                name = name,
                item = data.item,
                label = data.label or name,
                price = data.price or 0,
                reputation = data.reputation or 0,
                requires = deepcopy(data.requires or {}),
                qualityBonus = data.qualityBonus or 0,
                secondHarvestChance = data.secondHarvestChance or 0,
                description = data.description or ''
            }
            table.insert(scalpelTiersOrdered, entry)
            scalpelTierIndex[name] = entry
        end
    end
    table.sort(scalpelTiersOrdered, function(a, b)
        if (a.qualityBonus or 0) == (b.qualityBonus or 0) then
            return (a.price or 0) < (b.price or 0)
        end
        return (a.qualityBonus or 0) < (b.qualityBonus or 0)
    end)
end

local function now() return os.time() end

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

local function getIdentifier(src)
    if playerIdentifiers[src] then return playerIdentifiers[src] end
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return nil end
    local identifier = xPlayer.getIdentifier()
    if identifier then playerIdentifiers[src] = identifier end
    return identifier
end

local function ensureStats(src)
    local identifier = getIdentifier(src)
    if not identifier then return nil end
    if statsCache[identifier] then return statsCache[identifier], identifier end

    local row = MySQL.single.await('SELECT reputation, contracts, deliveries, unlocks FROM outlaw_organ_stats WHERE identifier = ?', { identifier })
    local stats
    if row then
        stats = {
            reputation = tonumber(row.reputation) or 0,
            contracts = tonumber(row.contracts) or 0,
            deliveries = (row.deliveries and row.deliveries ~= '' and json.decode(row.deliveries)) or {},
            unlocks = (row.unlocks and row.unlocks ~= '' and json.decode(row.unlocks)) or {}
        }
    else
        stats = { reputation = 0, contracts = 0, deliveries = {}, unlocks = {} }
        MySQL.insert.await('INSERT INTO outlaw_organ_stats (identifier, reputation, contracts, deliveries, unlocks) VALUES (?, ?, ?, ?, ?)', {
            identifier, 0, 0, json.encode(stats.deliveries), json.encode(stats.unlocks)
        })
    end

    stats.deliveries = stats.deliveries or {}
    stats.unlocks = stats.unlocks or {}
    stats.unlocks.basic = true
    statsCache[identifier] = stats
    return stats, identifier
end

local function saveStats(identifier)
    if not identifier then return end
    local stats = statsCache[identifier]
    if not stats then return end
    MySQL.update.await('UPDATE outlaw_organ_stats SET reputation = ?, contracts = ?, deliveries = ?, unlocks = ? WHERE identifier = ?', {
        math.floor(stats.reputation or 0),
        math.floor(stats.contracts or 0),
        json.encode(stats.deliveries or {}),
        json.encode(stats.unlocks or {}),
        identifier
    })
end

local function getPriceMultiplier(rep)
    local cfg = Config.Reputation or {}
    local perPoint = cfg.PriceBonusPerPoint or 0
    local maxBonus = cfg.MaxPriceBonus or 0.5
    local bonus = math.max(0.0, math.min(maxBonus, (rep or 0) * perPoint))
    return 1.0 + bonus, bonus
end

local function addReputation(identifier, amount)
    if not identifier or not amount or amount == 0 then return end
    local stats = statsCache[identifier]
    if not stats then return end
    local cfg = Config.Reputation or {}
    local maxRep = cfg.Max or 500
    local rep = (stats.reputation or 0) + amount
    if rep < 0 then rep = 0 end
    if maxRep and rep > maxRep then rep = maxRep end
    stats.reputation = math.floor(rep)
end

local function addContract(identifier)
    if not identifier then return end
    local stats = statsCache[identifier]
    if not stats then return end
    stats.contracts = math.floor((stats.contracts or 0) + 1)
    local cfg = Config.Reputation or {}
    if cfg.ContractBonus and cfg.ContractBonus > 0 then
        addReputation(identifier, cfg.ContractBonus)
    end
end

local function recordDelivery(identifier, item, amount)
    if not identifier then return end
    local stats = statsCache[identifier]
    if not stats then return end
    stats.deliveries = stats.deliveries or {}
    stats.deliveries[item] = math.floor((stats.deliveries[item] or 0) + (amount or 1))
end

local function repGainFromQuality(quality)
    local cfg = Config.Reputation or {}
    local minQuality = cfg.SaleMinQuality or 40
    if not quality or quality <= minQuality then return 0 end
    local weight = cfg.SaleQualityWeight or 0.05
    return math.max(0, math.floor((quality - minQuality) * weight))
end

local function deliveriesMeetRequirements(stats, requires)
    local missing = {}
    if not requires or not next(requires) then return true, missing end
    for item, needed in pairs(requires) do
        local have = (stats.deliveries or {})[item] or 0
        if have < needed then
            table.insert(missing, { item = item, have = have, need = needed })
        end
    end
    return #missing == 0, missing
end

local function formatMissingList(missing)
    if not missing or #missing == 0 then return '' end
    local parts = {}
    for _, info in ipairs(missing) do
        local cfg = Config.ItemDetails[info.item]
        local label = (cfg and (cfg.label or info.item)) or info.item
        table.insert(parts, ('%s (%d/%d)'):format(label, info.have, info.need))
    end
    return table.concat(parts, ', ')
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
    ensureStats(src)
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
    for i = #scalpelTiersOrdered, 1, -1 do
        local tier = scalpelTiersOrdered[i]
        if tier.item and hasItem(src, tier.item) then
            return tier
        end
    end
    return nil
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

local function rareLocked(item, reputation)
    local req = Config.Reputation and Config.Reputation.RareOrders and Config.Reputation.RareOrders[item]
    if not req then return false end
    return (reputation or 0) < req
end

local function pickOrganName(exclude, reputation)
    local pool, sum = {}, 0
    exclude = exclude or {}
    for k, v in pairs(Config.ItemDetails) do
        if (not rareLocked(k, reputation)) and (not exclude[k] or (Config.ItemDetails[k].limit or 1) > (exclude[k] or 0)) then
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

    local stats, identifier = ensureStats(src)
    if not stats then
        return TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Progression vendeur indisponible.', type='error'})
    end

    local scalpelTier = playerHasScalpel(src)
    if not scalpelTier then
        return TriggerClientEvent('ox_lib:notify', src, {title='Organes', description=('Tu as besoin d’un %s.'):format(Config.Scalpel.basic), type='error'})
    end

    if mission.harvested >= 1 and not mission.canSecond then
        return TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Plus rien à prélever sur ce corps.', type='error'})
    end

    if mission.harvested == 0 then
        local chance = scalpelTier.secondHarvestChance or 0
        mission.canSecond = chance > 0 and math.random() < chance
    end

    local base = 80 + baseQualityFromCause(causeHash or 0)
    if scalpelTier.qualityBonus and scalpelTier.qualityBonus ~= 0 then
        base = base + scalpelTier.qualityBonus
    end
    base = math.max(20, math.min(100, base))

    local ttl = Config.OrganDecaySeconds or 600
    if hasItem(src, Config.CoolerItem) then ttl = ttl + (Config.CoolerBonusSeconds or 300) end
    if Config.IcepackItem and hasItem(src, Config.IcepackItem) then ttl = ttl + (Config.IcepackBonusSeconds or 120) end
    if Config.Scalpel.kit and hasItem(src, Config.Scalpel.kit) then
        ttl = ttl + (Config.Scalpel.kitExtraSeconds or 180)
        removeItem(src, Config.Scalpel.kit, 1)
    end

    mission.given = mission.given or {}
    local organ = pickOrganName(mission.given, stats.reputation or 0)

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

        local done = (mission.harvested >= 1 and not mission.canSecond) or mission.harvested >= 2

        if done then
            TriggerClientEvent('outlaw_organ:clearTarget', src)
            missions[src].netId = nil
            missions[src].startedAt = now()
            addContract(identifier)
            saveStats(identifier)
        end

        TriggerClientEvent('ox_lib:notify', src, {title='Organes', description=('Récolte: %s (%d%%)'):format(organ, base), type='success'})
    end)
end)

RegisterNetEvent('outlaw_organ:sellOrgans', function()
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    local stats, identifier = ensureStats(src)
    if not stats then
        return TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Impossible de charger ta réputation.', type='error'})
    end

    local total = 0
    local t = now()
    local repGain = 0
    local multiplier, bonus = getPriceMultiplier(stats.reputation or 0)

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
            local final = math.floor(price * (q / 100) * multiplier)
            if final < 1 then final = 1 end
            total = total + final
            exports.ox_inventory:RemoveItem(src, name, 1, nil, slot.slot)
            recordDelivery(identifier, name, 1)
            repGain = repGain + repGainFromQuality(q)
        end
    end

    if total <= 0 then
        return TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Tu n’as rien à vendre.', type='error'})
    end

    if Config.UseBlackMoney then xPlayer.addAccountMoney('black_money', total) else xPlayer.addMoney(total) end
    local msg = ('Vente: $%s'):format(total)
    if bonus and bonus > 0 then
        msg = msg .. (' (bonus réputation +%d%%)'):format(math.floor(bonus * 100))
    end
    TriggerClientEvent('ox_lib:notify', src, {title='Organes', description=msg, type='success'})

    if repGain > 0 then
        addReputation(identifier, repGain)
    end

    saveStats(identifier)

    if repGain > 0 then
        TriggerClientEvent('ox_lib:notify', src, {title='Réputation', description=('Tu gagnes %d de réputation (total: %d).'):format(repGain, stats.reputation or 0), type='inform'})
    end

    sendWebhook('Vente d’organes', ('**Joueur:** %s\n**Montant:** $%s'):format(GetPlayerName(src), total), 15844367)
end)

RegisterNetEvent('outlaw_organ:buyTool', function(kind)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    if kind == 'kit' then
        local item = Config.Scalpel.kit
        if not item or item == '' then
            return TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Indisponible.', type='error'})
        end
        local price = 400
        if xPlayer.getMoney() < price then
            return TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Pas assez d’argent.', type='error'})
        end
        local ok = exports.ox_inventory:AddItem(src, item, 1)
        if not ok then
            return TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Inventaire plein.', type='error'})
        end
        xPlayer.removeMoney(price)
        return TriggerClientEvent('ox_lib:notify', src, {title='Organes', description=('Achat: %s'):format(item), type='success'})
    end

    local tier = scalpelTierIndex[kind]
    if not tier then
        return TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Indisponible.', type='error'})
    end

    local stats, identifier = ensureStats(src)
    if not stats then
        return TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Progression vendeur indisponible.', type='error'})
    end

    if (stats.reputation or 0) < (tier.reputation or 0) then
        return TriggerClientEvent('ox_lib:notify', src, {title='Organes', description=('Réputation insuffisante (%d requise).'):format(tier.reputation or 0), type='error'})
    end

    local okReq, missing = deliveriesMeetRequirements(stats, tier.requires)
    if not okReq then
        local details = formatMissingList(missing)
        return TriggerClientEvent('ox_lib:notify', src, {title='Organes', description=('Livraisons insuffisantes: %s'):format(details), type='error'})
    end

    local price = tier.price or 0
    if xPlayer.getMoney() < price then
        return TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Pas assez d’argent.', type='error'})
    end

    local ok = exports.ox_inventory:AddItem(src, tier.item, 1)
    if not ok then
        return TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Inventaire plein.', type='error'})
    end

    xPlayer.removeMoney(price)
    stats.unlocks = stats.unlocks or {}
    stats.unlocks[kind] = true
    saveStats(identifier)

    TriggerClientEvent('ox_lib:notify', src, {title='Organes', description=('Achat: %s'):format(tier.label or tier.item), type='success'})
end)

RegisterNetEvent('outlaw_organ:witnessDispatch', function(coords)
    if not coords then return end
    policeDispatch(coords, 'Appel citoyen: activité suspecte / organes')
    sendWebhook('Témoin', ('Activité suspecte repérée en (%.1f, %.1f, %.1f)'):format(coords.x, coords.y, coords.z), 15158332)
end)

AddEventHandler('playerDropped', function()
    local src = source
    missions[src] = nil
    heat[src] = nil
    invOpen[src] = nil
    local identifier = playerIdentifiers[src]
    if identifier then
        saveStats(identifier)
        playerIdentifiers[src] = nil
    end
end)

RegisterCommand('organreset', function(src, args, raw)
    if src == 0 then return end
    missions[src] = nil
    TriggerClientEvent('outlaw_organ:clearTarget', src)
    TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Reset effectué.', type='success'})
end, false)

lib.callback.register('outlaw_organ:getDealerStats', function(source)
    local stats = ensureStats(source)
    if not stats then return nil end

    local deliveries = {}
    for name, data in pairs(Config.ItemDetails) do
        local entry = {
            name = name,
            label = data.label or name,
            count = (stats.deliveries or {})[name] or 0
        }
        table.insert(deliveries, entry)
    end
    table.sort(deliveries, function(a, b)
        if a.count == b.count then
            return a.label < b.label
        end
        return a.count > b.count
    end)

    local rep = stats.reputation or 0
    local multiplier, bonus = getPriceMultiplier(rep)

    local nextRare
    if Config.Reputation and Config.Reputation.RareOrders then
        for item, req in pairs(Config.Reputation.RareOrders) do
            if rep < req and (not nextRare or req < nextRare.required) then
                local cfg = Config.ItemDetails[item]
                nextRare = {
                    item = item,
                    label = (cfg and (cfg.label or item)) or item,
                    required = req
                }
            end
        end
    end

    local tiers = {}
    for _, tier in ipairs(scalpelTiersOrdered) do
        local owned = tier.item and hasItem(source, tier.item)
        local meetsRep = rep >= (tier.reputation or 0)
        local okReq, missing = deliveriesMeetRequirements(stats, tier.requires)
        local missingCopy = {}
        if missing and #missing > 0 then
            for _, info in ipairs(missing) do
                table.insert(missingCopy, {
                    item = info.item,
                    need = info.need,
                    have = info.have,
                    label = (Config.ItemDetails[info.item] and (Config.ItemDetails[info.item].label or info.item)) or info.item
                })
            end
        end
        table.insert(tiers, {
            name = tier.name,
            label = tier.label,
            description = tier.description,
            price = tier.price,
            reputation = tier.reputation,
            requires = tier.requires,
            owned = owned,
            meetsRep = meetsRep,
            available = meetsRep and okReq,
            missing = missingCopy
        })
    end

    return {
        reputation = rep,
        contracts = stats.contracts or 0,
        priceMultiplier = multiplier,
        priceBonus = bonus,
        deliveries = deliveries,
        nextRare = nextRare,
        tiers = tiers
    }
end)

AddEventHandler('onResourceStop', function(resName)
    if resName ~= GetCurrentResourceName() then return end
    for identifier, _ in pairs(statsCache) do
        saveStats(identifier)
    end
end)
