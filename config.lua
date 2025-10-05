Config = {}

Config.DiscordWebhook = "REPLACE_ME"

Config.MissionNpc = {
    model = 'a_m_m_farmer_01',
    coords = vector3(2180.5330, 3497.6675, 44.4864),
    heading = 39.1055
}

Config.DealerNpc = {
    model = 'a_m_y_business_01',
    coords = vector3(3559.8201, 3674.5522, 28.1219),
    heading = 169.527
}

Config.SpawnZones = {
    vector3(-1312.7555, -1361.5681, 4.5177),
    vector3(1125.4896, -479.2893, 65.9640),
    vector3(1239.4215, -511.8290, 69.2385),
    vector3(1216.6670, -417.6181, 67.7202),
    vector3(450.5364, -864.3065, 28.0955),
    vector3(-306.1215, -128.5467, 45.8041),
    vector3(-1274.3179, 315.5086, 65.511),
    vector3(-608.9398, 771.0920, 188.5101),
    vector3(1231.5182, 1858.0808, 79.2012),
    vector3(1590.9747, 3592.1724, 38.7030),
    vector3(1942.0649, 3845.1641, 35.3871),
    vector3(1392.1718, 3605.1086, 38.9419),
    vector3(1704.3462, 4826.0391, 42.0202),
    vector3(-149.9705, 6310.4565, 31.3904),
}

Config.ItemDetails = {
    rein  = { label = 'Rein',    price = 400, limit = 1 },
    crane = { label = 'Crâne',   price = 150, limit = 1 },
    pied  = { label = 'Pied',    price = 200, limit = 1 },
    yeux  = { label = 'Yeux',    price = 250, limit = 2 },
    organe= { label = 'Organe',  price = 350, limit = 1 },
    coeur = { label = 'Cœur',    price = 800, limit = 1 },
    os    = { label = 'Os',      price = 20,  limit = 4 },
}

Config.MissionCooldown = 300

Config.Scalpel = {
    basic = 'scalpel',
    pro   = 'scalpel_pro',
    kit   = 'surgery_kit',
    proQualityBonus = 10,
    kitExtraSeconds  = 180
}

Config.ScalpelTiers = {
    basic = {
        item = 'scalpel',
        label = 'Scalpel (basique)',
        price = 250,
        reputation = 0,
        requires = {},
        qualityBonus = 0,
        secondHarvestChance = 0.0,
        description = 'Outil standard fourni sans condition.'
    },
    pro = {
        item = 'scalpel_pro',
        label = 'Scalpel (pro)',
        price = 1500,
        reputation = 35,
        requires = { rein = 8, yeux = 4 },
        qualityBonus = 10,
        secondHarvestChance = Config.SecondHarvestChance or 0.17,
        description = 'Améliore la qualité des prélèvements et ouvre la voie aux doubles récoltes.'
    },
    honed = {
        item = 'scalpel_honed',
        label = 'Scalpel affûté',
        price = 3200,
        reputation = 120,
        requires = { rein = 20, crane = 10, coeur = 3 },
        qualityBonus = 18,
        secondHarvestChance = 0.28,
        description = 'Version affûtée du scalpel, réservée aux vétérans au sang-froid.'
    }
}

Config.Reputation = {
    Max = 500,
    PriceBonusPerPoint = 0.0025, -- +0.25% par point
    MaxPriceBonus = 0.6,         -- Bonus max de +60%
    SaleQualityWeight = 0.08,    -- Influence de la qualité sur le gain de réput.
    SaleMinQuality = 40,         -- Qualité minimale pour générer de la réput.
    ContractBonus = 6,           -- Bonus fixe par contrat terminé
    RareOrders = {
        coeur = 110
    }
}

-- Base TTL (seconds) before organ rots (without any bonus)
Config.OrganDecaySeconds = 600
Config.CoolerItem  = 'cooler'
Config.CoolerBonusSeconds = 300
Config.IcepackItem = 'icepack'
Config.IcepackBonusSeconds = 120

Config.QualityByKill = {
  knife = 15,
  melee = 10,
  pistol = -15,
  rifle = -20,
  shotgun = -30,
  explosion = -50,
  vehicle = -40,
  other = 0
}

Config.SecondHarvestChance = 0.17

Config.Risk = {
  InfectionChanceNoGloves = 0.25,
  GlovesItem = 'gants',
  InfectionDuration = 600,
  InfectionSprintMultiplier = 0.9
}

Config.Heat = {
  Enable = true,
  AddOnHarvest = 20,
  DecayPerMinute = 5,
  DispatchThreshold = 50,
  DispatchCooldownSeconds = 90
}

Config.Witness = {
  Enable = true,
  Radius = 25.0,
  CallChance = 0.35
}

Config.PoliceJobs = { 'police' }
Config.PolicePing = {
  Duration = 60,
  BlipSprite = 153,
  BlipColor = 1
}

Config.UseBlackMoney = true

Config.BlipSprite = 153
Config.BlipColor  = 1

Config.TargetPedModels = {
    'a_m_m_eastsa_01', 'a_m_m_stlat_02', 'a_m_m_salton_01',
    'a_m_y_hipster_01', 'a_m_y_vinewood_01', 'a_m_y_beach_01',
    'a_f_y_hipster_02', 'a_f_y_bevhills_01', 'a_f_m_fatcult_01'
}
