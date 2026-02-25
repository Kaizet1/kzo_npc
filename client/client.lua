-- ============================================
-- IUH NPC - DIALOGUE SYSTEM
-- ============================================
-- Client-side: NPC spawning, dialogue navigation, camera, UI
-- All dialogue logic runs on client. Server only for validated actions.
-- Supports two interaction methods: iuh_textui or ox_target
-- ============================================

---@type UI
local UI = exports.kzo_ui:UI()

-- ============================================
-- STATE (set once, never re-created)
-- ============================================
local spawnedPeds = {}   -- [npcId] = ped handle
local spawnedBlips = {}  -- [npcId] = blip handle
local isDialogueOpen = false
local activeNpcId = nil
local dialogueCam = nil
local isTextUIShown = false  -- track textui visibility to avoid spamming Show/Hide
local nearestNpcId = nil     -- NPC currently in interact range

local cachedNPCData = nil
local dynamicNpcIdCounter = 10000 -- Start dynamic NPCs from ID 10000 to avoid conflicts with config NPCs

-- ============================================
-- FORWARD DECLARATIONS
-- ============================================
local openDialogue  -- Forward declare for ox_target callbacks

-- ============================================
-- HELPER FUNCTIONS
-- ============================================

--- Check if two coords are the same location (within threshold)
---@param coords1 vector4
---@param coords2 vector4
---@return boolean
local function isSameLocation(coords1, coords2)
    local threshold = 0.5  -- Distance threshold in meters
    local distance = #(vector3(coords1.x, coords1.y, coords1.z) - vector3(coords2.x, coords2.y, coords2.z))
    return distance < threshold
end

--- Remove NPC at specific location (if exists)
---@param coords vector4
local function removeNPCAtLocation(coords)
    local allNpcs = Config.GetAllNPCs()
    
    for id, ped in pairs(spawnedPeds) do
        -- Check if this is a config NPC or dynamic NPC
        local npcConfig = allNpcs[id]
        local npcCoords = npcConfig and npcConfig.coords or nil
        
        -- For dynamic NPCs, get coords from ped position
        if not npcCoords and DoesEntityExist(ped) then
            local pedPos = GetEntityCoords(ped)
            local heading = GetEntityHeading(ped)
            npcCoords = vector4(pedPos.x, pedPos.y, pedPos.z, heading)
        end
        
        if npcCoords and isSameLocation(coords, npcCoords) then
            -- Remove ox_target if using target method
            if Config.InteractionMethod == 'target' and DoesEntityExist(ped) then
                exports.ox_target:removeLocalEntity(ped, 'npc_talk_' .. id)
            end
            
            -- Delete ped
            if DoesEntityExist(ped) then
                DeletePed(ped)
            end
            spawnedPeds[id] = nil
            
            -- Remove blip
            if spawnedBlips[id] and DoesBlipExist(spawnedBlips[id]) then
                RemoveBlip(spawnedBlips[id])
                spawnedBlips[id] = nil
            end
            
            -- Remove from cached data
            if cachedNPCData and cachedNPCData[id] then
                cachedNPCData[id] = nil
            end
            
            if Config.Debug then
                print(('[iuh_npc] ✓ Removed NPC #%d at duplicate location'):format(id))
            end
            
            return true
        end
    end
    
    return false
end

-- ============================================
-- BUILD CACHED NPC DATA (runs once)
-- ============================================
local function buildCachedData()
    if cachedNPCData then return cachedNPCData end

    local allNpcs = Config.GetAllNPCs()
    local data = {}

    for id, npc in pairs(allNpcs) do
        local resolvedDialogue = {}
        for nodeKey, node in pairs(npc.dialogue) do
            local resolvedChoices = {}
            for i, choice in ipairs(node.choices) do
                resolvedChoices[i] = {
                    label = choice.label,  -- Direct string from config
                    next = choice.next,
                    action = choice.action,
                    event = choice.event,
                    command = choice.command,
                    args = choice.args,
                }
            end
            resolvedDialogue[nodeKey] = {
                text = node.text,  -- Direct string from config
                choices = resolvedChoices,
            }
        end

        data[id] = {
            id = id,
            name = npc.name,
            dialogue = resolvedDialogue,
        }
    end

    cachedNPCData = data
    return data
