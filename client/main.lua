local missionPed, dealerPed
local activeTarget = { netId = nil, blip = nil }
local corpseZoneId = nil

local function loadModel(model)
    if type(model) == 'string' then model = joaat(model) end
    if not IsModelInCdimage(model) then return false end
    RequestModel(model)
    local tries = 0
    while not HasModelLoaded(model) and tries < 100 do Wait(50) tries = tries + 1 end
    return HasModelLoaded(model)
end

local function spawnStaticNpc(model, coords, heading)
    if not loadModel(model) then return nil end
    local ped = CreatePed(4, joaat(model), coords.x, coords.y, coords.z - 1.0, heading or 0.0, false, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCanRagdoll(ped, false)
    return ped
end

local function addMissionNpcTarget(ped)
    exports.ox_target:addLocalEntity(ped, {{
        icon = 'fa-solid fa-briefcase-medical',
        label = 'Démarrer une mission',
        distance = 2.0,
        onSelect = function(_) TriggerServerEvent('outlaw_organ:startMission') end
    }})
end

local function addDealerNpcTarget(ped)
    exports.ox_target:addLocalEntity(ped, {
        {
            icon = 'fa-solid fa-handshake',
            label = 'Parler au trafiquant',
            distance = 2.0,
            onSelect = function(_) TriggerServerEvent('outlaw_organ:requestDealerMenu') end
        },
        {
            icon = 'fa-solid fa-hand-holding-dollar',
            label = 'Vente rapide',
            distance = 2.0,
            onSelect = function(_) TriggerServerEvent('outlaw_organ:sellOrgans') end
        }
    })
end

RegisterNetEvent('outlaw_organ:applyInfection', function(duration, mult)
    local playerId = PlayerId()
    local restore = 1.0
    if mult and mult > 0.1 and mult < 1.0 then SetRunSprintMultiplierForPlayer(playerId, mult) end
    lib.notify({title='Santé', description='Infection contractée, vous vous sentez faible...', type='error'})
    Wait((duration or 600) * 1000)
    SetRunSprintMultiplierForPlayer(playerId, restore)
    lib.notify({title='Santé', description='Vous vous sentez mieux.', type='inform'})
end)

RegisterNetEvent('outlaw_organ:policePing', function(coords, text)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, Config.PolicePing.BlipSprite)
    SetBlipColour(blip, Config.PolicePing.BlipColor)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentString(text or 'Activité suspecte'); EndTextCommandSetBlipName(blip)
    lib.notify({title='Dispatch', description=text or 'Activité suspecte', type='warning'})
    Wait((Config.PolicePing.Duration or 60) * 1000)
    if DoesBlipExist(blip) then RemoveBlip(blip) end
end)

