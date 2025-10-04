local ESX = exports['es_extended']:getSharedObject()

local missions = {} -- [src] = { netId=..., coords=vector3, startedAt=os.time() }

local function now() return os.time() end

local function sendWebhook(title, description, color)
    if not Config.DiscordWebhook or Config.DiscordWebhook == 'REPLACE_ME' then return end
    local embed = {
        {
            title = title,
            description = description,
            color = color or 15158332,
            footer = { text = 'Outlaw_OrganHarvest' },
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ')
        }
    }
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
        TriggerClientEvent('ox_lib:notify', src, {title='Organes', description=('Attends %ss avant une nouvelle mission.'):format(remain), type='error'})
        return
    end

    -- assigne un point aléatoire
    local zone = Config.SpawnZones[math.random(#Config.SpawnZones)]
    missions[src] = { netId = nil, coords = zone, startedAt = now() }

    TriggerClientEvent('outlaw_organ:missionAssigned', src, zone)
    sendWebhook('Mission organes assignée', ('**Joueur:** %s\n**Zone:** (%.1f, %.1f, %.1f)'):format(GetPlayerName(src), zone.x, zone.y, zone.z), 3447003)
end)

RegisterNetEvent('outlaw_organ:registerTarget', function(netId, coords)
    local src = source
    if not missions[src] then
        missions[src] = { startedAt = now() }
    end
    missions[src].netId = netId
    missions[src].coords = coords
end)

-- Helper pour compter un item côté ox_inventory
local function countItem(src, name)
    return exports.ox_inventory:Search(src, 'count', name) or 0
end

local function addItem(src, name, count)
    return exports.ox_inventory:AddItem(src, name, count or 1)
end

local function removeItem(src, name, count)
    return exports.ox_inventory:RemoveItem(src, name, count or 1)
end

local function playerHasScalpel(src)
    return countItem(src, Config.ScalpelItem) > 0
end

-- Choisit un organe avec une pondération inverse au prix (moins cher = plus fréquent)
local function pickOrganName()
    local pool, sum = {}, 0
    for k, v in pairs(Config.ItemDetails) do
        local price = math.max(1, tonumber(v.price) or 1)
        local w = math.floor(1000 / price) -- cœur très rare, os très commun
        if w < 1 then w = 1 end
        sum = sum + w
        table.insert(pool, {name=k, weight=w})
    end
    local r = math.random(1, sum)
    local acc = 0
    for _, it in ipairs(pool) do
        acc = acc + it.weight
        if r <= acc then return it.name end
    end
    return 'organe'
end

RegisterNetEvent('outlaw_organ:harvest', function(netId)
    local src = source
    local mission = missions[src]
    if not mission or not mission.netId or mission.netId ~= netId then
        TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Aucune cible valide.', type='error'})
        return
    end
    -- distance sécurité
    local ent = NetworkGetEntityFromNetworkId(netId)
    if not ent or ent == 0 or not DoesEntityExist(ent) then
        TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='La cible est introuvable.', type='error'})
        return
    end
    local pedCoords = GetEntityCoords(ent)
    local plyCoords = GetEntityCoords(GetPlayerPed(src))
    if #(pedCoords - plyCoords) > 5.0 then
        TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Tu es trop loin de la cible.', type='error'})
        return
    end
    if not playerHasScalpel(src) then
        TriggerClientEvent('ox_lib:notify', src, {title='Organes', description=('Tu as besoin d’un %s.'):format(Config.ScalpelItem), type='error'})
        return
    end

    -- Donne 1 organe aléatoire
    local organ = pickOrganName()
    local ok, reason = addItem(src, organ, 1)
    if not ok then
        TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Inventaire plein.', type='error'})
        return
    end

    -- Fin de mission côté serveur
    TriggerClientEvent('outlaw_organ:clearTarget', src)
    missions[src].netId = nil
    missions[src].startedAt = now() -- redémarre le cooldown dès la récolte

    TriggerClientEvent('ox_lib:notify', src, {title='Organes', description=('Récolte réussie: %s'):format(organ), type='success'})
    sendWebhook('Prélèvement réussi', ('**Joueur:** %s\n**Item:** %s\n**Pos:** (%.1f, %.1f, %.1f)'):format(GetPlayerName(src), organ, pedCoords.x, pedCoords.y, pedCoords.z), 5763719)
end)

RegisterNetEvent('outlaw_organ:sellOrgans', function()
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    local total = 0
    for name, data in pairs(Config.ItemDetails) do
        local count = countItem(src, name)
        if count and count > 0 then
            local price = tonumber(data.price) or 0
            total = total + (price * count)
        end
    end

    if total <= 0 then
        TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Tu n’as rien à vendre.', type='error'})
        return
    end

    -- retire les items puis paie
    for name, data in pairs(Config.ItemDetails) do
        local count = countItem(src, name)
        if count and count > 0 then
            removeItem(src, name, count)
        end
    end

    if Config.UseBlackMoney then
        xPlayer.addAccountMoney('black_money', total)
    else
        xPlayer.addMoney(total)
    end

    TriggerClientEvent('ox_lib:notify', src, {title='Organes', description=('Vente effectuée: $%s'):format(total), type='success'})
    sendWebhook('Vente d’organes', ('**Joueur:** %s\n**Montant:** $%s'):format(GetPlayerName(src), total), 15844367)
end)

RegisterNetEvent('outlaw_organ:buyScalpel', function()
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    local price = tonumber(Config.ScalpelPrice) or 0
    if price <= 0 then
        TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Item non disponible.', type='error'})
        return
    end

    if xPlayer.getMoney() < price then
        TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Pas assez d’argent liquide.', type='error'})
        return
    end

    local ok, reason = exports.ox_inventory:AddItem(src, Config.ScalpelItem, 1)
    if not ok then
        TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Inventaire plein.', type='error'})
        return
    end

    xPlayer.removeMoney(price)
    TriggerClientEvent('ox_lib:notify', src, {title='Organes', description=('Achat: %s'):format(Config.ScalpelItem), type='success'})
end)

AddEventHandler('playerDropped', function()
    local src = source
    missions[src] = nil
end)

-- Commande admin: /organreset (reset cooldown + mission)
RegisterCommand('organreset', function(src, args, raw)
    if src == 0 then return end
    missions[src] = nil
    TriggerClientEvent('outlaw_organ:clearTarget', src)
    TriggerClientEvent('ox_lib:notify', src, {title='Organes', description='Reset effectué.', type='success'})
end, false)