end

-- ============================================
-- NPC SPAWNING (runs once at resource start)
-- ============================================
local function spawnNPCs()
    local allNpcs = Config.GetAllNPCs()

    for id, npc in pairs(allNpcs) do
        -- Remove any existing NPC at this location
        removeNPCAtLocation(npc.coords)
        
        local model = joaat(npc.model)
        lib.requestModel(model, 10000)

        local ped = CreatePed(0, model, npc.coords.x, npc.coords.y, npc.coords.z - 1.0, npc.coords.w, false, false)
        SetEntityHeading(ped, npc.coords.w)
        SetModelAsNoLongerNeeded(model)

        -- Make NPC static and invincible
        FreezeEntityPosition(ped, true)
        SetEntityInvincible(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)

        -- Play ambient scenario
        if npc.scenario then
            TaskStartScenarioInPlace(ped, npc.scenario, 0, true)
        end

        spawnedPeds[id] = ped

        -- Add ox_target interaction if using target method
        if Config.InteractionMethod == 'target' then
            exports.ox_target:addLocalEntity(ped, {
                {
                    name = 'npc_talk_' .. id,
                    icon = Config.TargetIcon,
                    label = Config.TargetLabel,
                    distance = Config.InteractDistance,
                    onSelect = function()
                        openDialogue(id)
                    end,
                }
            })
        end

        -- Create blip if configured
        if npc.blip then
            local blip = AddBlipForCoord(npc.coords.x, npc.coords.y, npc.coords.z)
            SetBlipSprite(blip, npc.blip.sprite or 280)
            SetBlipDisplay(blip, 4)
            SetBlipScale(blip, npc.blip.scale or 0.8)
            SetBlipColour(blip, npc.blip.color or 3)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString(npc.blip.label or npc.name)
            EndTextCommandSetBlipName(blip)
            spawnedBlips[id] = blip
        end

        if Config.Debug then
            print(('[iuh_npc] ✓ Spawned NPC #%d: %s at %.1f, %.1f, %.1f'):format(id, npc.name, npc.coords.x, npc.coords.y, npc.coords.z))
        end
    end
end

-- ============================================
-- ANIMATION HELPERS
-- ============================================

--- Play configured dialogue animation on NPC (if any).
--- Falls back silently if no animation is configured.
---@param npcId number
local function playDialogueAnimation(npcId)
    local npcConfig = Config.GetNPC(npcId)
    if not npcConfig or not npcConfig.dialogueAnimation then return end

    local ped = spawnedPeds[npcId]
    if not ped or not DoesEntityExist(ped) then return end

    local da = npcConfig.dialogueAnimation
    local dict = da.dict
    local animName = da.anim
    local flag = da.flag or 1  -- default: loop

    lib.requestAnimDict(dict, 5000)
    ClearPedTasks(ped)
    TaskPlayAnim(ped, dict, animName, 8.0, -8.0, -1, flag, 0.0, false, false, false)
    RemoveAnimDict(dict)

    if Config.Debug then
        print(('[iuh_npc] ✓ Playing dialogue anim on NPC #%d: %s / %s'):format(npcId, dict, animName))
    end
end

--- Restore NPC to its default scenario animation after dialogue closes.
---@param npcId number
local function restoreNpcAnimation(npcId)
    local npcConfig = Config.GetNPC(npcId)
    if not npcConfig then return end

    local ped = spawnedPeds[npcId]
    if not ped or not DoesEntityExist(ped) then return end

    ClearPedTasks(ped)
    if npcConfig.scenario then
        TaskStartScenarioInPlace(ped, npcConfig.scenario, 0, true)
    end

    if Config.Debug then
        print(('[iuh_npc] ✓ Restored animation for NPC #%d'):format(npcId))
    end
end

