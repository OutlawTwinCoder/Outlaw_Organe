Config = {}

-- URL du webhook Discord (remplace par le tien)
Config.DiscordWebhook = "REPLACE_ME" -- ⚠️ Mets ton URL webhook

-- PNJ Mission (donne une cible à récolter)
Config.MissionNpc = {
    model = 'a_m_m_farmer_01',
    coords = vector3(2180.5330, 3497.6675, 44.4864),
    heading = 39.1055
}

-- PNJ Dealer (achète les organes, vend un scalpel)
Config.DealerNpc = {
    model = 'a_m_y_business_01',
    coords = vector3(3559.8201, 3674.5522, 28.1219),
    heading = 169.527
}

-- Zones de spawn pour les cibles (un ped apparaît dans une de ces zones)
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

-- Prix & limites pour chaque item
Config.ItemDetails = {
    rein  = { price = 400, limit = 1 },
    crane = { price = 150, limit = 1 },
    pied  = { price = 200, limit = 1 },
    yeux  = { price = 250, limit = 1 },
    organe= { price = 350, limit = 1 },
    coeur = { price = 800, limit = 1 },
    os    = { price = 20,  limit = 1 },
}

-- Cooldown entre deux missions (secondes)
Config.MissionCooldown = 300

-- Item & prix du scalpel (vendu par le Dealer)
Config.ScalpelItem = 'scalpel'
Config.ScalpelPrice = 250

-- Réglages avancés
Config.BlipSprite = 153 -- Medical cross
Config.BlipColor  = 1   -- Red
Config.UseBlackMoney = true -- l’argent de la vente va en black_money si true, sinon en cash

-- Liste de modèles de peds possibles pour la cible
Config.TargetPedModels = {
    'a_m_m_eastsa_01', 'a_m_m_stlat_02', 'a_m_m_salton_01',
    'a_m_y_hipster_01', 'a_m_y_vinewood_01', 'a_m_y_beach_01',
    'a_f_y_hipster_02', 'a_f_y_bevhills_01', 'a_f_m_fatcult_01'
}