local function registerDealerMenus(data)
    local reputation = data.reputation or 0
    local multiplier = data.multiplier or 1.0
    local tierName = (data.tier and data.tier.name) or 'Inconnu'
    local descParts = {('Rang: %s'):format(tierName), ('Réputation: %d'):format(reputation), ('Bonus prix: x%.2f'):format(multiplier)}
    if data.nextTier and data.nextTier.reputation then
        table.insert(descParts, ('Prochain rang: %s (%d RP)'):format(data.nextTier.name or '???', data.nextTier.reputation))
    end
    if data.scalpel then
        local chance = data.scalpel.secondChance and math.floor(data.scalpel.secondChance * 100) or 0
        table.insert(descParts, ('Scalpel: %s (+%d qualité, %d%% chance double prélèvement)'):format(data.scalpel.label, data.scalpel.bonusQuality or 0, chance))
    end
    local mainOptions = {
        {
            title = 'Vendre mes organes',
            description = 'Liquider immédiatement votre stock actuel.',
            icon = 'fa-solid fa-hand-holding-dollar',
            serverEvent = 'outlaw_organ:sellOrgans'
        },
        {
            title = 'Acheter du matériel',
            description = 'Scalpels disponibles et consommables.',
            icon = 'fa-solid fa-scalpel',
            menu = 'outlaw_organ:dealerBuy'
        },
        {
            title = 'Réputation & livraisons',
            description = 'Consulter votre progression détaillée.',
            icon = 'fa-solid fa-chart-simple',
            menu = 'outlaw_organ:dealerStats'
        },
        {
            title = 'Améliorer mon scalpel',
            description = (not data.upgrades or #data.upgrades == 0) and 'Aucune amélioration débloquée pour le moment.' or 'Débloquer des scalpels uniques via la réputation.',
            icon = 'fa-solid fa-screwdriver-wrench',
            menu = 'outlaw_organ:dealerUpgrades'
        }
    }

    lib.registerContext({
        id = 'outlaw_organ:dealerMain',
        title = 'Marché noir - Organes',
        description = table.concat(descParts, '\n'),
        options = mainOptions
    })

    local buyOptions = {}
    local variants = Config.Scalpel and Config.Scalpel.variants or {}
    local variantList = {}
    for key, variant in pairs(variants) do
        if variant.buyPrice and variant.buyPrice > 0 then
            table.insert(variantList, { key = key, data = variant })
        end
    end
    table.sort(variantList, function(a, b)
        return (a.data.buyPrice or 0) < (b.data.buyPrice or 0)
    end)
    for _, entry in ipairs(variantList) do
        local key = entry.key
        local variant = entry.data
        local locked = variant.reputation and reputation < variant.reputation
        local label = variant.label or variant.item
        local quality = variant.bonusQuality or 0
        local secondChance = variant.secondHarvestChance and math.floor(variant.secondHarvestChance * 100) or 0
        local description = ('Prix: $%d | Bonus qualité: +%d | Chance double: %d%%'):format(variant.buyPrice, quality, secondChance)
        local option = {
            title = label,
            description = description,
            icon = locked and 'fa-solid fa-lock' or 'fa-solid fa-scalpel',
            disabled = locked,
            rightLabel = locked and 'LOCK' or '$' .. variant.buyPrice,
            metadata = {}
        }
        if variant.reputation and variant.reputation > 0 then
            table.insert(option.metadata, {label = 'Réputation requise', value = tostring(variant.reputation)})
        end
        if not locked then
            option.serverEvent = 'outlaw_organ:buyTool'
            option.args = key
        end
        table.insert(buyOptions, option)
    end
    if Config.Scalpel and Config.Scalpel.kit then
        table.insert(buyOptions, {
            title = 'Kit chirurgical',
            description = 'Recharge de temps supplémentaire pour les organes frais.',
            icon = 'fa-solid fa-kit-medical',
            rightLabel = '$400',
            serverEvent = 'outlaw_organ:buyTool',
            args = 'kit'
        })
    end
    if #buyOptions == 0 then
        table.insert(buyOptions, { title = 'Aucune offre disponible', disabled = true })
    end
    lib.registerContext({
        id = 'outlaw_organ:dealerBuy',
        title = 'Boutique du trafiquant',
        menu = 'outlaw_organ:dealerMain',
        options = buyOptions
    })

    local stats = data.stats or {}
    local statsOptions = {
        {
            title = ('Contrats terminés: %d'):format(stats.contracts or 0),
            description = ('Qualité moyenne: %d%% | Meilleure qualité: %d%%'):format(stats.averageQuality or 0, stats.bestQuality or 0),
            icon = 'fa-solid fa-list-check',
            disabled = true
        },
        {
            title = ('Organes vendus: %d'):format(stats.totalSales or 0),
            icon = 'fa-solid fa-boxes-stacked',
            disabled = true
        },
        {
            title = 'Détails des livraisons',
            description = 'Voir le cumul par organe.',
            icon = 'fa-solid fa-dolly',
            menu = 'outlaw_organ:dealerDeliveries'
        }
    }
    if data.rare and #data.rare > 0 then
        table.insert(statsOptions, {
            title = 'Commandes rares',
            description = 'Statut de vos accès aux pièces spéciales.',
            icon = 'fa-solid fa-heart-pulse',
            menu = 'outlaw_organ:dealerRare'
        })
    end
    lib.registerContext({
        id = 'outlaw_organ:dealerStats',
        title = 'Progression & réputation',
        menu = 'outlaw_organ:dealerMain',
        options = statsOptions
    })

    local deliveryOptions = {}
    for _, delivery in ipairs(data.deliveries or {}) do
        local unlocked = reputation >= (delivery.unlock or 0)
        local unlockText = delivery.unlock and delivery.unlock > 0 and ('Déblocage: %d RP'):format(delivery.unlock) or 'Disponible'
        table.insert(deliveryOptions, {
            title = delivery.label or delivery.name,
            description = ('Livraisons: %d | Prix de base: $%d'):format(delivery.count or 0, delivery.price or 0),
            icon = unlocked and 'fa-solid fa-box-open' or 'fa-solid fa-lock',
            disabled = true,
            metadata = {{label = 'Déblocage', value = unlockText}}
        })
    end
    if #deliveryOptions == 0 then deliveryOptions = {{ title = 'Aucune livraison enregistrée', disabled = true }} end
    lib.registerContext({
        id = 'outlaw_organ:dealerDeliveries',
        title = 'Détails des livraisons',
        menu = 'outlaw_organ:dealerStats',
        options = deliveryOptions
    })

    local rareOptions = {}
    for _, rare in ipairs(data.rare or {}) do
        local unlocked = rare.unlocked
        local title = rare.label or rare.name
        table.insert(rareOptions, {
            title = title,
            description = ('Requis: %d RP | Statut: %s'):format(rare.required or 0, unlocked and 'Débloqué' or 'Verrouillé'),
            icon = unlocked and 'fa-solid fa-heart' or 'fa-solid fa-heart-crack',
            disabled = true
        })
    end
    if #rareOptions == 0 then rareOptions = {{ title = 'Aucune commande rare', disabled = true }} end
    lib.registerContext({
        id = 'outlaw_organ:dealerRare',
        title = 'Commandes rares',
        menu = 'outlaw_organ:dealerStats',
        options = rareOptions
    })

    local upgradeOptions = {}
    for _, upgrade in ipairs(data.upgrades or {}) do
        local option = {
            title = upgrade.label,
            icon = 'fa-solid fa-screwdriver-wrench',
            rightLabel = upgrade.status == 'ready' and 'PRÊT' or (upgrade.status == 'owned' and 'OBTENU' or 'LOCK'),
            metadata = {},
            description = ('Prix: $%d | Réputation requise: %d'):format(upgrade.price or 0, upgrade.reputation or 0)
        }
        if upgrade.reasons and #upgrade.reasons > 0 then
            for _, reason in ipairs(upgrade.reasons) do
                table.insert(option.metadata, {label = 'Condition', value = reason})
            end
        end
        if upgrade.status == 'ready' then
            option.serverEvent = 'outlaw_organ:upgradeScalpel'
            option.args = upgrade.id
        else
            option.disabled = true
        end
        if upgrade.targetOwned then
            option.disabled = true
        end
        table.insert(upgradeOptions, option)
    end
    if #upgradeOptions == 0 then upgradeOptions = {{ title = 'Aucune amélioration disponible', disabled = true }} end
    lib.registerContext({
        id = 'outlaw_organ:dealerUpgrades',
        title = 'Atelier clandestin',
        menu = 'outlaw_organ:dealerMain',
        options = upgradeOptions
    })
end

RegisterNetEvent('outlaw_organ:openDealerMenu', function(data)
    if not data then return end
    registerDealerMenus(data)
    lib.showContext('outlaw_organ:dealerMain')
end)

local function createCorpseZone(ped)
    if corpseZoneId then return end
    local c = GetEntityCoords(ped)
    corpseZoneId = exports.ox_target:addSphereZone({
        coords = vec3(c.x, c.y, c.z),
        radius = 1.6,
        debug = false,
        options = {{
            icon = 'fa-solid fa-scalpel',
            label = 'Prélever (corps)',
            onSelect = function(_)
                if not activeTarget.netId then return end
                local entity = NetworkGetEntityFromNetworkId(activeTarget.netId)
                if not entity or entity == 0 or not DoesEntityExist(entity) then return end
                TaskTurnPedToFaceEntity(PlayerPedId(), entity, 500); Wait(300)
                local ok = lib.progressCircle({
                    duration = 7000, position = 'bottom', useWhileDead = false, canCancel = true,
                    disable = { move = true, car = true, combat = true },
                    anim = { dict = 'amb@medic@standing@tendtodead@base', clip = 'base' },
                    label = 'Prélèvement du corps...'
                })
                if not ok then return end
                local cause = GetPedCauseOfDeath(entity) or 0
                TriggerServerEvent('outlaw_organ:harvest', activeTarget.netId, cause)
            end
        }}
    })
    lib.notify({title='Organes', description='La cible est neutralisée. Prélève l’organe.', type='inform'})
end

RegisterNetEvent('outlaw_organ:missionAssigned', function(targetCoords)
    local model = Config.TargetPedModels[math.random(#Config.TargetPedModels)]
    if not loadModel(model) then return lib.notify({title='Organes', description='Erreur de chargement du ped cible', type='error'}) end
    local ped = CreatePed(4, joaat(model), targetCoords.x, targetCoords.y, targetCoords.z - 1.0, 0.0, true, true)
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedSeeingRange(ped, 0.0)
    SetPedHearingRange(ped, 0.0)
    SetPedAlertness(ped, 0)
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_STAND_IMPATIENT', 0, true)

    exports.ox_target:addLocalEntity(ped, {{
        icon = 'fa-solid fa-scalpel',
        label = 'Prélever un organe',
        distance = 1.8,
        onSelect = function(data)
            local victim = data.entity
            TaskTurnPedToFaceEntity(PlayerPedId(), victim, 500); Wait(500)
            local ok = lib.progressCircle({
                duration = 7000, position = 'bottom', useWhileDead = false, canCancel = true,
                disable = { move = true, car = true, combat = true },
                anim = { dict = 'amb@medic@standing@tendtodead@base', clip = 'base' },
                label = 'Prélèvement en cours...'
            })
            if not ok then return lib.notify({title='Organes', description='Prélèvement annulé.', type='error'}) end
            local netId = NetworkGetNetworkIdFromEntity(victim)
            local cause = GetPedCauseOfDeath(victim) or 0
            TriggerServerEvent('outlaw_organ:harvest', netId, cause)
        end
    }})

    local netId = NetworkGetNetworkIdFromEntity(ped)
    Entity(ped).state:set('organOwner', GetPlayerServerId(PlayerId()), true)

    if DoesBlipExist(activeTarget.blip) then RemoveBlip(activeTarget.blip) end
    local blip = AddBlipForEntity(ped)
    SetBlipSprite(blip, Config.BlipSprite)
    SetBlipColour(blip, Config.BlipColor)
    SetBlipRoute(blip, true)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentString('Cible - Organe'); EndTextCommandSetBlipName(blip)

    activeTarget.netId = netId
    activeTarget.blip = blip

    TriggerServerEvent('outlaw_organ:registerTarget', netId, targetCoords)
    lib.notify({title='Organes', description='Cible assignée. Rejoins le point sur ta carte.', type='inform'})

    CreateThread(function()
        while DoesEntityExist(ped) do
            if IsPedDeadOrDying(ped, true) then
                createCorpseZone(ped)
                if Config.Witness and Config.Witness.Enable then
                    local pcoords = GetEntityCoords(ped)
                    local pool = GetGamePool('CPed')
                    for _, npc in ipairs(pool) do
                        if npc ~= ped and not IsPedAPlayer(npc) and not IsPedDeadOrDying(npc) then
                            if #(GetEntityCoords(npc) - pcoords) <= (Config.Witness.Radius or 25.0) then
                                if math.random() < (Config.Witness.CallChance or 0.35) then
                                    TriggerServerEvent('outlaw_organ:witnessDispatch', pcoords)
                                    break
                                end
                            end
                        end
                    end
                end
                break
            end
            Wait(300)
        end
    end)
end)

RegisterNetEvent('outlaw_organ:clearTarget', function()
    if activeTarget.netId then
        local ped = NetworkGetEntityFromNetworkId(activeTarget.netId)
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end
    if DoesBlipExist(activeTarget.blip) then RemoveBlip(activeTarget.blip) end
    if corpseZoneId then exports.ox_target:removeZone(corpseZoneId); corpseZoneId = nil end
    activeTarget.netId = nil
    activeTarget.blip = nil
end)

CreateThread(function()
    local m = Config.MissionNpc
    missionPed = spawnStaticNpc(m.model, m.coords, m.heading); if missionPed then addMissionNpcTarget(missionPed) end
    local d = Config.DealerNpc
    dealerPed  = spawnStaticNpc(d.model, d.coords, d.heading); if dealerPed then addDealerNpcTarget(dealerPed) end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if missionPed and DoesEntityExist(missionPed) then DeleteEntity(missionPed) end
    if dealerPed and DoesEntityExist(dealerPed) then DeleteEntity(dealerPed) end
    if corpseZoneId then exports.ox_target:removeZone(corpseZoneId); corpseZoneId = nil end
    TriggerEvent('outlaw_organ:clearTarget')
end)

-- INVENTAIRE : Tooltip + Inspect
CreateThread(function()
    if exports and exports.ox_inventory and exports.ox_inventory.displayMetadata then
        exports.ox_inventory:displayMetadata({
            quality = 'Qualité',
            expires = 'Expire'
        })
    end
end)

exports('inspectOrgan', function(data, slot)
    local m = slot and slot.metadata or {}
    local now = os.time()
    local born = tonumber(m.born or now)
    local ttl  = tonumber(m.ttl or 600)
    local q0   = tonumber(m.quality or 100)
    local exp = tonumber(m.expires or (born + ttl))
    local remain = math.max(0, math.floor(exp - now))

    local q = 10
    if remain > 0 and ttl > 0 then
        local ratio = remain / ttl
        q = math.max(10, math.min(100, math.floor(q0 * ratio)))
    end

    local function fmt(sec)
        sec = math.max(0, math.floor(sec))
        local mm = math.floor(sec / 60)
        local ss = sec % 60
        return string.format('%02d:%02d', mm, ss)
    end

    lib.notify({
        title = 'Inspection',
        description = ('Qualité actuelle: %d%%\nTemps restant: %s'):format(q, fmt(remain)),
        type = (remain > 0 and 'inform' or 'error')
    })
end)