-- ============================================
-- CAMERA SYSTEM
-- ============================================
local function createDialogueCamera(npcId)
    if not Config.EnableCamera then return end

    local ped = spawnedPeds[npcId]
    if not ped or not DoesEntityExist(ped) then return end

    -- Get NPC head bone position
    local headBone = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0) -- SKEL_Head
    local offset = Config.CameraOffset

    -- Calculate camera position always in front of NPC face using CONFIGURED heading from config
    -- (NOT GetEntityHeading which changes at runtime when NPC turns to face player)
    local npcConfig = Config.GetNPC(npcId)
    local npcHeading = npcConfig and npcConfig.coords.w or GetEntityHeading(ped)
    local rad = math.rad(npcHeading)
    -- NPC forward vector (direction NPC is facing based on config heading)
    local fwdX = -math.sin(rad)
    local fwdY =  math.cos(rad)
    -- Place camera in front of NPC face (along NPC forward vector)
    local camPos = vector3(
        headBone.x + fwdX * offset.y,
        headBone.y + fwdY * offset.y,
        headBone.z + offset.z
    )

    dialogueCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(dialogueCam, camPos.x, camPos.y, camPos.z)
    PointCamAtCoord(dialogueCam, headBone.x, headBone.y, headBone.z) -- look directly at NPC head/face
    SetCamFov(dialogueCam, Config.CameraFov)
    SetCamActive(dialogueCam, true)
    RenderScriptCams(true, true, 800, true, false)
end

local function destroyDialogueCamera()
    if dialogueCam then
        RenderScriptCams(false, true, 800, true, false)
        SetCamActive(dialogueCam, false)
        DestroyCam(dialogueCam, false)
        dialogueCam = nil
    end
end

-- ============================================
-- DIALOGUE FUNCTIONS
-- ============================================

--- Open dialogue with an NPC
---@param npcId number
openDialogue = function(npcId)
    if isDialogueOpen then return end

    local data = buildCachedData()
    local npcData = data[npcId]
    if not npcData then
        if Config.Debug then
            print(('[iuh_npc] ✗ NPC #%d not found in cached data'):format(npcId))
        end
        return
    end

    -- Verify start node exists
    if not npcData.dialogue.start then
        if Config.Debug then
            print(('[iuh_npc] ✗ NPC #%d has no "start" dialogue node'):format(npcId))
        end
        return
    end

    -- Hide textui before opening dialogue
    if isTextUIShown then
        lib.hideTextUI()
        isTextUIShown = false
    end

    isDialogueOpen = true
    activeNpcId = npcId

    -- Camera zoom to NPC face
    createDialogueCamera(npcId)

    -- Play custom dialogue animation on the NPC (if configured)
    playDialogueAnimation(npcId)

    -- Hide player ped during dialogue for better UX
    SetEntityVisible(cache.ped, false, false)

    -- Mount UI with all pre-resolved data (no server call needed)
    UI.setFocus(true, true)
    UI.mount('npc', {
        npcName = npcData.name,
        dialogue = npcData.dialogue,
        typewriterSpeed = Config.TypewriterSpeed,
    })

    if Config.Debug then
        print(('[iuh_npc] ✓ Dialogue opened with NPC #%d: %s'):format(npcId, npcData.name))
    end
end

--- Close dialogue
local function closeDialogue()
    if not isDialogueOpen then return end

    isDialogueOpen = false

    -- Capture before clearing so we can restore animation
    local closingNpcId = activeNpcId
    activeNpcId = nil

    UI.setFocus(false, false)
    UI.unmount('npc')
    destroyDialogueCamera()

    -- Restore NPC to its default scenario animation
    if closingNpcId then
        restoreNpcAnimation(closingNpcId)
    end

    -- Restore player ped visibility
    SetEntityVisible(cache.ped, true, true)

    if Config.Debug then
        print('[iuh_npc] ✓ Dialogue closed')
    end
end

-- ============================================
-- UI EVENT HANDLERS
-- ============================================

