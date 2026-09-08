/* OQV2 QUESTS — browser-only mock data (never loaded in game)
   Used by web/dev.html to preview and test the interface. */
(function (w) {
    'use strict';

    var now = Math.floor(Date.now() / 1000);

    var MISSIONS = [
        {
            uid: 'm_scrap_trade', name: 'Scrap Trade', category: 'general', icon: 'recycle', enabled: true, order: 1,
            description: 'Old Marco buys used electronics. Bring him 5 pieces of scrap metal and he will pay well — no questions asked.',
            requiredLevel: 0, xpReward: 120, prerequisites: [],
            requirements: { items: [], money: 0 },
            objectives: [{ id: 'o1', type: 'give_item', label: 'Hand 5x Scrap Metal to Marco', item: 'scrapmetal', count: 5, radius: 2, duration: 5000, marker: true, blip: true, optional: false }],
            rewards: { money: 850, bank: 0, black: 0, items: [{ name: 'water', count: 1, chance: 100 }], xp: 0 },
            restriction: { type: 'all', grade: 0, level: 0 },
            cooldown: { type: 'daily', seconds: 86400, maxCompletions: 0 },
            alert: { title: 'Scrap Trade', description: 'Marco is waiting for his scrap metal.', sound: 'quest_start', duration: 6000 },
            schedule: { enabled: false, from: 0, to: 24 },
            meta: { createdBy: 'config', createdAt: now - 90000, updatedAt: now - 4000 }
        },
        {
            uid: 'm_night_delivery', name: 'Night Delivery', category: 'delivery', icon: 'truck', enabled: true, order: 2,
            description: 'A sealed package needs to reach the docks before sunrise. Do not open it. Do not ask.',
            requiredLevel: 2, xpReward: 260, prerequisites: ['m_scrap_trade'],
            requirements: { items: [], money: 0 },
            objectives: [
                { id: 'o2', type: 'interact', label: 'Pick up the sealed package', coords: { x: 707.34, y: -966.71, z: 30.41 }, radius: 2, duration: 4000, anim: { dict: 'anim@heists@box_carry@', clip: 'idle', flag: 49 }, marker: true, blip: true },
                { id: 'o3', type: 'deliver', label: 'Deliver the package at the docks', item: 'sealed_package', count: 1, coords: { x: 1208.61, y: -3115.55, z: 5.54 }, radius: 3, marker: true, blip: true }
            ],
            rewards: { money: 1800, bank: 0, black: 0, items: [], xp: 0 },
            restriction: { type: 'all', grade: 0, level: 0 },
            cooldown: { type: 'daily', seconds: 86400, maxCompletions: 0 },
            alert: { title: 'Night Delivery', description: 'Get to the docks before sunrise.', sound: 'quest_start', duration: 6000 },
            schedule: { enabled: true, from: 20, to: 6 },
            meta: { createdBy: 'config', createdAt: now - 80000, updatedAt: now - 3000 }
        },
        {
            uid: 'm_clear_the_block', name: 'Clear The Block', category: 'crime', icon: 'crosshair', enabled: true, order: 3,
            description: 'A crew took over the alley behind the motel. Deal with them and bring back whatever they were guarding.',
            requiredLevel: 5, xpReward: 500, prerequisites: ['m_night_delivery'],
            requirements: { items: [], money: 0 },
            objectives: [
                { id: 'o4', type: 'goto', label: 'Reach the alley behind the motel', coords: { x: 328.29, y: -2043.13, z: 21.31 }, radius: 30, marker: true, blip: true },
                { id: 'o5', type: 'kill', label: 'Eliminate the crew', amount: 3, model: 'g_m_y_ballasout_01', marker: false, blip: false }
            ],
            rewards: { money: 3200, bank: 0, black: 1500, items: [{ name: 'weapon_ammo', count: 30, chance: 60 }], xp: 0 },
            restriction: { type: 'level', grade: 0, level: 5 },
            cooldown: { type: 'weekly', seconds: 604800, maxCompletions: 0 },
            alert: { title: 'Clear The Block', description: 'Armed hostiles reported. Be careful.', sound: 'quest_alert', duration: 6000 },
            schedule: { enabled: false, from: 0, to: 24 },
            meta: { createdBy: 'Codex Dev', createdAt: now - 40000, updatedAt: now - 900 }
        },
        {
            uid: 'm_evidence_run', name: 'Evidence Run', category: 'legal', icon: 'shield', enabled: false, order: 4,
            description: 'Transport the sealed evidence bag from Mission Row to the forensic lab.',
            requiredLevel: 0, xpReward: 180, prerequisites: [],
            requirements: { items: [], money: 0 },
            objectives: [{ id: 'o6', type: 'deliver', label: 'Drop the evidence at the lab', item: 'evidence_bag', count: 1, coords: { x: 1855.24, y: 3683.51, z: 34.27 }, radius: 3, marker: true, blip: true }],
            rewards: { money: 0, bank: 1200, black: 0, items: [], xp: 0 },
            restriction: { type: 'job', job: 'police', grade: 0, level: 0 },
            cooldown: { type: 'hourly', seconds: 3600, maxCompletions: 0 },
            alert: { title: 'Evidence Run', description: 'Chain of custody starts now.', sound: 'quest_start', duration: 6000 },
            schedule: { enabled: false, from: 0, to: 24 },
            meta: { createdBy: 'config', createdAt: now - 30000, updatedAt: now - 300 }
        }
    ];

    var LOCATIONS = [
        {
            uid: 'loc_marco', name: 'Old Marco', enabled: true, description: 'Scrap dealer in the industrial yard.',
            entity: { type: 'ped', model: 'a_m_m_hillbilly_01', scenario: 'WORLD_HUMAN_SMOKING', freeze: true, invincible: true, ignore: true },
            points: [{ x: 1088.13, y: -2002.13, z: 30.9, w: 275 }],
            rotate: { enabled: false, interval: 1800 },
            target: { label: 'Talk to Marco', icon: 'fa-solid fa-comments', distance: 2 },
            dialogue: { title: 'Old Marco', text: 'You look like someone who knows where to find metal.', accept: 'What do you need?', decline: 'Not today' },
            blip: { enabled: true, sprite: 480, color: 27, scale: 0.8, label: 'Scrap Dealer', shortRange: true },
            schedule: { enabled: false, from: 0, to: 24 },
            missions: ['m_scrap_trade'],
            meta: { createdBy: 'config', createdAt: now - 90000, updatedAt: now - 5000 }
        },
        {
            uid: 'loc_dockhand', name: 'Dock Handler', enabled: true, description: 'Runs the night shift at the docks.',
            entity: { type: 'ped', model: 's_m_y_dockwork_01', scenario: 'WORLD_HUMAN_CLIPBOARD', freeze: true, invincible: true, ignore: true },
            points: [{ x: 1204.71, y: -3113.63, z: 5.54, w: 178 }, { x: 856.16, y: -3140.51, z: 5.9, w: 90 }],
            rotate: { enabled: true, interval: 1800 },
            target: { label: 'Talk to the handler', icon: 'fa-solid fa-box', distance: 2 },
            dialogue: { title: 'Dock Handler', text: 'Packages come, packages go.', accept: 'I am listening', decline: 'Walk away' },
            blip: { enabled: true, sprite: 478, color: 5, scale: 0.8, label: 'Night Deliveries', shortRange: true },
            schedule: { enabled: true, from: 19, to: 7 },
            missions: ['m_night_delivery'],
            meta: { createdBy: 'config', createdAt: now - 88000, updatedAt: now - 5000 }
        },
        {
            uid: 'loc_evidence_locker', name: 'Evidence Locker', enabled: true, description: 'Mission Row evidence intake.',
            entity: { type: 'object', model: 'prop_box_wood04a', freeze: true, invincible: true, ignore: true },
            points: [{ x: 473.61, y: -996.14, z: 25.06, w: 0 }],
            rotate: { enabled: false, interval: 1800 },
            target: { label: 'Open the evidence locker', icon: 'fa-solid fa-box-archive', distance: 1.5 },
            dialogue: { title: 'Evidence Locker', text: 'A sealed bag is tagged and ready.', accept: 'Take the bag', decline: 'Close' },
            blip: { enabled: false, sprite: 480, color: 27, scale: 0.8, label: 'Evidence', shortRange: true },
            schedule: { enabled: false, from: 0, to: 24 },
            missions: [],
            meta: { createdBy: 'config', createdAt: now - 70000, updatedAt: now - 5000 }
        }
    ];

    var NPCS = [
        {
            uid: 'npc_block_crew', name: 'Block Crew', enabled: true, model: 'g_m_y_ballasout_01',
            count: 3, companions: 1, weapons: ['WEAPON_PISTOL', 'WEAPON_MICROSMG'],
            coords: { x: 328.29, y: -2043.13, z: 21.31 }, radius: 18,
            trigger: { type: 'proximity', distance: 80 },
            difficulty: 'normal', aggression: 80, alertPolice: true, respawn: 600,
            loot: [{ name: 'weapon_ammo', count: 15, chance: 55 }, { name: 'bandage', count: 2, chance: 35 }],
            money: { min: 150, max: 600 }, xp: 40, linkedMission: 'm_clear_the_block',
            meta: { createdBy: 'config', createdAt: now - 60000, updatedAt: now - 1200 }
        },
        {
            uid: 'npc_desert_smugglers', name: 'Desert Smugglers', enabled: false, model: 'g_m_m_mexboss_01',
            count: 4, companions: 2, weapons: ['WEAPON_ASSAULTRIFLE'],
            coords: { x: 1387.24, y: 3608.05, z: 34.98 }, radius: 30,
            trigger: { type: 'proximity', distance: 120 },
            difficulty: 'hard', aggression: 95, alertPolice: true, respawn: 900,
            loot: [{ name: 'weapon_ammo', count: 30, chance: 70 }],
            money: { min: 400, max: 1500 }, xp: 90, linkedMission: null,
            meta: { createdBy: 'Codex Dev', createdAt: now - 20000, updatedAt: now - 200 }
        }
    ];

    var SCHEMA = {
        objectiveTypes: [
            { value: 'give_item', label: 'Hand over item' }, { value: 'collect', label: 'Collect item' },
            { value: 'deliver', label: 'Deliver to point' }, { value: 'goto', label: 'Go to location' },
            { value: 'kill', label: 'Eliminate targets' }, { value: 'interact', label: 'Interact / animate' },
            { value: 'pay', label: 'Pay money' }, { value: 'wait', label: 'Timed task' }
        ],
        restrictionTypes: [
            { value: 'all', label: 'Everyone' }, { value: 'civilian', label: 'Civilians only' },
            { value: 'job', label: 'Specific job' }, { value: 'gang', label: 'Specific gang' },
            { value: 'business', label: 'Business / society' }, { value: 'level', label: 'Level gated' }
        ],
        repeatTypes: [
            { value: 'none', label: 'One time only' }, { value: 'hourly', label: 'Every hour' },
            { value: 'daily', label: 'Daily' }, { value: 'weekly', label: 'Weekly' },
            { value: 'monthly', label: 'Monthly' }, { value: 'custom', label: 'Custom cooldown' },
            { value: 'infinite', label: 'Unlimited' }
        ],
        entityTypes: [{ value: 'ped', label: 'NPC (ped)' }, { value: 'object', label: 'Object / prop' }, { value: 'marker', label: 'Marker only' }],
        difficulties: [
            { value: 'easy', label: 'Easy' }, { value: 'normal', label: 'Normal' },
            { value: 'hard', label: 'Hard' }, { value: 'brutal', label: 'Brutal' }
        ],
        categories: ['general', 'delivery', 'crime', 'legal', 'gang', 'story', 'event', 'daily'],
        cooldownPresets: { none: 0, hourly: 3600, daily: 86400, weekly: 604800, monthly: 2592000 },
        defaults: {
            mission: {
                uid: '', name: 'New mission', description: '', category: 'general', icon: 'scroll', enabled: true, order: 0,
                requiredLevel: 0, xpReward: 100, prerequisites: [],
                requirements: { items: [], money: 0 }, objectives: [],
                rewards: { money: 0, bank: 0, black: 0, items: [], xp: 0 },
                restriction: { type: 'all', grade: 0, level: 0 },
                cooldown: { type: 'none', seconds: 0, maxCompletions: 0 },
                alert: { title: '', description: '', sound: 'none', duration: 6000 },
                schedule: { enabled: false, from: 0, to: 24 }, meta: {}
            },
            location: {
                uid: '', name: 'New location', description: '', enabled: true,
                entity: { type: 'ped', model: 'a_m_m_business_01', freeze: true, invincible: true, ignore: true },
                points: [], rotate: { enabled: false, interval: 1800 },
                target: { label: 'Talk', icon: 'fa-solid fa-comments', distance: 2 },
                dialogue: { title: 'Hello there', text: 'I might have something for you...', accept: 'Accept', decline: 'Leave' },
                blip: { enabled: true, sprite: 480, color: 27, scale: 0.8, shortRange: true },
                schedule: { enabled: false, from: 0, to: 24 }, missions: [], meta: {}
            },
            npc: {
                uid: '', name: 'Hostile group', enabled: true, model: 'g_m_y_ballasout_01', count: 3, companions: 0,
                weapons: ['WEAPON_PISTOL'], coords: { x: 0, y: 0, z: 0 }, radius: 25,
                trigger: { type: 'proximity', distance: 90 }, difficulty: 'normal', aggression: 75,
                alertPolice: true, respawn: 300, loot: [], money: { min: 0, max: 0 }, xp: 25, meta: {}
            },
            objective: {
                id: '', type: 'goto', label: 'Objective', item: null, count: 1, money: 0, coords: null,
                radius: 2, duration: 5000, anim: null, model: null, amount: 1, marker: true, blip: true, optional: false
            }
        }
    };

    var BRANDING = {
        brand: 'OQV2 QUESTS', subtitle: 'Unlimited Mission System',
        author: 'Codex Dev: #Alesh48 5654', footer: 'Made with CodeX Dev.', version: '2.0.0'
    };

    function snapshot() {
        return {
            branding: BRANDING,
            ui: { accent: '#e01b84', accentAlt: '#7c4dff' },
            schema: SCHEMA,
            missions: MISSIONS,
            locations: LOCATIONS,
            npcs: NPCS,
            players: [
                { source: 1, name: 'Alesh Codex', identifier: 'char1:a3f9c2', job: 'mechanic', grade: 3, level: 12, xp: 8420, percent: 62, active: 'Night Delivery', completed: 27 },
                { source: 4, name: 'Mia Herrera', identifier: 'char1:88bc1f', job: 'police', grade: 5, level: 21, xp: 24100, percent: 18, active: null, completed: 64 },
                { source: 7, name: 'Deon Walker', identifier: 'char1:5512aa', job: 'unemployed', grade: 0, level: 4, xp: 1900, percent: 81, active: 'Scrap Trade', completed: 6 }
            ],
            logs: [
                { id: 9, identifier: 'char1:a3f9c2', name: 'Alesh Codex', action: 'mission_complete', detail: '{"mission":"m_scrap_trade","rewards":{"money":850,"xp":120}}', created_at: now - 120 },
                { id: 8, identifier: 'char1:88bc1f', name: 'Mia Herrera', action: 'level_up', detail: '{"level":21}', created_at: now - 900 },
                { id: 7, identifier: 'char1:5512aa', name: 'Deon Walker', action: 'mission_start', detail: '{"mission":"m_scrap_trade"}', created_at: now - 1500 },
                { id: 6, identifier: 'char1:a3f9c2', name: 'Alesh Codex', action: 'admin_save_mission', detail: '{"uid":"m_clear_the_block","new":false}', created_at: now - 3600 },
                { id: 5, identifier: 'char1:99ffaa', name: 'Random Guy', action: 'panel_denied', detail: 'denied', created_at: now - 5400 },
                { id: 4, identifier: 'char1:88bc1f', name: 'Mia Herrera', action: 'npc_loot', detail: '{"npc":"npc_block_crew","money":420}', created_at: now - 7200 }
            ],
            leaderboard: [
                { identifier: 'char1:88bc1f', name: 'Mia Herrera', xp: 24100, level: 21, completed: 64 },
                { identifier: 'char1:a3f9c2', name: 'Alesh Codex', xp: 8420, level: 12, completed: 27 },
                { identifier: 'char1:5512aa', name: 'Deon Walker', xp: 1900, level: 4, completed: 6 }
            ],
            stats: {
                missions: 4, missionsEnabled: 3, locations: 3, locationsEnabled: 3,
                npcs: 2, npcsEnabled: 1, playersTracked: 148, completions: 1362,
                activeRuns: 2, topMission: 'm_scrap_trade', online: 3, dbReady: true
            },
            config: { locale: 'en', progression: true, maxLevel: 100, evilNpc: true, journal: true, useDatabase: true }
        };
    }

    function journal() {
        return {
            branding: BRANDING,
            ui: { accent: '#e01b84', accentAlt: '#7c4dff' },
            player: {
                identifier: 'char1:a3f9c2', name: 'Alesh Codex', level: 12, xp: 3120, need: 5000,
                percent: 62, totalXP: 8420, completed: 27, maxLevel: false,
                discovered: ['loc_marco', 'loc_dockhand'],
                active: { uid: 'm_night_delivery', name: 'Night Delivery', icon: 'truck' }
            },
            missions: MISSIONS.map(function (m, i) {
                return {
                    uid: m.uid, name: m.name, description: m.description, category: m.category, icon: m.icon,
                    requiredLevel: m.requiredLevel, xpReward: m.xpReward, rewards: m.rewards,
                    objectives: m.objectives, prerequisites: m.prerequisites,
                    completions: i === 0 ? 4 : 0,
                    available: i < 2, reason: i >= 2 ? 'Complete "Night Delivery" first.' : null,
                    cooldownLeft: i === 0 ? 40320 : 0, locked: false
                };
            }),
            locations: LOCATIONS.map(function (l, i) {
                return { uid: l.uid, name: l.name, missions: l.missions, points: i < 2 ? l.points : null, discovered: i < 2 };
            })
        };
    }

    function tracker() {
        return {
            visible: true,
            mission: {
                uid: 'm_night_delivery', name: 'Night Delivery', icon: 'truck',
                objectives: [
                    { id: 'o2', label: 'Pick up the sealed package', type: 'interact', done: true, have: 1, need: 1, optional: false },
                    { id: 'o3', label: 'Deliver the package at the docks', type: 'deliver', done: false, have: 0, need: 1, optional: false },
                    { id: 'o9', label: 'Avoid the police', type: 'goto', done: false, have: 0, need: 1, optional: true }
                ]
            },
            player: { level: 12, percent: 62, xp: 3120, need: 5000 }
        };
    }

    w.OQ_MOCK = { snapshot: snapshot, journal: journal, tracker: tracker };
})(window);
