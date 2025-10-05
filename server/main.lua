local ESX = exports['es_extended']:getSharedObject()

local missions = {} -- [src] = { netId=..., coords=vector3, startedAt=os.time(), harvested=0, given={}, canSecond=false, lastDispatchAt=0 }
local heat = {}     -- [src] = { value=0, updatedAt=os.time() }
local invOpen = {}  -- [src] = true/false
local statsCache = {} -- [identifier] = stats table

local function now() return os.time() end

local function getIdentifier(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return nil end
    local identifier = xPlayer.identifier
    if not identifier and xPlayer.getIdentifier then identifier = xPlayer.getIdentifier() end
    return identifier
end

local function loadStats(identifier)
    if not identifier then return nil end
    if statsCache[identifier] then return statsCache[identifier] end
    local raw = GetResourceKvpString(('outlaw_organe:stats:%s'):format(identifier))
    local data = raw and json.decode(raw) or nil
    if not data then
        data = {
            reputation = 0,
            contractsCompleted = 0,
            deliveries = {},
            totalQuality = 0,
            bestQuality = 0,
            sales = 0,
            upgrades = {}
        }
    end
    data.reputation = clampReputation(data.reputation or 0)
    statsCache[identifier] = data
    return data
end

local function saveStats(identifier)
    if not identifier then return end
    local data = statsCache[identifier]
    if not data then return end
    SetResourceKvp(('outlaw_organe:stats:%s'):format(identifier), json.encode(data))
end

local function getStats(src)
    local identifier = getIdentifier(src)
    if not identifier then return nil, nil end
    local data = loadStats(identifier)
    return data, identifier
end

local function clampReputation(value)
    if not value then return 0 end
    local max = Config.Reputation and Config.Reputation.Max
    if max and max > 0 then return math.min(value, max) end
    return value
end

local sortedTiers
local function getSortedTiers()
    if sortedTiers then return sortedTiers end
    sortedTiers = {}
    local tiers = (Config.Reputation and Config.Reputation.Tiers) or {}
    for _, tier in ipairs(tiers) do table.insert(sortedTiers, tier) end
    table.sort(sortedTiers, function(a, b)
        return (a.reputation or 0) < (b.reputation or 0)
    end)
    return sortedTiers
end

local function calculatePriceMultiplier(reputation)
    local tiers = getSortedTiers()
    local current = tiers[1] or { name = 'Recrue', reputation = 0, multiplier = 1.0 }
    local nextTier = nil
    local multiplier = current.multiplier or 1.0
    for _, tier in ipairs(tiers) do
        if reputation >= (tier.reputation or 0) then
            current = tier
            multiplier = tier.multiplier or multiplier
        elseif not nextTier then
            nextTier = tier
        end
    end
    return multiplier, current, nextTier
end

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
    if not Config.Scalpel or not Config.Scalpel.variants then return nil end
    local bestKey, bestData = nil, nil
    for key, data in pairs(Config.Scalpel.variants) do
        if data.item and hasItem(src, data.item) then
            if not bestData or (data.bonusQuality or 0) > (bestData.bonusQuality or 0) then
                bestKey, bestData = key, data
            end
        end
    end
    if bestKey then
        return { key = bestKey, data = bestData }
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

local function pickOrganName(exclude, stats)
    local pool, sum = {}, 0
    exclude = exclude or {}
    local reputation = stats and (stats.reputation or 0) or 0
    for k, v in pairs(Config.ItemDetails) do
        local unlock = tonumber(v.unlockReputation or 0)
        if reputation >= unlock then
            if not exclude[k] or (Config.ItemDetails[k].limit or 1) > (exclude[k] or 0) then
                local price = math.max(1, tonumber(v.price) or 1)
                local w = math.floor(1000 / price)
                if v.weight and v.weight > 0 then w = v.weight end
                if w < 1 then w = 1 end
                sum = sum + w
                table.insert(pool, {name=k, weight=w})
            end
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
        local baseVariant = Config.Scalpel and Config.Scalpel.variants and Config.Scalpel.variants.basic
        local label = baseVariant and (baseVariant.label or baseVariant.item) or 'scalpel'
        return TriggerClientEvent('ox_lib:notify', src, {title='Organes', description=('Tu as besoin d’un %s.'):format(label), type='error'})
    end

    if mission.harvested >= 1 and not mission.canSecond then
        return TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Plus rien à prélever sur ce corps.', type='error'})
    end

    if mission.harvested == 0 then
        local canSecond = false
        local chance = (scalpelType.data and scalpelType.data.secondHarvestChance) or (Config.SecondHarvestChance or 0.0)
        if chance > 0 and math.random() < chance then canSecond = true end
        mission.canSecond = canSecond
    end

    local base = 80 + baseQualityFromCause(causeHash or 0)
    if scalpelType.data and scalpelType.data.bonusQuality then
        base = base + scalpelType.data.bonusQuality
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
    local stats = select(1, getStats(src))
    local organ = pickOrganName(mission.given, stats)

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
            local playerStats, identifier = getStats(src)
            if playerStats then
                playerStats.contractsCompleted = (playerStats.contractsCompleted or 0) + 1
                if Config.Reputation and Config.Reputation.ContractBonus then
                    playerStats.reputation = clampReputation((playerStats.reputation or 0) + (Config.Reputation.ContractBonus or 0))
                end
                playerStats.lastContractAt = now()
                saveStats(identifier)
            end
        end

        TriggerClientEvent('ox_lib:notify', src, {title='Organes', description=('Récolte: %s (%d%%)'):format(organ, base), type='success'})
    end)
