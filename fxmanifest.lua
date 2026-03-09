fx_version 'cerulean'
game 'gta5'

author 'Crash'
description 'Police tools - DSLR camera'
version '0.1.0'

lua54 'yes'

shared_scripts {
  '@ox_lib/init.lua',
  'config.lua',
}

server_scripts {
  'server/sv_config.lua',
  'server/sv_sdcard.lua',
}

client_scripts {
  'client/cl_camera.lua',
}

ui_page 'ui/index.html'

files {
  'ui/index.html',
  'ui/camera.png',
  'ui/style.css',
  'ui/script.js',
}

dependencies {
  'ox_lib',
  'ox_inventory',
  'screenshot-basic',
}