-- Player selected a choice with action
AddEventHandler('iuh_npc:action', function(data)
    if not isDialogueOpen then return end
    if not data or not data.action then return end

    local action = data.action

    if action == 'close' then
        closeDialogue()
    elseif action == 'event' then
        -- Close dialogue first, then trigger event after a short delay
        -- to allow UI unmount to complete before the next UI opens
        closeDialogue()
        if data.event then
            local eventName = data.event
            local eventArgs = data.args
            Citizen.SetTimeout(150, function()
                if eventArgs then
                    TriggerEvent(eventName, eventArgs)
                else
                    TriggerEvent(eventName)
                end
            end)
        end
    elseif action == 'server_event' then
        closeDialogue()
        if data.event then
            local eventName = data.event
            local eventArgs = data.args
            Citizen.SetTimeout(150, function()
                if eventArgs then
                    TriggerServerEvent(eventName, eventArgs)
                else
                    TriggerServerEvent(eventName)
                end
            end)
        end
    elseif action == 'command' then
        closeDialogue()
        if data.command then
            local cmd = data.command
            Citizen.SetTimeout(150, function()
                ExecuteCommand(cmd)
            end)
        end
    end
end)

-- Close event from UI (Escape key or close button)
AddEventHandler('iuh_npc:close', function()
    closeDialogue()
end)

-- ============================================
-- INTERACTION THREAD (iuh_textui + E key)
-- ============================================
-- Only used when Config.InteractionMethod = 'textui'
-- Checks distance to all NPCs. When player is within range,
-- shows iuh_textui. Press E to open dialogue.
-- Runs at adaptive tick rate: 1000ms when far, 0ms when near.
local function interactionThread()
    if Config.InteractionMethod ~= 'textui' then return end
    
    local allNpcs = Config.GetAllNPCs()
    local interactDist = Config.InteractDistance

    while true do
        local sleep = 1000
        local playerCoords = GetEntityCoords(cache.ped)
        local closestId = nil
        local closestDist = interactDist + 1

        -- Find nearest NPC within interact distance
        for id, ped in pairs(spawnedPeds) do
            if DoesEntityExist(ped) then
                local dist = #(playerCoords - GetEntityCoords(ped))
                if dist < closestDist then
                    closestDist = dist
                    closestId = id
                end
            end
        end

        if closestId and closestDist <= interactDist and not isDialogueOpen then
            -- Player is near an NPC
            sleep = 0
            nearestNpcId = closestId

            if not isTextUIShown then
                isTextUIShown = true
                lib.showTextUI('[E] ' .. (Config.TargetLabel or 'Talk'), {
                    position = 'right-center',
                    icon = 'fa-solid fa-comments'
                })
            end

            -- Check E key press (INPUT_CONTEXT = 38)
            if IsControlJustPressed(0, 38) then
                openDialogue(closestId)
            end
        else
            -- Player is far or dialogue is open
            if isTextUIShown then
                isTextUIShown = false
                lib.hideTextUI()
            end
            nearestNpcId = nil
        end

        Wait(sleep)
    end
end

-- ============================================
-- INITIALIZATION
-- ============================================
CreateThread(function()
    -- Wait a bit for models to load
    Wait(1000)

    -- Build cached data once
    buildCachedData()

    -- Spawn all NPCs once
    spawnNPCs()

    -- Start interaction loop
    interactionThread()

    if Config.Debug then
        print('[iuh_npc] ✓ Client script loaded!')
    end
end)

-- ============================================
-- DYNAMIC NPC CREATION (EXPORTS)
-- ============================================

