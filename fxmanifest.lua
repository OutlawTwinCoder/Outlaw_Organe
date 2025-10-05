fx_version 'cerulean'
game 'gta5'

lua54 'yes'

author 'OutlawTwinCoder'
description 'Illegal organ harvest missions with decay/quality, multi-harvest, heat, witnesses & dispatch + inventory tooltip/inspect + live durability bar'
version '1.3.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

dependencies {
    'ox_lib',
    'ox_target',
    'ox_inventory',
    'es_extended'
}

client_export 'inspectOrgan'
