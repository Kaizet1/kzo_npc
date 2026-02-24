-- ============================================
-- DYNAMIC NPC CREATION - EXPORT EXAMPLES
-- ============================================
-- This file demonstrates how to create NPCs dynamically from other scripts
-- Copy these examples into your own resource to create NPCs programmatically
-- ============================================
--
-- AVAILABLE EXPORT:
--   exports['iuh_npc']:CreateNPC(npcConfig)
--
--   Parameters:
--     npcConfig - Table containing NPC configuration (same structure as Config.NPCs)
--
--   Returns:
--     number - Unique ID of the created NPC (starts from 10000 to avoid conflicts)
--     nil    - If creation failed (invalid config)
--
-- NOTES:
--   - NPCs created via export will persist until resource restart
--   - Dynamic NPCs start from ID 10000+ to avoid conflicts with config NPCs
--   - All dialogue text should be plain strings (no locale keys needed)
--   - The 'start' dialogue node is REQUIRED
--
-- ============================================

-- ============================================
-- EXAMPLE 1: BASIC NPC WITH SIMPLE DIALOGUE
-- ============================================

-- Create an NPC with minimal configuration
local npcId = exports['iuh_npc']:CreateNPC({
    name = 'Flower Seller',            -- NPC name displayed in dialogue UI
    model = 'a_f_y_business_01',       -- Female business ped model
    coords = vector4(-269.0, -956.0, 31.22, 207.0),  -- Spawn location (x, y, z, heading)
    scenario = 'WORLD_HUMAN_STAND_MOBILE',  -- Idle animation (using phone)
    
    -- Dialogue tree (must have 'start' node)
    dialogue = {
        start = {
            text = 'Hello! I sell fresh flowers. Would you like to buy some?',
            choices = {
                { label = 'Yes, I want flowers', action = 'event', event = 'shop:buyFlowers' },
                { label = 'No, thank you', action = 'close' },
            },
        },
    },
})

print('NPC created with ID:', npcId)

-- ============================================
-- EXAMPLE 2: NPC WITH MAP BLIP AND COMPLEX DIALOGUE
-- ============================================

-- Create a quest NPC with multiple dialogue branches
local questNpcId = exports['iuh_npc']:CreateNPC({
    name = 'Mysterious Old Man',
    model = 's_m_m_fiboffice_02',
    coords = vector4(245.5, -1084.5, 29.29, 90.0),
    scenario = 'WORLD_HUMAN_GUARD_STAND',
    
    -- Custom animation when dialogue opens (optional)
    dialogueAnimation = {
        dict = 'gestures@m@standing@casual',
        anim = 'gesture_pleased',
        flag = 1,  -- Loop animation
    },
    
    -- Add a blip on the map
    blip = {
        sprite = 280,           -- Question mark icon
        color = 5,              -- Yellow color
        scale = 0.8,            -- Medium size
        label = 'Mysterious Quest',  -- Text on map
    },
    
    -- Multi-branch dialogue tree
    dialogue = {
        -- Entry point (always required)
        start = {
            text = 'Greetings, young one. I have a special task for you...',
            choices = {
                { label = 'What task?', next = 'quest_info' },           -- Navigate to another node
                { label = 'I\'m not interested', action = 'close' },     -- Close dialogue
            },
        },
        
        -- Second dialogue node
        quest_info = {
            text = 'I need you to find 10 rare diamonds. Will you accept this quest?',
            choices = {
                { 
                    label = 'Accept quest', 
                    action = 'server_event',                    -- Trigger server event
                    event = 'quest:acceptMission',
                    args = { questId = 'mysterious_diamonds' }  -- Pass arguments
                },
                { label = 'Let me think about it', next = 'start' },  -- Go back to start
                { label = 'No thanks', action = 'close' },
            },
        },
    },
})

-- ============================================
-- EXAMPLE 3: CREATE MULTIPLE NPCs IN A LOOP
-- ============================================

-- Define vendor locations
local vendorLocations = {
    { coords = vector4(-1486.0, -378.0, 40.16, 133.0), name = 'Bread Vendor', icon = 52 },
    { coords = vector4(-1222.0, -907.0, 12.33, 34.0), name = 'Water Vendor', icon = 52 },
    { coords = vector4(-707.0, -914.0, 19.21, 90.0), name = 'Toy Vendor', icon = 52 },
}

