local missionPed, dealerPed
local activeTarget = {
    netId = nil,
    blip = nil
}

local function loadModel(model)
    if type(model) == 'string' then model = joaat(model) end
    if not IsModelInCdimage(model) then return false end
    RequestModel(model)
    local tries = 0
    while not HasModelLoaded(model) and tries < 100 do
        Wait(50); tries = tries + 1
    end
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
    exports.ox_target:addLocalEntity(ped, {
        {
            icon = 'fa-solid fa-briefcase-medical',
            label = 'Démarrer une mission',
            distance = 2.0,
            onSelect = function(_)
                TriggerServerEvent('outlaw_organ:startMission')
            end
        }
    })
end

local function addDealerNpcTarget(ped)
    exports.ox_target:addLocalEntity(ped, {
        {
            icon = 'fa-solid fa-hand-holding-dollar',
            label = 'Vendre mes organes',
            distance = 2.0,
            onSelect = function(_)
                TriggerServerEvent('outlaw_organ:sellOrgans')
            end
        },
        {
            icon = 'fa-solid fa-scalpel',
            label = ('Acheter un %s ($%s)'):format(Config.ScalpelItem, Config.ScalpelPrice),
            distance = 2.0,
            onSelect = function(_)
                TriggerServerEvent('outlaw_organ:buyScalpel')
            end
        }
    })
end

-- Reçoit l’assignation de cible (coords) depuis le serveur
RegisterNetEvent('outlaw_organ:missionAssigned', function(targetCoords)
    -- créer le ped cible côté client
    local model = Config.TargetPedModels[math.random(#Config.TargetPedModels)]
    if not loadModel(model) then
        lib.notify({title='Organes', description='Erreur de chargement du ped cible', type='error'})
        return
    end

    local ped = CreatePed(4, joaat(model), targetCoords.x, targetCoords.y, targetCoords.z - 1.0, 0.0, true, true)
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedSeeingRange(ped, 0.0)
    SetPedHearingRange(ped, 0.0)
    SetPedAlertness(ped, 0)
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_STAND_IMPATIENT', 0, true)

    local netId = NetworkGetNetworkIdFromEntity(ped)
    Entity(ped).state:set('organOwner', GetPlayerServerId(PlayerId()), true)

    -- Ajoute immédiatement l'option de prélèvement pour le client propriétaire.
    -- L'évènement entityCreated peut se déclencher avant que l'état soit défini,
    -- ce qui empêchait ox_target d'ajouter l'interaction.
    addTargetOptionToEntity(ped)

    -- blip/route
    if DoesBlipExist(activeTarget.blip) then RemoveBlip(activeTarget.blip) end
    local blip = AddBlipForEntity(ped)
    SetBlipSprite(blip, Config.BlipSprite)
    SetBlipColour(blip, Config.BlipColor)
    SetBlipRoute(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('Cible - Organe')
    EndTextCommandSetBlipName(blip)

    activeTarget.netId = netId
    activeTarget.blip = blip

    -- enregistre côté serveur
    TriggerServerEvent('outlaw_organ:registerTarget', netId, targetCoords)
    lib.notify({title='Organes', description='Cible assignée. Rejoins le point sur ta carte.', type='inform'})
end)

-- Supprime la cible (succès, abandon, déco)
RegisterNetEvent('outlaw_organ:clearTarget', function()
    if activeTarget.netId then
        local ped = NetworkGetEntityFromNetworkId(activeTarget.netId)
        if DoesEntityExist(ped) then
            DeleteEntity(ped)
        end
    end
    if DoesBlipExist(activeTarget.blip) then RemoveBlip(activeTarget.blip) end
    activeTarget.netId = nil
    activeTarget.blip = nil
end)

-- Ajoute l’option de prélèvement directement sur la cible via ox_target
local function addTargetOptionToEntity(ped)
    exports.ox_target:addLocalEntity(ped, {
        {
            icon = 'fa-solid fa-scalpel',
            label = 'Prélever un organe',
            distance = 1.8,
            canInteract = function(entity, distance, coords, name, bone)
                local owner = Entity(entity).state.organOwner
                return owner and owner == GetPlayerServerId(PlayerId()) and IsPedDeadOrDying(entity, true)
            end,
            onSelect = function(data)
                -- petite anim + progress côté client
                local ped = data.entity
                TaskTurnPedToFaceEntity(PlayerPedId(), ped, 500)
                Wait(500)
                local ok = lib.progressCircle({
                    duration = 7000,
                    position = 'bottom',
                    useWhileDead = false,
                    canCancel = true,
                    disable = { move = true, car = true, combat = true },
                    anim = { dict = 'amb@medic@standing@tendtodead@base', clip = 'base' },
                    label = 'Prélèvement en cours...'
                })
                if not ok then
                    lib.notify({title='Organes', description='Prélèvement annulé.', type='error'})
                    return
                end
                -- envoie au serveur pour vérification + récompense
                local netId = NetworkGetNetworkIdFromEntity(ped)
                TriggerServerEvent('outlaw_organ:harvest', netId)
            end
        }
    })
end

-- Quand on crée la cible, ajoute l’option ox_target
AddEventHandler('entityCreated', function(entity)
    if DoesEntityExist(entity) and IsEntityAPed(entity) then
        local owner = Entity(entity).state.organOwner
        if owner and owner == GetPlayerServerId(PlayerId()) then
            addTargetOptionToEntity(entity)
        end
    end
end)

-- Spawn des PNJ au démarrage
CreateThread(function()
    local m = Config.MissionNpc
    missionPed = spawnStaticNpc(m.model, m.coords, m.heading)
    if missionPed then addMissionNpcTarget(missionPed) end

    local d = Config.DealerNpc
    dealerPed = spawnStaticNpc(d.model, d.coords, d.heading)
    if dealerPed then addDealerNpcTarget(dealerPed) end
end)

-- Nettoyage si on redémarre la ressource
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if missionPed and DoesEntityExist(missionPed) then DeleteEntity(missionPed) end
    if dealerPed and DoesEntityExist(dealerPed) then DeleteEntity(dealerPed) end
    TriggerEvent('outlaw_organ:clearTarget')
end)
