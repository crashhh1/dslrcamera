local cameraActive  = false
local viewfinderMode = false
local currentCameraSlot = nil
local scriptedCam   = nil
local camFov = 35.0
local fovMin = 10.0
local scanRadius = 15.0
local shutterSound = 'Camera_Shoot'
local resName = GetCurrentResourceName()

local function fovToZoom(fov)
  if fov <= 0 then return 1.0 end
  return math.floor(fovMax / fov * 10 + 0.5) / 10
end

local function getStreetNameAtCoord(x, y, z)
  local h1, h2 = GetStreetNameAtCoord(x, y, z)
  local n1 = h1 and GetStreetNameFromHashKey(h1) or ''
  local n2 = h2 and GetStreetNameFromHashKey(h2) or ''
  if n1 == '' then return 'Unknown' end
  if n2 and n2 ~= '' and n2 ~= n1 then return n1 .. ' / ' .. n2 end
  return n1
end

local function getCameraVectors()
  local coord, rot
  if scriptedCam and DoesCamExist(scriptedCam) then
    coord = GetCamCoord(scriptedCam)
    rot   = GetCamRot(scriptedCam, 2)
  else
    coord = GetGameplayCamCoord()
    rot   = GetGameplayCamRot(2)
  end
  local rx, rz = math.rad(rot.x), math.rad(rot.z)
  local fx = -math.sin(rz) * math.cos(rx)
  local fy =  math.cos(rz) * math.cos(rx)
  local fz =  math.sin(rx)
  local len = math.sqrt(fx*fx + fy*fy + fz*fz)
  if len > 0.0001 then fx,fy,fz = fx/len,fy/len,fz/len else fx,fy,fz = 0,1,0 end
  return coord, vector3(fx, fy, fz)
end

local function buildReport()
  local coord, fwd = getCameraVectors()
  local list = {}
  local ok, L = pcall(function()
    return exports[resName]:GetEvidenceInCameraFOV(coord, fwd, camFov / 2, scanRadius)
  end)
  if ok and type(L) == 'table' then list = L end
  local ids = {}
  for _, e in ipairs(list) do ids[#ids+1] = e.id end
  local tsStr, dateFormatted, timeStr
  local timeOk, timeData = pcall(function()
    return lib.callback.await('crash_dslrcamera:getServerTime', false)
  end)
  if timeOk and type(timeData) == 'table' then
    tsStr = timeData.timestamp or tostring(GetGameTimer())
    dateFormatted = timeData.date_formatted or tsStr
    timeStr = timeData.time_string or '--:--'
  else
    tsStr = tostring(GetGameTimer())
    dateFormatted = tsStr
    timeStr = '--:--'
  end
  local streetName = getStreetNameAtCoord(coord.x, coord.y, coord.z)
  return {
    timestamp = tsStr,
    date_formatted = dateFormatted,
    time_string = timeStr,
    street_name = streetName,
    coords = { x = coord.x, y = coord.y, z = coord.z },
    evidence_ids = ids,
    evidence_detected = list,
  }
end

local function forwardFromRot(rot)
  local rx, rz = math.rad(rot.x), math.rad(rot.z)
  local fx = -math.sin(rz) * math.cos(rx)
  local fy =  math.cos(rz) * math.cos(rx)
  local fz =  math.sin(rx)
  local len = math.sqrt(fx*fx + fy*fy + fz*fz)
  if len > 0.0001 then fx,fy,fz = fx/len,fy/len,fz/len else fx,fy,fz = 0,1,0 end
  return vector3(fx, fy, fz)
end

local VIEWFINDER_OFFSET = 0.35

local function syncCam()
  if not scriptedCam or not DoesCamExist(scriptedCam) then return end
  local gc = GetGameplayCamCoord()
  local gr = GetGameplayCamRot(2)
  local fwd = forwardFromRot(gr)
  local cx = gc.x + fwd.x * VIEWFINDER_OFFSET
  local cy = gc.y + fwd.y * VIEWFINDER_OFFSET
  local cz = gc.z + fwd.z * VIEWFINDER_OFFSET
  SetCamCoord(scriptedCam, cx, cy, cz)
  SetCamRot(scriptedCam,   gr.x, gr.y, gr.z, 2)
  SetCamFov(scriptedCam,   camFov)
end

local function destroyCam()
  if scriptedCam and DoesCamExist(scriptedCam) then
    RenderScriptCams(false, false, 0, true, true)
    DestroyCam(scriptedCam, false)
    scriptedCam = nil
  end
end

local function setViewfinderMode(on)
  viewfinderMode = on
  if on then
    SetFollowPedCamViewMode(4)
    Wait(50)
    local gc = GetGameplayCamCoord()
    local gr = GetGameplayCamRot(2)
    local fwd = forwardFromRot(gr)
    scriptedCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(scriptedCam, gc.x + fwd.x * VIEWFINDER_OFFSET, gc.y + fwd.y * VIEWFINDER_OFFSET, gc.z + fwd.z * VIEWFINDER_OFFSET)
    SetCamRot(scriptedCam,   gr.x, gr.y, gr.z, 2)
    SetCamFov(scriptedCam,   camFov)
    SetCamActive(scriptedCam, true)
    RenderScriptCams(true, false, 0, true, true)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'enterViewfinder', zoom = fovToZoom(camFov) })
  else
    destroyCam()
    SetFollowPedCamViewMode(0)
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(true)
    SendNUIMessage({ action = 'exitViewfinder' })
  end