-- Create all vendors at once
for i, vendor in ipairs(vendorLocations) do
    local npcId = exports['iuh_npc']:CreateNPC({
        name = vendor.name,
        model = 'a_m_y_business_02',
        coords = vendor.coords,
        scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
        
        blip = {
            sprite = vendor.icon,
            color = 2,  -- Green
            scale = 0.6,
            label = vendor.name,
        },
        
        dialogue = {
            start = {
                text = 'Welcome to ' .. vendor.name .. '! What can I get you?',
                choices = {
                    { 
                        label = 'Browse items', 
                        action = 'event', 
                        event = 'shop:open', 
                        args = { vendorId = i }  -- Pass vendor index
                    },
                    { label = 'Goodbye', action = 'close' },
                },
            },
        },
    })
    
    print('Created vendor:', vendor.name, 'with ID:', npcId)
end

-- ============================================
-- EXAMPLE 4: SERVER-SYNCED NPC CREATION
-- ============================================
-- Create NPCs from server and sync to all clients

-- SERVER SIDE (server.lua)
--[[
RegisterCommand('spawnnpc', function(source, args)
    -- Get player position
    local playerPed = GetPlayerPed(source)
    local coords = GetEntityCoords(playerPed)
    local heading = GetEntityHeading(playerPed)
    
    local npcName = args[1] or 'Dynamic NPC'
    
    -- Send to all clients to create the NPC
    TriggerClientEvent('myresource:createSharedNPC', -1, {
        name = npcName,
        coords = vector4(coords.x, coords.y, coords.z, heading),
    })
    
    TriggerClientEvent('chat:addMessage', source, {
        args = { 'System', 'NPC spawned for all players!' }
    })
end, false)
]]

-- CLIENT SIDE (client.lua)
--[[
RegisterNetEvent('myresource:createSharedNPC', function(npcData)
    local npcId = exports['iuh_npc']:CreateNPC({
        name = npcData.name,
        model = 's_m_m_autoshop_01',
        coords = npcData.coords,
        scenario = 'WORLD_HUMAN_CLIPBOARD',
        
        blip = {
            sprite = 280,
            color = 3,
            scale = 0.7,
            label = npcData.name,
        },
        
        dialogue = {
            start = {
                text = 'Hello! I am ' .. npcData.name .. '. I was dynamically spawned!',
                choices = {
                    { label = 'That\\'s cool!', action = 'close' },
                },
            },
        },
    })
    
    print('Shared NPC created with ID:', npcId)
end)
]]

-- ============================================
-- IMPORTANT NOTES
-- ============================================
--[[
1. REQUIRED FIELDS:
   - name: NPC display name (string)
   - model: Ped model name (string)
   - coords: Spawn position vector4(x, y, z, heading)
   - dialogue: Dialogue tree table with 'start' node

2. DIALOGUE STRUCTURE:
   - Must have a 'start' node (entry point)
   - Each node has 'text' (string) and 'choices' (array)
   - Choices must have 'label' (string)
   - Use 'next' to navigate between nodes
   - Use 'action' to perform actions

3. AVAILABLE ACTIONS:
   - 'close': Close dialogue window
   - 'event': Trigger client event (requires 'event' field)
   - 'server_event': Trigger server event (requires 'event' field)
   - 'command': Execute command (requires 'command' field)

4. OPTIONAL FIELDS:
   - scenario: Idle animation (string)
   - dialogueAnimation: Custom dialogue animation (table)
   - blip: Map marker configuration (table)

5. TIPS:
   - Dynamic NPCs have IDs starting from 10000
   - NPCs persist until resource restart
   - All text should be plain strings (no locale keys)
   - Use args to pass data to events/commands
   - Test thoroughly before deploying

6. PED MODELS:
   Full list: https://docs.fivem.net/docs/game-references/ped-models/

7. SCENARIOS:
   Full list: https://pastebin.com/6mrYTdQv

8. BLIP SPRITES:
   Full list: https://docs.fivem.net/docs/game-references/blips/
]]
