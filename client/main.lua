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

local dealerMenuId = 'outlaw_organ:dealerMenu'
local dealerDeliveryMenuId = 'outlaw_organ:dealerDeliveries'

local function openDeliveriesMenu(deliveries)
    local options = {}
    if deliveries and #deliveries > 0 then
        for _, entry in ipairs(deliveries) do
            table.insert(options, {
                title = entry.label or entry.name,
                description = ('Livré: %d'):format(entry.count or 0),
                disabled = true
            })
        end
    else
        options[1] = {
            title = 'Aucune livraison',
            description = 'Le dealer attend encore tes premiers organes.',
            disabled = true
        }
    end

    lib.registerContext({
        id = dealerDeliveryMenuId,
        title = 'Historique des livraisons',
        options = options
    })
    lib.showContext(dealerDeliveryMenuId)
end

local function openDealerMenu()
    local stats = lib.callback.await('outlaw_organ:getDealerStats', false)
    if not stats then
        return lib.notify({title='Organes', description='Impossible de récupérer les données du dealer.', type='error'})
    end

    local priceBonusPercent = math.floor(((stats.priceBonus or 0) * 1000) + 0.5) / 10
    local metadata = {
        { label = 'Réputation', value = stats.reputation or 0 },
        { label = 'Contrats', value = stats.contracts or 0 },
        { label = 'Bonus prix', value = ('+%.1f%%'):format(priceBonusPercent) }
    }

    if stats.nextRare then
        table.insert(metadata, { label = 'Prochain rare', value = ('%s (%d RP)'):format(stats.nextRare.label, stats.nextRare.required) })
    else
        table.insert(metadata, { label = 'Commandes rares', value = 'Toutes débloquées' })
    end

    local options = {
        {
            title = 'Profil vendeur',
            icon = 'fa-solid fa-chart-line',
            description = 'Suivi de ta réputation auprès du courtier.',
            metadata = metadata,
            disabled = true
        },
        {
            title = 'Vendre mes organes',
            icon = 'fa-solid fa-hand-holding-dollar',
            onSelect = function()
                TriggerServerEvent('outlaw_organ:sellOrgans')
            end
        },
        {
            title = 'Journal des livraisons',
            icon = 'fa-solid fa-box-archive',
            onSelect = function()
                openDeliveriesMenu(stats.deliveries or {})
            end
        }
    }

    local deliveredMap = {}
    for _, entry in ipairs(stats.deliveries or {}) do
        deliveredMap[entry.name] = entry
    end

    if stats.tiers then
        for _, tier in ipairs(stats.tiers) do
            local tierMeta = {
                { label = 'Prix', value = ('$' .. (tier.price or 0)) }
            }
            if tier.reputation and tier.reputation > 0 then
                table.insert(tierMeta, { label = 'Réputation', value = ('%d/%d'):format(stats.reputation or 0, tier.reputation) })
            end
            if tier.requires then
                for item, needed in pairs(tier.requires) do
                    local info = deliveredMap[item]
                    local have = info and info.count or 0
                    local label = (info and info.label) or item
                    table.insert(tierMeta, { label = label, value = ('%d/%d'):format(have, needed) })
                end
            end

            local description = tier.description or ''
            if tier.owned then
                description = description .. '\n✔ Déjà possédé'
            end
            if tier.available then
                description = description .. '\nDisponible pour achat.'
            else
                if tier.reputation and tier.reputation > 0 and not tier.meetsRep then
                    description = description .. ('\n❌ Réputation %d requise'):format(tier.reputation)
                end
                if tier.missing and #tier.missing > 0 then
                    for _, missing in ipairs(tier.missing) do
                        description = description .. ('\n❌ %s %d/%d'):format(missing.label or missing.item, missing.have or 0, missing.need or 0)
                    end
                end
            end

            table.insert(options, {
                title = tier.label or tier.name,
                icon = 'fa-solid fa-scalpel',
                description = description,
                metadata = tierMeta,
                disabled = not tier.available,
                onSelect = function()
                    TriggerServerEvent('outlaw_organ:buyTool', tier.name)
                end
            })
        end
    end

    table.insert(options, {
        title = ('Acheter %s (consommable)'):format(Config.Scalpel.kit),
        icon = 'fa-solid fa-kit-medical',
        description = 'Trousse chirurgicale à usage unique pour ralentir la décomposition.',
        onSelect = function()
            TriggerServerEvent('outlaw_organ:buyTool', 'kit')
        end
    })

    lib.registerContext({
        id = dealerMenuId,
        title = 'Marché clandestin',
        options = options
    })
    lib.showContext(dealerMenuId)
end

local function addDealerNpcTarget(ped)
    exports.ox_target:addLocalEntity(ped, {{
        icon = 'fa-solid fa-user-nurse',
        label = 'Parler au dealer',
        distance = 2.0,
        onSelect = function()
            openDealerMenu()
        end
    }})
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
