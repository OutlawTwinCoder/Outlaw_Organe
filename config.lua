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
    rein  = { label = 'Rein',   price = 400, limit = 1, rep = 8,  unlockReputation = 0 },
    crane = { label = 'Crâne',  price = 150, limit = 1, rep = 4,  unlockReputation = 0 },
    pied  = { label = 'Pied',   price = 200, limit = 1, rep = 5,  unlockReputation = 0 },
    yeux  = { label = 'Yeux',   price = 250, limit = 2, rep = 6,  unlockReputation = 120 },
    organe= { label = 'Organe', price = 350, limit = 1, rep = 7,  unlockReputation = 0 },
    coeur = { label = 'Cœur',   price = 900, limit = 1, rep = 18, unlockReputation = 320 },
    os    = { label = 'Os',     price = 20,  limit = 4, rep = 1,  unlockReputation = 0 },
}

Config.Reputation = {
    Max = 2000,
    BaseGainPerItem = 3,
    QualityWeight = 0.25,
    ContractBonus = 25,
    Tiers = {
        { name = 'Recrue',        reputation = 0,   multiplier = 1.0 },
        { name = 'Complice',      reputation = 120, multiplier = 1.1 },
        { name = 'Dissecteur',    reputation = 320, multiplier = 1.25 },
        { name = 'Chirurgien',    reputation = 620, multiplier = 1.4 },
        { name = 'Légende',       reputation = 1100, multiplier = 1.6 },
    },
    RareOrders = {
        coeur = { reputation = 320 },
    }
}

Config.MissionCooldown = 300

-- Progression des contrats de mission (débloque la pool d'organes et les missions ciblées)
Config.MissionBoard = {
    DefaultTimeLimit = 15 * 60,
    Contracts = {
        os = {
            label = 'Commande osseuse',
            item = 'os',
            order = 1,
            description = 'Ramasser des os frais pour alimenter la chaîne clandestine.',
            timeLimit = 10 * 60,
            fee = 0,
            reputation = 0,
            deliveries = {},
            bonusReputation = 6
        },
        pied = {
            label = 'Commande pédestre',
            item = 'pied',
            order = 2,
            description = 'Fournir des pieds propres pour les trafiquants.',
            timeLimit = 12 * 60,
            fee = 250,
            reputation = 80,
            deliveries = { os = 50 },
            bonusReputation = 10
        },
        crane = {
            label = 'Commande crânienne',
            item = 'crane',
            order = 3,
            description = 'Collecter des boîtes crâniennes intactes.',
            timeLimit = 12 * 60,
            fee = 350,
            reputation = 120,
            deliveries = { os = 75, pied = 40 },
            bonusReputation = 12
        },
        yeux = {
            label = 'Commande oculaire',
            item = 'yeux',
            order = 4,
            description = 'Livrer des yeux sans tache ni éraflure.',
            timeLimit = 14 * 60,
            fee = 450,
            reputation = 180,
            deliveries = { os = 110, pied = 65, crane = 30 },
            bonusReputation = 14
        },
        organe = {
            label = 'Commande viscérale',
            item = 'organe',
            order = 5,
            description = 'Acheminer des organes internes utilisables.',
            timeLimit = 14 * 60,
            fee = 550,
            reputation = 220,
            deliveries = { os = 140, pied = 85, crane = 45, yeux = 25 },
            bonusReputation = 16
        },
        rein = {
            label = 'Commande rénale',
            item = 'rein',
            order = 6,
            description = 'Prélever un rein prêt pour la transplantation.',
            timeLimit = 15 * 60,
            fee = 700,
            reputation = 320,
            deliveries = { os = 180, pied = 120, crane = 70, yeux = 40, organe = 20 },
            bonusReputation = 20
        },
        coeur = {
            label = 'Commande cardiaque',
            item = 'coeur',
            order = 7,
            description = 'Assurer un cœur vibrant livré dans les temps.',
            timeLimit = 16 * 60,
            fee = 900,
            reputation = 420,
            deliveries = { os = 220, pied = 160, crane = 110, yeux = 60, rein = 30 },
            bonusReputation = 25
        }
    }
}

Config.Scalpel = {
    kit   = 'surgery_kit',
    kitExtraSeconds  = 180,
    variants = {
        basic = { item = 'scalpel',      label = 'Scalpel (basique)', bonusQuality = 0,  buyPrice = 250,  reputation = 0,   secondHarvestChance = 0.0 },
        pro   = { item = 'scalpel_pro',  label = 'Scalpel (pro)',     bonusQuality = 10, buyPrice = 1500, reputation = 120, secondHarvestChance = 0.2 },
        elite = { item = 'scalpel_elite',label = 'Scalpel (élite)',   bonusQuality = 18, buyPrice = 5500, reputation = 380, secondHarvestChance = 0.35 },
    },
    upgrades = {
        elite = {
            id = 'elite',
            from = 'pro',
            to = 'elite',
            price = 0,
            reputation = 380,
            deliveries = { rein = 20, yeux = 12, coeur = 3 },
        }
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
