-- ╔═══════════════════════════════════════════════════════════════════════════════╗
-- ║                        IUH NPC DIALOGUE SYSTEM - CONFIGURATION                ║
-- ║                                                                               ║
-- ║  Interactive NPC dialogue system for FiveM RP servers.                         ║
-- ║  NPCs are spawned once at resource start. Dialogue trees are navigated        ║
-- ║  entirely on the client side for maximum performance.                          ║
-- ║                                                                               ║
-- ║  QUICK START GUIDE:                                                           ║
-- ║  1. Configure NPC models, spawn locations, and idle animations                ║
-- ║  2. Build dialogue trees with text and player choice options                   ║
-- ║  3. Add optional blips to show NPCs on the map                                ║
-- ║  4. Adjust camera and interaction settings below                               ║
-- ║                                                                               ║
-- ║  DYNAMIC NPC CREATION:                                                        ║
-- ║  You can also create NPCs from other scripts using the export:                ║
-- ║  exports['iuh_npc']:CreateNPC(npcConfig)                                      ║
-- ║  See EXPORT_EXAMPLE.lua for detailed examples                                 ║
-- ╚═══════════════════════════════════════════════════════════════════════════════╝

Config = {}

-- ============================================
-- GENERAL SETTINGS
-- ============================================

-- Enable debug messages in F8 console
Config.Debug = false

-- Interaction method: 'textui' or 'target'
-- 'textui' - Show textui prompt when close to NPC, press E to interact
-- 'target' - Use ox_target to interact with NPCs (requires ox_target)
Config.InteractionMethod = 'target'

-- Maximum distance to interact with NPCs (in meters)
-- For textui: Distance to show textui prompt
-- For target: Maximum target distance
Config.InteractDistance = 1.5

-- Target icon (only used if InteractionMethod = 'target')
Config.TargetIcon = 'fas fa-comments'

-- Target label (only used if InteractionMethod = 'target')
Config.TargetLabel = 'Talk'

-- Typewriter effect speed for dialogue text (milliseconds per character)
-- Lower = faster typing effect, Higher = slower
-- Set to 0 to disable typewriter effect
Config.TypewriterSpeed = 30

-- ============================================
-- CAMERA SETTINGS
-- ============================================

-- Enable camera zoom to NPC face during dialogue
-- Set to false to keep player's normal camera view
Config.EnableCamera = true

-- Camera offset from NPC head bone
-- x = left/right, y = forward/back (distance from NPC), z = up/down (camera height)
Config.CameraOffset = vector3(0.0, 1.75, 0.0)

-- Camera field of view (lower = more zoomed in)
Config.CameraFov = 45.0

-- ============================================
-- NPC CONFIGURATION
-- ============================================
--
-- HOW TO CONFIGURE AN NPC:
-- Each NPC is defined by an entry in Config.NPCs table with the following fields:
--
-- REQUIRED FIELDS:
--   name        : Display name shown in dialogue UI header (string)
--   model       : Ped model name (string)
--                 Full list: https://docs.fivem.net/docs/game-references/ped-models/
--   coords      : Spawn location and facing direction
--                 Format: vector4(x, y, z, heading)
--                 Tip: Use /getcoords command in-game to get your current position
--   dialogue    : Dialogue tree (table) - See DIALOGUE TREE section below
--
-- OPTIONAL FIELDS:
--   scenario    : Idle animation played while NPC is standing (string)
--                 Examples: 'WORLD_HUMAN_CLIPBOARD', 'WORLD_HUMAN_STAND_IMPATIENT',
--                           'WORLD_HUMAN_GUARD_STAND', 'WORLD_HUMAN_AA_SMOKE'
--                 Full list: https://pastebin.com/6mrYTdQv
--
--   dialogueAnimation : Custom animation played when dialogue opens (table)
--                       If not set, NPC keeps scenario animation during dialogue
--     dict  : Animation dictionary name (string)
--     anim  : Animation clip name (string)
--     flag  : Animation flag (number, default = 1)
--             Common flags: 1=loop, 8=hold last frame, 9=loop+hold
--
--   blip        : Map blip configuration (table)
--                 If not set, no blip will appear on the map
--     sprite    : Blip icon ID (number)
--                 Full list: https://docs.fivem.net/docs/game-references/blips/
--     color     : Blip color ID (number, 0-85)
--     scale     : Blip size (number, 0.5-2.0)
--     label     : Text displayed on map when hovering over blip (string)
--
-- ============================================
-- DIALOGUE TREE STRUCTURE:
-- ============================================
--
-- The dialogue tree is a table of "nodes". Each node represents one dialogue screen.
-- The 'start' node is REQUIRED and is always the entry point when opening dialogue.
--
-- DIALOGUE NODE FORMAT:
--   dialogue = {
--     node_name = {                     -- Node identifier (must be unique)
--       text = "NPC dialogue text",      -- What the NPC says (string)
--       choices = {                     -- Player response options (array of tables)
--         {
--           label = "Button text",       -- Text shown on choice button (REQUIRED)
--           next = "next_node_name",    -- Navigate to another dialogue node (optional)
--           action = "action_type",      -- Perform an action (optional)
--           event = "event_name",        -- Event to trigger (required if action = 'event' or 'server_event')
--           command = "command_name",    -- Command to execute (required if action = 'command')
--           args = { key = value },     -- Arguments to pass to event/command (optional)
--         },
--       },
--     },
--   }
--
-- AVAILABLE ACTIONS:
--   'close'        - Close the dialogue window
--   'event'        - Trigger a client-side event (requires 'event' field)
--   'server_event' - Trigger a server-side event (requires 'event' field)
--   'command'      - Execute a command (requires 'command' field)
--
-- NAVIGATION:
--   Use 'next' to move between dialogue nodes (creates conversation branches)
--   Use 'action' to perform an action (typically used on final choices)
--   You can combine 'next' with actions in some cases
--
-- EXAMPLE:
--   dialogue = {
--     start = {                                          -- Entry point (required)
--       text = "Hello! How can I help you?",
--       choices = {
--         { label = "Tell me about jobs", next = "jobs" },        -- Navigate to 'jobs' node
--         { label = "Open shop", action = "event", event = "shop:open" }, -- Trigger event
--         { label = "Goodbye", action = "close" },                -- Close dialogue
--       },
--     },
--     jobs = {                                            -- Another node
--       text = "We have many jobs available!",
--       choices = {
--         { label = "Go back", next = "start" },               -- Return to start
--       },
--     },
--   }