end)

local function buildDeliverySnapshot(stats)
    local deliveries = {}
    for name, data in pairs(Config.ItemDetails) do
        table.insert(deliveries, {
            name = name,
            label = data.label or name,
            count = stats and stats.deliveries and (stats.deliveries[name] or 0) or 0,
            price = data.price or 0,
            unlock = data.unlockReputation or 0
        })
    end
    table.sort(deliveries, function(a, b)
        if a.price == b.price then return a.name < b.name end
        return a.price > b.price
    end)
    return deliveries
end

RegisterNetEvent('outlaw_organ:requestDealerMenu', function()
    local src = source
    local stats = select(1, getStats(src))
    local reputation = stats and (stats.reputation or 0) or 0
    local multiplier, currentTier, nextTier = calculatePriceMultiplier(reputation)
    local deliveries = buildDeliverySnapshot(stats)
    local rareUnlocks = {}
    if Config.Reputation and Config.Reputation.RareOrders then
        for item, info in pairs(Config.Reputation.RareOrders) do
            table.insert(rareUnlocks, {
                name = item,
                label = (Config.ItemDetails[item] and Config.ItemDetails[item].label) or item,
                required = info.reputation or 0,
                unlocked = reputation >= (info.reputation or 0)
            })
        end
        table.sort(rareUnlocks, function(a, b)
            return a.required < b.required
        end)
    end

    local scalpelInfo = nil
    local ownedScalpel = playerHasScalpel(src)
    if ownedScalpel and ownedScalpel.data then
        scalpelInfo = {
            key = ownedScalpel.key,
            label = ownedScalpel.data.label or ownedScalpel.data.item,
            bonusQuality = ownedScalpel.data.bonusQuality or 0,
            secondChance = ownedScalpel.data.secondHarvestChance or 0
        }
    end

    local upgrades = {}
    for id, upgrade in pairs((Config.Scalpel and Config.Scalpel.upgrades) or {}) do
        local variants = Config.Scalpel.variants or {}
        local fromVariant = variants[upgrade.from or '']
        local toVariant = variants[upgrade.to or '']
        if fromVariant and toVariant then
            local entry = {
                id = upgrade.id or id,
                label = toVariant.label or toVariant.item,
                price = upgrade.price or 0,
                reputation = upgrade.reputation or 0,
                deliveries = upgrade.deliveries or {},
                hasBase = hasItem(src, fromVariant.item),
                targetOwned = toVariant.item and hasItem(src, toVariant.item)
            }
            entry.reasons = {}
            if entry.targetOwned then
                entry.status = 'owned'
            else
                if reputation < entry.reputation then
                    table.insert(entry.reasons, ('Réputation %d/%d'):format(reputation, entry.reputation))
                end
                if upgrade.deliveries then
                    for organ, count in pairs(upgrade.deliveries) do
                        local delivered = stats and stats.deliveries and (stats.deliveries[organ] or 0) or 0
                        if delivered < count then
                            table.insert(entry.reasons, ('%s %d/%d'):format((Config.ItemDetails[organ] and Config.ItemDetails[organ].label) or organ, delivered, count))
                        end
                    end
                end
                if not entry.hasBase then
                    table.insert(entry.reasons, ('Posséder: %s'):format(fromVariant.label or fromVariant.item))
                end
                if #entry.reasons == 0 then
                    entry.status = 'ready'
                else
                    entry.status = 'locked'
                end
            end
            table.insert(upgrades, entry)
        end
    end
    table.sort(upgrades, function(a, b)
        if a.status == b.status then return (a.reputation or 0) < (b.reputation or 0) end
        if a.status == 'ready' then return true end
        if b.status == 'ready' then return false end
        if a.status == 'owned' then return false end
        if b.status == 'owned' then return true end
        return (a.reputation or 0) < (b.reputation or 0)
    end)

    local avgQuality = 0
    if stats and (stats.sales or 0) > 0 then
        avgQuality = math.floor((stats.totalQuality or 0) / (stats.sales or 1))
    end

    TriggerClientEvent('outlaw_organ:openDealerMenu', src, {
        reputation = reputation,
        multiplier = multiplier,
        tier = currentTier,
        nextTier = nextTier,
        deliveries = deliveries,
        rare = rareUnlocks,
        stats = {
            contracts = stats and (stats.contractsCompleted or 0) or 0,
            bestQuality = stats and (stats.bestQuality or 0) or 0,
            averageQuality = avgQuality,
            totalSales = stats and (stats.sales or 0) or 0
        },
        scalpel = scalpelInfo,
        upgrades = upgrades
    })
end)

