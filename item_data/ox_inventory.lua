-- Items à copier dans ox_inventory/data/items.lua pour Outlaw_OrganHarvest
return {
    -- Scalpels et consommables
    ['scalpel'] = {
        label = 'Scalpel',
        weight = 50,
        stack = true,
        close = true,
        description = 'Instrument chirurgical basique'
    },
    ['scalpel_pro'] = {
        label = 'Scalpel Pro',
        weight = 50,
        stack = true,
        close = true,
        description = 'Affûtage renforcé pour de meilleures coupes'
    },
    ['scalpel_elite'] = {
        label = 'Scalpel Élite',
        weight = 50,
        stack = true,
        close = true,
        description = 'Lame modifiée, équilibre parfait'
    },
    ['surgery_kit'] = {
        label = 'Kit chirurgical',
        weight = 150,
        stack = true,
        close = true,
        description = 'Stérilisation et outils jetables'
    },

    -- Outils de conservation / sécurité
    ['cooler'] = {
        label = 'Glacière médicale',
        weight = 700,
        stack = false,
        close = true,
        description = 'Maintient les organes au frais plus longtemps'
    },
    ['icepack'] = {
        label = 'Pack de glace',
        weight = 150,
        stack = true,
        close = true,
        description = 'Bonus de conservation ponctuel'
    },
    ['gants'] = {
        label = 'Gants stériles',
        weight = 10,
        stack = true,
        close = true,
        description = 'Réduit les risques d\'infection'
    },

    -- Organes / pièces récoltées
    ['rein'] = {
        label = 'Rein',
        weight = 200,
        stack = true,
        close = true
    },
    ['crane'] = {
        label = 'Crâne',
        weight = 300,
        stack = true,
        close = true
    },
    ['pied'] = {
        label = 'Pied',
        weight = 250,
        stack = true,
        close = true
    },
    ['yeux'] = {
        label = 'Yeux',
        weight = 80,
        stack = true,
        close = true
    },
    ['organe'] = {
        label = 'Organe',
        weight = 150,
        stack = true,
        close = true
    },
    ['coeur'] = {
        label = 'Cœur',
        weight = 120,
        stack = true,
        close = true
    },
    ['os'] = {
        label = 'Os',
        weight = 60,
        stack = true,
        close = true
    }
}
