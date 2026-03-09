local cameraItem = Config.CameraItem or 'dslr_camera'
local KVP_PREFIX = 'crash_dslrcamera_cam_'
local MAX_FOLDERS = 3

local function getCameraSlot(source)
  local inv = exports.ox_inventory:GetInventory(source)
  if not inv or not inv.items then return nil end
  for slot, item in pairs(inv.items) do
    if type(item) == 'table' and item.name == cameraItem then
      return slot
    end
  end
  return nil
end

local function resolveSlot(source, slot)
  if type(slot) == 'number' and slot > 0 then return slot end
  return getCameraSlot(source)
end

local function ensureFolders(data)
  if type(data.folders) == 'table' and #data.folders > 0 then
    data.default_folder = type(data.default_folder) == 'number' and math.max(1, math.min(data.default_folder, #data.folders)) or 1
    return
  end
  data.folders = { { name = 'Default', photos = {} } }
  data.default_folder = 1
end

local function getCameraData(source, slot)
  if not source or source < 1 then return nil end
  local s = resolveSlot(source, slot)
  if not s then return nil end
  local key = KVP_PREFIX .. tostring(source) .. '_' .. tostring(s)
  local raw = GetResourceKvpString(key)
  if raw and raw ~= '' then
    local ok, data = pcall(json.decode, raw)
    if ok and type(data) == 'table' then
      ensureFolders(data)
      return data
    end
  end
  local data = { folders = { { name = 'Default', photos = {} } }, default_folder = 1 }
  SetResourceKvp(key, json.encode(data))
  return data
end

local function setCameraData(source, slot, data)
  if not source or source < 1 or not data then return end
  local s = resolveSlot(source, slot)
  if not s then return end
  SetResourceKvp(KVP_PREFIX .. tostring(source) .. '_' .. tostring(s), json.encode(data))
end

lib.callback.register('crash_dslrcamera:getServerTime', function(source)
  local ts = os.time()
  local t = os.date('*t', ts)
  local monthNames = { 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec' }
  local day = t.day or 1
  local ord = tostring(day)
  if day >= 11 and day <= 13 then ord = ord .. 'th'
  elseif day % 10 == 1 then ord = ord .. 'st'
  elseif day % 10 == 2 then ord = ord .. 'nd'
  elseif day % 10 == 3 then ord = ord .. 'rd'
  else ord = ord .. 'th' end
  return {
    timestamp = tostring(ts),
    date_formatted = ord .. ' of ' .. (monthNames[t.month or 1] or ''),
    time_string = os.date('%H:%M', ts),
  }
end)

lib.callback.register('crash_dslrcamera:getCameraHasSdCard', function(source)
  return getCameraSlot(source) ~= nil
end)

lib.callback.register('crash_dslrcamera:getSdCardPhotos', function(source, folderIndex, slot)
  if resolveSlot(source, slot) == nil then return {} end
  local data = getCameraData(source, slot)
  if not data then return {} end
  local idx = type(folderIndex) == 'number' and folderIndex or data.default_folder
  if idx < 1 or idx > #data.folders then idx = data.default_folder end
  local folder = data.folders[idx]
  return type(folder) == 'table' and type(folder.photos) == 'table' and folder.photos or {}
end)

lib.callback.register('crash_dslrcamera:getSdCardFolders', function(source, slot)
  if resolveSlot(source, slot) == nil then return { folders = {}, default_folder = 1 } end
  local data = getCameraData(source, slot)
  if not data then return { folders = {}, default_folder = 1 } end
  local list = {}
  for i, f in ipairs(data.folders) do
    list[#list + 1] = { name = type(f.name) == 'string' and f.name or ('Folder %d'):format(i), index = i }
  end
  return { folders = list, default_folder = data.default_folder or 1 }
end)

lib.callback.register('crash_dslrcamera:getCameraSdLabel', function(source)
  return 'CAM'
end)

lib.callback.register('crash_dslrcamera:getScreenshotUploadUrl', function()
  local key = (ServerConfig and ServerConfig.FiveManageApiKey) or ''
  key = type(key) == 'string' and key:gsub('%s+', '') or ''
  if key == '' then return '' end
  return 'https://api.fivemanage.com/api/v3/file?apiKey=' .. key
end)

local function sendDiscordLog(playerName, photoUrl, streetName, timeStr)
  if not Config.UseDiscordLogs then return end
  local webhook = ServerConfig and ServerConfig.DiscordWebhook
  if type(webhook) ~= 'string' or webhook == '' then return end
  pcall(function()
    local content = ('**DSLR Photo**\nPlayer: %s\nLocation: %s\nTime: %s\nURL: %s'):format(
      playerName or 'Unknown',
      streetName or '—',
      timeStr or '—',
      photoUrl or '—'
    )
    PerformHttpRequest(webhook, function() end, 'POST', json.encode({ content = content }), { ['Content-Type'] = 'application/json' })
  end)
end

RegisterNetEvent('crash_dslrcamera:addPhotoToSdCard', function(report, photoUrl, slot)
  local src = source
  if resolveSlot(src, slot) == nil then
    TriggerClientEvent('ox_lib:notify', src, { title = 'DSLR', description = 'No camera in inventory.', type = 'error' })
    return
  end
  local data = getCameraData(src, slot)
  if not data then return end
  local coords = report and report.coords
  local entry = {
    url = photoUrl or '',
    timestamp = report and report.timestamp or tostring(os.time()),
    date_formatted = report and report.date_formatted,
    time_string = report and report.time_string,
    street_name = report and report.street_name,
    coords = coords and { x = coords.x, y = coords.y, z = coords.z } or nil,
    ev_count = report and report.evidence_ids and #report.evidence_ids or 0,
  }
  local df = data.default_folder or 1
  if not data.folders[df] then data.folders[df] = { name = 'Default', photos = {} } end
  local photos = data.folders[df].photos
  if type(photos) ~= 'table' then data.folders[df].photos = {} photos = data.folders[df].photos end
  local maxPhotos = type(Config.MaxPhotosPerFolder) == 'number' and math.max(1, math.min(Config.MaxPhotosPerFolder, 200)) or 50
  while #photos >= maxPhotos do table.remove(photos, 1) end
  photos[#photos + 1] = entry
  setCameraData(src, slot, data)
  TriggerClientEvent('ox_lib:notify', src, { title = 'DSLR', description = 'Photo saved.', type = 'success' })
  sendDiscordLog(GetPlayerName(src), photoUrl, report and report.street_name, report and report.time_string)
end)

RegisterNetEvent('crash_dslrcamera:deletePhotoFromSd', function(folderIndex, photoIndex, slot)
  local src = source
  local data = getCameraData(src, slot)
  if not data then return end
  local fi = type(folderIndex) == 'number' and folderIndex or (data.default_folder or 1)
  if fi < 1 or fi > #data.folders then return end
  local photos = data.folders[fi].photos
  if type(photos) ~= 'table' or photoIndex < 1 or photoIndex > #photos then return end
  table.remove(photos, photoIndex)
  setCameraData(src, slot, data)
  TriggerClientEvent('ox_lib:notify', src, { title = 'DSLR', description = 'Photo deleted.', type = 'inform' })
end)

RegisterNetEvent('crash_dslrcamera:movePhotoToFolder', function(fromFolderIndex, photoIndex, toFolderIndex, slot)
  local src = source
  local data = getCameraData(src, slot)
  if not data then return end
  local folders = data.folders
  if fromFolderIndex < 1 or fromFolderIndex > #folders or toFolderIndex < 1 or toFolderIndex > #folders then return end
  local fromPhotos = folders[fromFolderIndex].photos
  if type(fromPhotos) ~= 'table' or photoIndex < 1 or photoIndex > #fromPhotos then return end
  local photo = table.remove(fromPhotos, photoIndex)
  if type(folders[toFolderIndex].photos) ~= 'table' then folders[toFolderIndex].photos = {} end
  folders[toFolderIndex].photos[#folders[toFolderIndex].photos + 1] = photo
  setCameraData(src, slot, data)
  TriggerClientEvent('ox_lib:notify', src, { title = 'DSLR', description = 'Photo moved to folder.', type = 'success' })
end)

RegisterNetEvent('crash_dslrcamera:setDefaultFolder', function(folderIndex, slot)
  local src = source
  local data = getCameraData(src, slot)
  if not data or folderIndex < 1 or folderIndex > #data.folders then return end
  data.default_folder = folderIndex
  setCameraData(src, slot, data)
  TriggerClientEvent('ox_lib:notify', src, { title = 'DSLR', description = 'Default folder set.', type = 'success' })
end)

RegisterNetEvent('crash_dslrcamera:createFolder', function(name, slot)
  local src = source
  local data = getCameraData(src, slot)
  if not data then return end
  if #data.folders >= MAX_FOLDERS then
    TriggerClientEvent('ox_lib:notify', src, { title = 'DSLR', description = 'Maximum ' .. tostring(MAX_FOLDERS) .. ' folders allowed.', type = 'error' })
    return
  end
  local n = type(name) == 'string' and name:gsub('^%s+', ''):gsub('%s+$', '') or 'New folder'
  if n == '' then n = 'New folder' end
  data.folders[#data.folders + 1] = { name = n, photos = {} }
  setCameraData(src, slot, data)
  TriggerClientEvent('ox_lib:notify', src, { title = 'DSLR', description = 'Folder created.', type = 'success' })
end)

RegisterNetEvent('crash_dslrcamera:deleteFolder', function(folderIndex, slot)
  local src = source
  local data = getCameraData(src, slot)
  if not data or #data.folders <= 1 then
    TriggerClientEvent('ox_lib:notify', src, { title = 'DSLR', description = 'Cannot delete the only folder.', type = 'error' })
    return
  end
  local fi = type(folderIndex) == 'number' and folderIndex or 1
  if fi < 1 or fi > #data.folders then return end
  table.remove(data.folders, fi)
  if data.default_folder > #data.folders then data.default_folder = #data.folders end
  if data.default_folder < 1 then data.default_folder = 1 end
  setCameraData(src, slot, data)
  TriggerClientEvent('ox_lib:notify', src, { title = 'DSLR', description = 'Folder deleted.', type = 'inform' })
end)

RegisterNetEvent('crash_dslrcamera:requestOpenCamera', function()
  local src = source
  if src and src > 0 then TriggerClientEvent('crash_dslrcamera:useDslrCamera', src) end
end)

exports('HandleCameraUse', function(event, item, inventory, slot, data)
  local src = source
  if not src or src < 1 then src = inventory and inventory.id end
  if src < 1 then return end
  if event == 'usingItem' then
    TriggerClientEvent('crash_dslrcamera:useDslrCamera', src, slot)
    return false
  end
end)

exports('UseDslrCamera', function(event, item, inventory, slot, data)
  local src = source
  if not src or src < 1 then src = inventory and inventory.id end
  if src and src > 0 then
    TriggerClientEvent('crash_dslrcamera:useDslrCamera', src)
  end
end)