RegisterNetEvent('outlaw_organ:upgradeScalpel', function(id)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    local upgrade = Config.Scalpel and Config.Scalpel.upgrades and Config.Scalpel.upgrades[id]
    if not upgrade then
        return TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Amélioration introuvable.', type='error'})
    end

    local variants = Config.Scalpel.variants or {}
    local fromVariant = variants[upgrade.from or '']
    local toVariant = variants[upgrade.to or '']
    if not fromVariant or not toVariant then
        return TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Configuration incomplète.', type='error'})
    end

    if not hasItem(src, fromVariant.item) then
        return TriggerClientEvent('ox_lib:notify', src, {title='Organes', description=('Tu dois posséder %s.'):format(fromVariant.label or fromVariant.item), type='error'})
    end

    if hasItem(src, toVariant.item) then
        return TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Tu possèdes déjà cette amélioration.', type='error'})
    end

    local stats, identifier = getStats(src)
    if not stats then
        return TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Statistiques indisponibles.', type='error'})
    end

    local reputation = stats.reputation or 0
    if upgrade.reputation and reputation < upgrade.reputation then
        return TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Réputation insuffisante.', type='error'})
    end

    if upgrade.deliveries then
        for organ, count in pairs(upgrade.deliveries) do
            local delivered = stats.deliveries and (stats.deliveries[organ] or 0) or 0
            if delivered < count then
                local label = (Config.ItemDetails[organ] and Config.ItemDetails[organ].label) or organ
                return TriggerClientEvent('ox_lib:notify', src, {title='Organes', description=('Livraisons insuffisantes: %s (%d/%d)'):format(label, delivered, count), type='error'})
            end
        end
    end

    local price = upgrade.price or 0
    if price > 0 and xPlayer.getMoney() < price then
        return TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Pas assez d’argent pour l’amélioration.', type='error'})
    end

    if price > 0 then
        xPlayer.removeMoney(price)
    end

    local removed = exports.ox_inventory:RemoveItem(src, fromVariant.item, 1)
    if not removed then
        if price > 0 then xPlayer.addMoney(price) end
        return TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Impossible de retirer ton ancien scalpel.', type='error'})
    end

    local added = exports.ox_inventory:AddItem(src, toVariant.item, 1)
    if not added then
        exports.ox_inventory:AddItem(src, fromVariant.item, 1)
        if price > 0 then xPlayer.addMoney(price) end
        return TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Inventaire plein pour le nouveau scalpel.', type='error'})
    end

    stats.upgrades = stats.upgrades or {}
    stats.upgrades[upgrade.to] = now()
    saveStats(identifier)

    TriggerClientEvent('ox_lib:notify', src, {title='Organes', description=('Amélioration obtenue: %s'):format(toVariant.label or toVariant.item), type='success'})
    sendWebhook('Scalpel amélioré', ('**Joueur:** %s\n**Amélioration:** %s -> %s'):format(GetPlayerName(src), fromVariant.item, toVariant.item), 5793266)
end)

