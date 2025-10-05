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

local function formatDeliveryMetadata(itemDetails, delivered)
    local rows = {}
    for name, info in pairs(itemDetails) do
        local label = info.label or name
        table.insert(rows, { label = label, value = tostring(delivered[name] or 0) })
    end
    table.sort(rows, function(a, b) return a.label < b.label end)
    return rows
end

local function openDealerMenu()
    lib.callback('outlaw_organ:getDealerData', false, function(data)
        if not data then
            return lib.notify({ title = 'Revendeur', description = 'Impossible d’obtenir les informations du marché.', type = 'error' })
        end

        local bonusPercent = math.floor(((data.multiplier or 1.0) - 1.0) * 100 + 0.5)
        if bonusPercent < 0 then bonusPercent = 0 end

        local statsMetadata = {
            { label = 'Rang', value = ('%s (x%.2f)'):format(data.tierLabel or 'Novice', data.multiplier or 1.0) },
            { label = 'Réputation', value = ('%d pts'):format(data.reputation or 0) },
            { label = 'Qualité livrée', value = ('%d'):format(data.totalQuality or 0) },
            { label = 'Contrats terminés', value = tostring(data.contracts or 0) }
        }
        if data.nextTier then
            table.insert(statsMetadata, { label = 'Prochain rang', value = ('%s dans %d pts'):format(data.nextTier.label or '?', data.nextTier.remaining or 0) })
        end

        local deliveryMetadata = formatDeliveryMetadata(data.itemDetails or Config.ItemDetails, data.delivered or {})

        lib.registerContext({
            id = 'outlaw_organ_dealer_stats',
            title = 'Tableau de réputation',
            menu = 'outlaw_organ_dealer_main',
            options = {
                {
                    title = 'Résumé',
                    icon = 'fa-solid fa-chart-line',
                    metadata = statsMetadata
                },
                {
                    title = 'Livraisons cumulées',
                    icon = 'fa-solid fa-table-list',
                    metadata = deliveryMetadata
                }
            }
        })

        local scalpelLabels = {
            basic = 'Scalpel basique',
            pro = 'Scalpel professionnel'
        }

        local upgradeOptions = {}
        local delivered = data.delivered or {}

        for kind, state in pairs(data.upgrades or {}) do
            local currentTier = state.current or 0
            local currentLabel = currentTier > 0 and (state.tiers[currentTier] and state.tiers[currentTier].label) or 'Aucune amélioration'
            table.insert(upgradeOptions, {
                title = scalpelLabels[kind] or kind,
                description = ('Niveau actuel: %s'):format(currentLabel),
                icon = 'fa-solid fa-screwdriver-wrench',
                menu = 'outlaw_organ_dealer_upgrades_' .. kind
            })

            local tierOptions = {}
            for _, tier in ipairs(state.tiers or {}) do
                local requirementsText = {}
                for item, needed in pairs(tier.organs or {}) do
                    local info = (data.itemDetails or Config.ItemDetails)[item] or {}
                    local label = info.label or item
                    table.insert(requirementsText, ('%s: %d/%d'):format(label, delivered[item] or 0, needed))
                end
                if #requirementsText == 0 then
                    requirementsText[1] = 'Aucune exigence de livraison'
                end

                local metadata = {
                    { label = 'Réputation requise', value = ('%d pts'):format(tier.reputation or 0) },
                    { label = 'Bonus qualité', value = ('+%d%%'):format(tier.bonusQuality or 0) }
                }
                if (tier.bonusTTL or 0) > 0 then
                    table.insert(metadata, { label = 'Conservation', value = ('+%ds'):format(tier.bonusTTL) })
                end
                table.insert(metadata, { label = 'Livraisons', value = table.concat(requirementsText, '\n') })

                local statusLabel
                local available = false
                if (state.current or 0) >= tier.index then
                    statusLabel = 'Débloqué'
                elseif tier.index == (state.current or 0) + 1 then
                    local enoughRep = (data.reputation or 0) >= (tier.reputation or 0)
                    local enoughDeliveries = true
                    for item, needed in pairs(tier.organs or {}) do
                        if (delivered[item] or 0) < needed then enoughDeliveries = false break end
                    end
                    if enoughRep and enoughDeliveries then
                        statusLabel = 'Disponible'
                        available = true
                    else
                        statusLabel = 'Verrouillé'
                    end
                else
                    statusLabel = 'Verrouillé'
                end

                table.insert(metadata, { label = 'Statut', value = statusLabel })

                table.insert(tierOptions, {
                    title = tier.label,
                    description = tier.description,
                    icon = 'fa-solid fa-wrench',
                    metadata = metadata,
                    disabled = not available,
                    onSelect = function()
                        lib.callback('outlaw_organ:upgradeScalpel', false, function(success, message)
                            if success then
                                lib.notify({ title = 'Atelier', description = ('Amélioration débloquée: %s'):format(message or tier.label), type = 'success' })
                                Wait(150)
                                openDealerMenu()
                            else
                                lib.notify({ title = 'Atelier', description = message or 'Action impossible', type = 'error' })
                            end
                        end, kind)
                    end
                })
            end

            lib.registerContext({
                id = 'outlaw_organ_dealer_upgrades_' .. kind,
                title = scalpelLabels[kind] or kind,
                menu = 'outlaw_organ_dealer_upgrades',
                options = (#tierOptions > 0 and tierOptions or {{ title = 'Aucune amélioration', disabled = true, icon = 'fa-solid fa-ban' }})
            })
        end

        if #upgradeOptions == 0 then
            upgradeOptions[1] = { title = 'Aucune amélioration disponible', disabled = true, icon = 'fa-solid fa-circle-xmark' }
        end

        lib.registerContext({
            id = 'outlaw_organ_dealer_upgrades',
            title = 'Atelier des scalpels',
            menu = 'outlaw_organ_dealer_main',
            options = upgradeOptions
        })

        lib.registerContext({
            id = 'outlaw_organ_dealer_main',
            title = 'Revendeur clandestin',
            options = {
                {
                    title = 'Vendre mes organes',
                    description = ('Bonus actuel: +%d%%'):format(bonusPercent),
                    icon = 'fa-solid fa-hand-holding-dollar',
                    serverEvent = 'outlaw_organ:sellOrgans',
                    arrow = false
                },
                {
                    title = 'Réputation & statistiques',
                    icon = 'fa-solid fa-chart-column',
                    menu = 'outlaw_organ_dealer_stats'
                },
                {
                    title = ('Acheter %s'):format(Config.Scalpel.basic),
                    description = ('$%d'):format((data.scalpelPrices and data.scalpelPrices.basic) or 0),
                    icon = 'fa-solid fa-scalpel',
                    serverEvent = 'outlaw_organ:buyTool',
                    args = 'basic'
                },
                {
                    title = ('Acheter %s'):format(Config.Scalpel.pro),
                    description = ('$%d'):format((data.scalpelPrices and data.scalpelPrices.pro) or 0),
                    icon = 'fa-solid fa-screwdriver-wrench',
                    serverEvent = 'outlaw_organ:buyTool',
                    args = 'pro'
                },
                {
                    title = ('Acheter %s'):format(Config.Scalpel.kit),
                    description = ('$%d'):format((data.scalpelPrices and data.scalpelPrices.kit) or 0),
                    icon = 'fa-solid fa-kit-medical',
                    serverEvent = 'outlaw_organ:buyTool',
                    args = 'kit'
                },
                {
                    title = 'Atelier des scalpels',
                    icon = 'fa-solid fa-hammer',
                    menu = 'outlaw_organ_dealer_upgrades'
                }
            }
        })

        lib.showContext('outlaw_organ_dealer_main')
    end)
end

local function addDealerNpcTarget(ped)
    exports.ox_target:addLocalEntity(ped, {
        {
            icon = 'fa-solid fa-handshake-simple',
            label = 'Parler au revendeur',
            distance = 2.0,
            onSelect = function(_) openDealerMenu() end
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
