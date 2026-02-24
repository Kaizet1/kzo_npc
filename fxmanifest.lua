fx_version('cerulean')
games({ 'gta5' })

name 'kzo_npcdialog'
description 'Hệ thống NPC hội thoại - NPC Dialogue System'
author 'KzO Exclusives (https://discord.gg/Kvwxjebdp4)'
version '1.0.0'

client_scripts({
    '@ox_lib/init.lua',
    'config.lua',
    'client/*',
})

dependencies({
    'ox_lib',
    'kzo_ui',
})

lua54 'yes'