RegisterNetEvent('outlaw_organ:sellOrgans', function()
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    local total = 0
    local t = now()
    local stats, identifier = getStats(src)
    local multiplier, currentTier = 1.0, nil
    if stats then
        local nextTier
        multiplier, currentTier, nextTier = calculatePriceMultiplier(stats.reputation or 0)
    end
    local saleSummary = { delivered = {}, repGain = 0, qualityPoints = 0, bestQuality = 0, items = 0 }
    local baseGain = Config.Reputation and Config.Reputation.BaseGainPerItem or 0
    local qualityWeight = Config.Reputation and Config.Reputation.QualityWeight or 0

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
            local final = math.floor(price * (q / 100))
            final = math.floor(final * (multiplier or 1.0))
            total = total + final
            exports.ox_inventory:RemoveItem(src, name, 1, nil, slot.slot)

            saleSummary.items = saleSummary.items + 1
            saleSummary.qualityPoints = saleSummary.qualityPoints + q
            if q > (saleSummary.bestQuality or 0) then saleSummary.bestQuality = q end
            saleSummary.delivered[name] = (saleSummary.delivered[name] or 0) + 1

            local repValue = (Config.ItemDetails[name] and Config.ItemDetails[name].rep) or 0
            local gain = baseGain + (repValue * qualityWeight * (q / 100))
            gain = math.floor(math.max(0, gain))
            if gain > 0 then saleSummary.repGain = saleSummary.repGain + gain end
        end
    end

    if total <= 0 then
        return TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Tu n’as rien à vendre.', type='error'})
    end

    if Config.UseBlackMoney then xPlayer.addAccountMoney('black_money', total) else xPlayer.addMoney(total) end
    if stats then
        stats.deliveries = stats.deliveries or {}
        for item, count in pairs(saleSummary.delivered) do
            stats.deliveries[item] = (stats.deliveries[item] or 0) + count
        end
        stats.totalQuality = (stats.totalQuality or 0) + (saleSummary.qualityPoints or 0)
        if saleSummary.bestQuality and saleSummary.bestQuality > (stats.bestQuality or 0) then
            stats.bestQuality = saleSummary.bestQuality
        end
        stats.sales = (stats.sales or 0) + (saleSummary.items or 0)
        if saleSummary.repGain and saleSummary.repGain > 0 then
            stats.reputation = clampReputation((stats.reputation or 0) + saleSummary.repGain)
        end
        saveStats(identifier)
    end

    local msg = ('Vente: $%s'):format(total)
    if multiplier and multiplier > 1.0 then
        msg = msg .. (' | Bonus x%.2f'):format(multiplier)
    end
    if saleSummary.repGain and saleSummary.repGain > 0 then
        msg = msg .. (' | Réputation +%d'):format(saleSummary.repGain)
    end
    TriggerClientEvent('ox_lib:notify', src, {title='Organes', description=msg, type='success'})
    sendWebhook('Vente d’organes', ('**Joueur:** %s\n**Montant:** $%s'):format(GetPlayerName(src), total), 15844367)
end)

RegisterNetEvent('outlaw_organ:buyTool', function(kind)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    local item, price, label
    if kind == 'kit' then
        item = Config.Scalpel.kit
        price = 400
        label = 'Kit chirurgical'
    else
        local variants = Config.Scalpel and Config.Scalpel.variants or {}
        local variant = variants and variants[kind] or nil
        if variant then
            if variant.buyPrice and variant.buyPrice > 0 then
                local stats = select(1, getStats(src))
                if variant.reputation and variant.reputation > 0 then
                    local rep = stats and (stats.reputation or 0) or 0
                    if rep < variant.reputation then
                        return TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Réputation insuffisante pour cet achat.', type='error'})
                    end
                end
                item = variant.item
                price = variant.buyPrice
                label = variant.label or variant.item
            else
                return TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Cet outil doit être débloqué via amélioration.', type='error'})
            end
        end
    end

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
    TriggerClientEvent('ox_lib:notify', src, {title='Organes', description=('Achat: %s'):format(label or item), type='success'})
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
end)

RegisterCommand('organreset', function(src, args, raw)
    if src == 0 then return end
    missions[src] = nil
    TriggerClientEvent('outlaw_organ:clearTarget', src)
    TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Reset effectué.', type='success'})
end, false)
