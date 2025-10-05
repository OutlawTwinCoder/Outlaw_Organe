return {
    -- OUTLAW ORGAN TOOLS
    ['scalpel'] = { label='Scalpel', weight=50, stack=true, close=true },
    ['scalpel_pro'] = { label='Scalpel Pro', weight=50, stack=true, close=true, description='+10% qualité, 2e prélèvement possible' },
    ['surgery_kit'] = { label='Kit chirurgical', weight=200, stack=true, close=true, description='+TTL (consommable)' },
    ['cooler'] = { label='Glacière', weight=600, stack=false, close=true },
    ['icepack'] = { label='Pack de glace', weight=100, stack=true, close=true },
    ['gants'] = { label='Gants', weight=10, stack=true, close=true },

    -- ORGANS
    ['rein'] = { label='Rein', weight=200, stack=true, close=true, client={ export='Outlaw_OrganHarvest.inspectOrgan' } },
    ['crane'] = { label='Crâne', weight=300, stack=true, close=true, client={ export='Outlaw_OrganHarvest.inspectOrgan' } },
    ['pied'] = { label='Pied', weight=250, stack=true, close=true, client={ export='Outlaw_OrganHarvest.inspectOrgan' } },
    ['yeux'] = { label='Yeux', weight=80, stack=true, close=true, client={ export='Outlaw_OrganHarvest.inspectOrgan' } },
    ['organe'] = { label='Organe', weight=150, stack=true, close=true, client={ export='Outlaw_OrganHarvest.inspectOrgan' } },
    ['coeur'] = { label='Cœur', weight=120, stack=true, close=true, client={ export='Outlaw_OrganHarvest.inspectOrgan' } },
    ['os'] = { label='Os', weight=60, stack=true, close=true, client={ export='Outlaw_OrganHarvest.inspectOrgan' } },
}