--- Spawn a single NPC with given configuration
---@param npcConfig table NPC configuration (same structure as Config.NPCs entries)
---@return number|nil npcId The ID of the created NPC, or nil if failed
local function spawnDynamicNPC(npcConfig)
    if not npcConfig then
        print('[iuh_npc] ✗ Invalid NPC config')
        return nil
    end

    -- Validate required fields
    if not npcConfig.model or not npcConfig.coords or not npcConfig.dialogue then
        print('[iuh_npc] ✗ NPC config missing required fields (model, coords, dialogue)')
        return nil
    end

    -- Remove any existing NPC at this location
    removeNPCAtLocation(npcConfig.coords)

    -- Generate unique ID
    dynamicNpcIdCounter = dynamicNpcIdCounter + 1
    local npcId = dynamicNpcIdCounter

    -- Spawn ped
    local model = joaat(npcConfig.model)
    lib.requestModel(model, 10000)

    local ped = CreatePed(0, model, npcConfig.coords.x, npcConfig.coords.y, npcConfig.coords.z - 1.0, npcConfig.coords.w, false, false)
    SetEntityHeading(ped, npcConfig.coords.w)
    SetModelAsNoLongerNeeded(model)

    -- Make NPC static and invincible
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)

    -- Play ambient scenario
    if npcConfig.scenario then
        TaskStartScenarioInPlace(ped, npcConfig.scenario, 0, true)
    end

    spawnedPeds[npcId] = ped

    -- Add ox_target interaction if using target method
    if Config.InteractionMethod == 'target' then
        exports.ox_target:addLocalEntity(ped, {
            {
                name = 'iuh_npc_talk_' .. npcId,
                icon = Config.TargetIcon,
                label = Config.TargetLabel,
                distance = Config.InteractDistance,
                onSelect = function()
                    openDialogue(npcId)
                end,
            }
        })
    end

    -- Create blip if configured
    if npcConfig.blip then
        local blip = AddBlipForCoord(npcConfig.coords.x, npcConfig.coords.y, npcConfig.coords.z)
        SetBlipSprite(blip, npcConfig.blip.sprite or 280)
        SetBlipDisplay(blip, 4)
        SetBlipScale(blip, npcConfig.blip.scale or 0.8)
        SetBlipColour(blip, npcConfig.blip.color or 3)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString(npcConfig.blip.label or npcConfig.name or 'NPC')
        EndTextCommandSetBlipName(blip)
        spawnedBlips[npcId] = blip
    end

    -- Initialize cached data if not done yet
    if not cachedNPCData then
        buildCachedData()
    end

    -- Add to cached NPC data (dialogue is already in plain text)
    local resolvedDialogue = {}
    for nodeKey, node in pairs(npcConfig.dialogue) do
        local resolvedChoices = {}
        for i, choice in ipairs(node.choices) do
            resolvedChoices[i] = {
                label = choice.label,
                next = choice.next,
                action = choice.action,
                event = choice.event,
                command = choice.command,
                args = choice.args,
            }
        end
        resolvedDialogue[nodeKey] = {
            text = node.text,
            choices = resolvedChoices,
        }
    end

    cachedNPCData[npcId] = {
        id = npcId,
        name = npcConfig.name or 'NPC',
        dialogue = resolvedDialogue,
    }

    if Config.Debug then
        print(('[iuh_npc] ✓ Dynamic NPC #%d created: %s at %.1f, %.1f, %.1f'):format(npcId, npcConfig.name or 'NPC', npcConfig.coords.x, npcConfig.coords.y, npcConfig.coords.z))
    end

    return npcId
end

-- Export function
exports('CreateNPC', spawnDynamicNPC)

-- ============================================
-- CLEANUP ON RESOURCE STOP
-- ============================================
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    -- Close dialogue if open
    if isDialogueOpen then
        closeDialogue()
    end

    -- Hide textui (only if using textui method)
    if Config.InteractionMethod == 'textui' and isTextUIShown then
        lib.hideTextUI()
        isTextUIShown = false
    end

    -- Remove ox_target interactions (only if using target method)
    if Config.InteractionMethod == 'target' then
        for id, ped in pairs(spawnedPeds) do
            if DoesEntityExist(ped) then
                exports.ox_target:removeLocalEntity(ped, 'iuh_npc_talk_' .. id)
            end
        end
    end

    -- Delete all spawned peds
    for id, ped in pairs(spawnedPeds) do
        if DoesEntityExist(ped) then
            DeletePed(ped)
        end
    end
    spawnedPeds = {}

    -- Remove all blips
    for _, blip in pairs(spawnedBlips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end
    spawnedBlips = {}

    if Config.Debug then
        print('[iuh_npc] ✓ Resources cleaned up')
    end
end)