Config.NPCs = {
    -- ┌──────────────────────────────────────────────────────────────────────┐
    -- │ EXAMPLE #1: CITY GUIDE - Multi-branch dialogue with information       │
    -- └──────────────────────────────────────────────────────────────────────┘
    [1] = {
        name = 'City Guide',           -- NPC name shown in dialogue UI
        model = 's_m_y_cop_01',        -- Ped model (male cop)
        coords = vector4(100, -1000.23, 29.42, 340.0),  -- x, y, z, heading
        scenario = 'WORLD_HUMAN_CLIPBOARD',  -- Idle animation (holding clipboard)
        
        -- Optional: Custom animation when dialogue opens
        -- Remove this section if you want to keep the scenario animation
        dialogueAnimation = {
            dict = 'gestures@m@standing@casual',
            anim = 'gesture_arm_cross_stand',
            flag = 1,  -- 1 = loop animation
        },
        
        -- Optional: Map blip
        blip = {
            sprite = 280,   -- Information icon
            color = 3,      -- Blue color
            scale = 0.8,    -- Medium size
            label = 'City Guide',  -- Text on map
        },
        dialogue = {
            start = {
                text = 'Hello there! Welcome to the city. I can help you get started with life here. What would you like to know?',
                choices = {
                    { label = 'I\'m looking for a job', next = 'jobs' },
                    { label = 'Tell me about the city', next = 'city_info' },
                    { label = 'Goodbye', action = 'close' },
                },
            },
            jobs = {
                text = 'There are many job opportunities in this city! You can work as a miner, lumberjack, fisherman, oil worker, and more. I can help you register for a job if you\'d like.',
                choices = {
                    { label = 'Register for a job', action = 'event', event = 'iuh_jobcenter:open' },
                    { label = 'Go back', next = 'start' },
                },
            },
            city_info = {
                text = 'This is a beautiful city with many facilities. There\'s a hospital for medical emergencies, a police station for law enforcement, and plenty of shops around the city.',
                choices = {
                    { label = 'Where is the hospital?', next = 'hospital_info' },
                    { label = 'Where is the police station?', next = 'police_info' },
                    { label = 'Go back', next = 'start' },
                },
            },
            hospital_info = {
                text = 'The hospital is located in Pillbox Hill. If you ever get injured, paramedics will take you there. You can also visit for routine medical care.',
                choices = {
                    { label = 'Go back', next = 'city_info' },
                },
            },
            police_info = {
                text = 'The police station is at Mission Row. The officers there help keep our city safe. If you need help or want to report a crime, you can visit them.',
                choices = {
                    { label = 'Go back', next = 'city_info' },
                },
            },
        },
    },

    -- ┌──────────────────────────────────────────────────────────────────────┐
    -- │ EXAMPLE #2: SHOP KEEPER - Simple dialogue with event triggers         │
    -- └──────────────────────────────────────────────────────────────────────┘
    [2] = {
        name = 'Shop Keeper',          -- NPC name
        model = 'mp_m_shopkeep_01',    -- Shop keeper model
        coords = vector4(50, -1000.23, 29.42, 340.0),
        scenario = 'WORLD_HUMAN_STAND_IMPATIENT',  -- Standing impatiently
        
        -- No dialogueAnimation → NPC keeps scenario animation during dialogue
        
        blip = {
            sprite = 52,    -- Shopping cart icon
            color = 2,      -- Green color
            scale = 0.7,    -- Small size
            label = 'Shop',
        },
        dialogue = {
            start = {
                text = 'Welcome to my shop! What can I do for you today?',
                choices = {
                    { label = 'I want to buy something', action = 'event', event = 'iuh_shop:open', args = { shopId = 1 } },
                    { label = 'I want to sell items', action = 'event', event = 'iuh_sellmarket:open' },
                    { label = 'Goodbye', action = 'close' },
                },
            },
        },
    },
}

-- ============================================
-- UTILITY FUNCTIONS
-- ============================================

--- Get a specific NPC by ID
---@param npcId number
---@return table|nil
function Config.GetNPC(npcId)
    return Config.NPCs[npcId]
end

--- Get all NPCs
---@return table
function Config.GetAllNPCs()
    return Config.NPCs
end

print('[iuh_npc] ✓ Config loaded successfully!')