end

local function doSnapshot()
  local cam = scriptedCam
  if cam and DoesCamExist(cam) then
    local startFov = camFov
    CreateThread(function()
      for step = 1, 6 do
        if not DoesCamExist(cam) then return end
        SetCamFov(cam, math.max(fovMin, startFov * (0.5 + 0.5 * (1 - step / 6))))
        Wait(25)
      end
      Wait(120)
      for step = 1, 6 do
        if not DoesCamExist(cam) then return end
        SetCamFov(cam, math.min(fovMax, startFov * (0.5 + 0.5 * step / 6)))
        Wait(30)
      end
      if DoesCamExist(cam) then SetCamFov(cam, startFov) end
    end)
  end
  PlaySoundFrontend(-1, shutterSound, 'DEFAULT', true)
  SendNUIMessage({ action = 'shutterFlash' })
  local report = buildReport()
  local uploadUrl = lib.callback.await('crash_dslrcamera:getScreenshotUploadUrl', false)
  if not uploadUrl or uploadUrl == '' then
    lib.notify({ title = 'DSLR', description = 'FiveManage not configured. Set ServerConfig.FiveManageApiKey in server/sv_config.lua', type = 'error' })
    return
  end
  local opts = { encoding = 'png' }
  exports['screenshot-basic']:requestScreenshotUpload(uploadUrl, 'file', opts, function(data)
    local url = ''
    if type(data) == 'string' then
      local trimmed = data:gsub('^%s+', ''):gsub('%s+$', '')
      if trimmed ~= '' and trimmed:match('^https?://') then
        url = trimmed
      else
        local ok, resp = pcall(json.decode, data)
        if ok and resp then
          url = (resp.url or (resp.data and resp.data.url)) or ''
        end
      end
    elseif type(data) == 'table' then
      url = (data.url or (data.data and data.data.url)) or ''
    end
    TriggerServerEvent('crash_dslrcamera:addPhotoToSdCard', report, url, currentCameraSlot)
    lib.notify({ title = 'DSLR', description = url ~= '' and 'Photo saved.' or #report.evidence_ids .. ' evidence captured.', type = 'success' })
  end)
end

local cameraAnimDict = 'amb@world_human_photograph@camera@idle_a'
local cameraAnimName = 'idle_a'
local cameraAnimDictFallback = 'cellphone@'
local cameraAnimNameFallback = 'cellphone_text_read_base'

local cameraProp = nil
local cameraPropModel = nil

local function stopCameraAnim()
  local ped = PlayerPedId()
  ClearPedTasks(ped)
end

local function destroyCameraProp()
  if cameraProp and DoesEntityExist(cameraProp) then
    DetachEntity(cameraProp, true, true)
    DeleteEntity(cameraProp)
    cameraProp = nil
  end
  cameraPropModel = nil
end

local function updateCameraPropAndAnim()
  local ped = PlayerPedId()
  if not DoesEntityExist(ped) or not cameraActive then return end
  local model = Config.CameraPropModel
  for _, pair in ipairs({
    { cameraAnimDict, cameraAnimName },
    { cameraAnimDictFallback, cameraAnimNameFallback },
  }) do
    local dict, name = pair[1], pair[2]
    if not HasAnimDictLoaded(dict) then RequestAnimDict(dict) end
    local timeout = GetGameTimer() + 1500
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Wait(10) end
    if HasAnimDictLoaded(dict) and not IsEntityPlayingAnim(ped, dict, name, 3) then
      TaskPlayAnim(ped, dict, name, 4.0, -4.0, -1, 50, 0, false, false, false)
      break
    elseif IsEntityPlayingAnim(ped, dict, name, 3) then
      break
    end
  end
  if model and type(model) == 'string' and model ~= '' then
    local hash = GetHashKey(model)
    if not cameraProp or not DoesEntityExist(cameraProp) or cameraPropModel ~= model then
      destroyCameraProp()
      RequestModel(hash)
      local t = 0
      while not HasModelLoaded(hash) and t < 2000 do Wait(10) t = t + 10 end
      if HasModelLoaded(hash) then
        local coords = GetEntityCoords(ped)
        cameraProp = CreateObject(hash, coords.x, coords.y, coords.z, false, false, false)
        cameraPropModel = model
        SetEntityAsMissionEntity(cameraProp, true, true)
      end
    end
    if cameraProp and DoesEntityExist(cameraProp) then
      AttachEntityToEntity(cameraProp, ped, GetPedBoneIndex(ped, 28422), 0.03, 0.0, 0.0, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
    end
  else
    destroyCameraProp()
  end
end

function SetCameraActive(active, options)
  if cameraActive == (active == true) then return end
  cameraActive = active == true
  if cameraActive then
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(true)
    SendNUIMessage({ action = 'openCamera', sdLabel = 'CAM', zoom = fovToZoom(camFov), width = 560, height = 420, computerGallery = false })
    CreateThread(function()
      updateCameraPropAndAnim()
      while cameraActive do
        Wait(500)
        if not cameraActive then break end
        updateCameraPropAndAnim()
      end
      stopCameraAnim()
      destroyCameraProp()
    end)
  else
    currentCameraSlot = nil
    stopCameraAnim()
    destroyCameraProp()
    if viewfinderMode then setViewfinderMode(false) end
    viewfinderMode = false
    SendNUIMessage({ action = 'closeCamera' })
    SetNuiFocusKeepInput(false)
    SetNuiFocus(false, false)
  end
end
exports('SetCameraActive', SetCameraActive)

RegisterNetEvent('crash_dslrcamera:useDslrCamera', function(slot)
  currentCameraSlot = type(slot) == 'number' and slot or nil
  SetCameraActive(true)
end)

local function playButtonClick()
  PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
end

RegisterNUICallback('enterViewfinder', function(_, cb)
  playButtonClick()
  if cameraActive and not viewfinderMode then setViewfinderMode(true) end
  cb('ok')
end)

RegisterNUICallback('exitViewfinder', function(_, cb)
  playButtonClick()
  if viewfinderMode then setViewfinderMode(false) end
  cb('ok')
end)

RegisterNUICallback('cameraShutter', function(_, cb)
  if not cameraActive then cb('ok') return end
  doSnapshot()
  cb('ok')
end)

RegisterNUICallback('cameraPlay', function(_, cb)
  playButtonClick()
  local folderData = lib.callback.await('crash_dslrcamera:getSdCardFolders', false, currentCameraSlot)
  local defaultIdx = folderData and folderData.default_folder or 1
  local photos = lib.callback.await('crash_dslrcamera:getSdCardPhotos', false, defaultIdx, currentCameraSlot)
  SendNUIMessage({
    action = 'showGallery',
    photos = photos or {},
    folders = folderData and folderData.folders or {},
    folderIndex = defaultIdx,
  })
  cb('ok')
end)

RegisterNUICallback('cameraMenu', function(_, cb)
  playButtonClick()
  if viewfinderMode then setViewfinderMode(false) else SetCameraActive(false) end
  cb('ok')
end)

RegisterNUICallback('cameraTrash', function(_, cb)
  playButtonClick()
  cb('ok')
end)

local function refreshGalleryForFolder(folderIndex)
  local photos = lib.callback.await('crash_dslrcamera:getSdCardPhotos', false, folderIndex, currentCameraSlot)
  local folderData = lib.callback.await('crash_dslrcamera:getSdCardFolders', false, currentCameraSlot)
  SendNUIMessage({
    action = 'showGallery',
    photos = photos or {},
    folders = folderData and folderData.folders or {},
    folderIndex = folderIndex,
  })
end

RegisterNUICallback('cameraInfo', function(body, cb)
  playButtonClick()
  local folderIndex = type(body and body.folderIndex) == 'number' and body.folderIndex or 1
  local photoIndex = type(body and body.photoIndex) == 'number' and body.photoIndex or -1
  local folderData = lib.callback.await('crash_dslrcamera:getSdCardFolders', false, currentCameraSlot)
  local folders = folderData and folderData.folders or {}
  local defaultFolder = folderData and folderData.default_folder or 1
  SendNUIMessage({
    action = 'openFolderMenu',
    folders = folders,
    folderIndex = folderIndex,
    photoIndex = photoIndex,
    defaultFolder = defaultFolder,
  })
  cb('ok')
end)

RegisterNUICallback('folderMenuSetDefault', function(body, cb)
  playButtonClick()
  local folderIndex = type(body and body.folderIndex) == 'number' and body.folderIndex or 1
  TriggerServerEvent('crash_dslrcamera:setDefaultFolder', folderIndex, currentCameraSlot)
  cb('ok')
end)

RegisterNUICallback('folderMenuViewFolder', function(body, cb)
  playButtonClick()
  local folderIndex = type(body and body.folderIndex) == 'number' and body.folderIndex or 1
  refreshGalleryForFolder(folderIndex)
  cb('ok')
end)

RegisterNUICallback('folderMenuMoveTo', function(body, cb)
  playButtonClick()
  local fromIdx = type(body and body.fromFolderIndex) == 'number' and body.fromFolderIndex or 1
  local photoIdx = type(body and body.photoIndex) == 'number' and body.photoIndex or 0
  local toIdx = type(body and body.toFolderIndex) == 'number' and body.toFolderIndex or 1
  TriggerServerEvent('crash_dslrcamera:movePhotoToFolder', fromIdx, photoIdx + 1, toIdx, currentCameraSlot)
  refreshGalleryForFolder(fromIdx)
  cb('ok')
end)

RegisterNUICallback('folderMenuCreateFolder', function(body, cb)
  playButtonClick()
  local name = type(body and body.name) == 'string' and body.name:gsub('^%s+', ''):gsub('%s+$', '') or 'Evidence'
  if name == '' then name = 'Evidence' end
  TriggerServerEvent('crash_dslrcamera:createFolder', name, currentCameraSlot)
  local folderIndex = type(body and body.folderIndex) == 'number' and body.folderIndex or 1
  refreshGalleryForFolder(folderIndex)
  cb('ok')
end)

RegisterNUICallback('folderMenuDeleteFolder', function(body, cb)
  playButtonClick()
  local folderIndex = type(body and body.folderIndex) == 'number' and body.folderIndex or 1
  TriggerServerEvent('crash_dslrcamera:deleteFolder', folderIndex, currentCameraSlot)
  refreshGalleryForFolder(1)
  cb('ok')
end)

RegisterNUICallback('folderMenuClose', function(_, cb)
  cb('ok')
end)

RegisterNUICallback('cameraDeletePhoto', function(body, cb)
  playButtonClick()
  local idx = body and body.index
  local folderIdx = body and body.folderIndex
  if type(idx) == 'number' then
    TriggerServerEvent('crash_dslrcamera:deletePhotoFromSd', type(folderIdx) == 'number' and folderIdx or 1, idx + 1, currentCameraSlot)
    refreshGalleryForFolder(type(folderIdx) == 'number' and folderIdx or 1)
  end
  cb('ok')
end)

RegisterNUICallback('cameraGalleryClose', function(_, cb)
  playButtonClick()
  SendNUIMessage({ action = 'hideGallery' })
  cb('ok')
end)

RegisterNUICallback('cameraGalleryOk', function(_, cb)
  playButtonClick()
  SendNUIMessage({ action = 'hideGallery' })
  cb('ok')
end)

RegisterNUICallback('galleryCopyUrl', function(body, cb)
  if body and body.success and body.url and #tostring(body.url) > 4 then
    lib.notify({ title = 'DSLR', description = 'URL copied to clipboard.', type = 'success' })
  end
  cb('ok')
end)

RegisterNUICallback('cameraZoom', function(body, cb)
  playButtonClick()
  local delta = (body and body.delta) or 0
  camFov = math.max(fovMin, math.min(fovMax, camFov - delta * 3.0))
  if scriptedCam and DoesCamExist(scriptedCam) then SetCamFov(scriptedCam, camFov) end
  SendNUIMessage({ action = 'setCameraZoom', zoom = fovToZoom(camFov) })
  cb('ok')
end)

RegisterNUICallback('nuiReady', function(_, cb)
  cameraActive   = false
  viewfinderMode = false
  destroyCam()
  SetNuiFocus(false, false)
  SendNUIMessage({ action = 'closeCamera' })
  cb('ok')
end)

RegisterNUICallback('buttonPositions', function(body, cb)
  if body and body.positions then
    local p = body.positions
    print('─── DSLR LAYOUT ───')
    local BTN_IDS = { 'play', 'menu', 'info', 'zin', 'zout', 'ok', 'trash' }
    local BTN_HTML = { play='#btn-play', menu='#btn-menu', info='#btn-info',
                       zin='#btn-zoom-in', zout='#btn-zoom-out', ok='#btn-ok', trash='#btn-trash' }
    for _, id in ipairs(BTN_IDS) do
      local pos = p[id]
      if pos then
        print(('%s { left: %s; top: %s; right: auto; bottom: auto; transform: none; }')
          :format(BTN_HTML[id], tostring(pos.left), tostring(pos.top)))
      end
    end
    if p.dpad then
      print(('#dpad-ring { left: %s; top: %s; right: auto; bottom: auto; }')
        :format(tostring(p.dpad.left), tostring(p.dpad.top)))
    end
    if p.lcd then
      print(('#camera-lcd { left: %s; top: %s; width: %s; height: %s; right: auto; bottom: auto; }')
        :format(tostring(p.lcd.left), tostring(p.lcd.top),
                tostring(p.lcd.width), tostring(p.lcd.height)))
    end
    print('──────────────────')
  end
  cb('ok')
end)

local disabledOnCameraBack = { 1, 2, 24, 25, 30, 31, 21, 22, 37, 44, 47, 58, 68, 140, 141, 142, 143, 263, 264 }
local disabledOnViewfinder  = { 25, 30, 31, 21, 22, 37, 44, 47, 58, 68, 140, 141, 142, 143, 263, 264 }
local nDisabledBack, nDisabledVf = #disabledOnCameraBack, #disabledOnViewfinder
CreateThread(function()
  while true do
    if not cameraActive then
      Wait(1000)
    else
      local list, n = viewfinderMode and disabledOnViewfinder or disabledOnCameraBack, viewfinderMode and nDisabledVf or nDisabledBack
      for i = 1, n do DisableControlAction(0, list[i], true) end
      if viewfinderMode then
        syncCam()
        if IsControlJustPressed(0, 200) or IsControlJustPressed(0, 202) or IsControlJustPressed(0, 177) then setViewfinderMode(false) end
        if IsControlJustPressed(0, 24) then doSnapshot() end
        local camExists = scriptedCam and DoesCamExist(scriptedCam)
        if IsControlJustPressed(0, 14) then camFov = math.max(fovMin, math.min(fovMax, camFov + 3.0)); if camExists then SetCamFov(scriptedCam, camFov) end; SendNUIMessage({ action = 'setCameraZoom', zoom = fovToZoom(camFov) }) end
        if IsControlJustPressed(0, 15) then camFov = math.max(fovMin, math.min(fovMax, camFov - 3.0)); if camExists then SetCamFov(scriptedCam, camFov) end; SendNUIMessage({ action = 'setCameraZoom', zoom = fovToZoom(camFov) }) end
      else
        if IsControlJustPressed(0, 200) or IsControlJustPressed(0, 202) or IsControlJustPressed(0, 177) then SetCameraActive(false) end
        if IsControlJustPressed(0, 172) then SendNUIMessage({ action = 'scrollGalleryDetail', direction = -1 }) end
        if IsControlJustPressed(0, 173) then SendNUIMessage({ action = 'scrollGalleryDetail', direction = 1 }) end
      end
      Wait(0)
    end
  end
end)

AddEventHandler('onResourceStop', function(resName_)
  if GetCurrentResourceName() ~= resName_ then return end
  destroyCam()
  SetNuiFocusKeepInput(false)
  SetNuiFocus(false, false)
end)

AddEventHandler('onResourceStart', function(resName_)
  if GetCurrentResourceName() ~= resName_ then return end
  cameraActive    = false
  viewfinderMode  = false
  destroyCam()
  SetNuiFocusKeepInput(false)
  SetNuiFocus(false, false)
  CreateThread(function()
    Wait(800)
    SendNUIMessage({ action = 'closeCamera' })
  end)
end)
