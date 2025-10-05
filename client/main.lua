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

local dealerUiOpen = false

local function closeDealerUi()
    if not dealerUiOpen then return end
    SendNUIMessage({ action = 'closeDealer' })
    SetNuiFocus(false, false)
    dealerUiOpen = false
end

local function openDealerUi(data)
    if not data then return end
    SendNUIMessage({ action = 'openDealer', payload = data })
    SetNuiFocus(true, true)
    dealerUiOpen = true
end

RegisterNetEvent('outlaw_organ:openDealerMenu', function(data)
    openDealerUi(data)
end)

RegisterNetEvent('outlaw_organ:updateDealerMenu', function(data)
    if not data then return end
    if dealerUiOpen then
        SendNUIMessage({ action = 'updateDealer', payload = data })
    end
end)

RegisterNUICallback('dealer_close', function(_, cb)
    closeDealerUi()
    cb({})
end)

RegisterNUICallback('dealer_sell', function(_, cb)
    TriggerServerEvent('outlaw_organ:sellOrgans')
    cb({})
end)

RegisterNUICallback('dealer_buy', function(data, cb)
    if data and data.id then
        TriggerServerEvent('outlaw_organ:buyTool', data.id)
    end
    cb({})
end)

RegisterNUICallback('dealer_upgrade', function(data, cb)
    if data and data.id then
        TriggerServerEvent('outlaw_organ:upgradeScalpel', data.id)
    end
    cb({})
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    closeDealerUi()
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
