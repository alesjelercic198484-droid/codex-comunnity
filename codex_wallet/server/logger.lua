--[[
    CodeX Wallet - logging module

    Levels: DEBUG < INFO < WARN < ERROR
    Destinations: server console, resource log file, Discord webhook.
]]

Logger = {}

local LEVELS = {
    DEBUG = 10,
    INFO = 20,
    WARN = 30,
    ERROR = 40
}

Logger.LEVELS = LEVELS

local function currentLevel()
    local name = (Config.Logging and Config.Logging.Level) or 'INFO'
    return LEVELS[string.upper(tostring(name))] or LEVELS.INFO
end

local function shouldLog(level)
    return (LEVELS[level] or 0) >= currentLevel()
end

local function timestamp()
    return os.date('%Y-%m-%d %H:%M:%S')
end

local function flatten(context)
    if type(context) ~= 'table' then
        return ''
    end

    local parts = {}
    for key, value in pairs(context) do
        parts[#parts + 1] = ('%s=%s'):format(tostring(key), tostring(value))
    end
    table.sort(parts)
    return table.concat(parts, ' ')
end

local function appendFile(line)
    if not Config.Logging or not Config.Logging.File then
        return
    end

    local resource = GetCurrentResourceName()
    local dir = Config.Logging.FileDir or 'logs'
    local name = Config.Logging.FileName or 'wallet.log'
    local path = ('%s/%s'):format(dir, name)

    local previous = LoadResourceFile(resource, path) or ''
    -- Keep the file from growing without bounds (last ~200 KB).
    if #previous > 200000 then
        previous = previous:sub(-100000)
    end

    SaveResourceFile(resource, path, previous .. line .. '\n', -1)
end

local function sendWebhook(level, event, message, context)
    local url = (Config.Logging and Config.Logging.Webhook) or ''
    url = GetConvar('codex_wallet:webhook', url)

    if not url or url == '' then
        return
    end

    local colours = {
        DEBUG = 0x9CA3AF,
        INFO = 0x3B82F6,
        WARN = 0xF59E0B,
        ERROR = 0xEF4444
    }

    local flat = flatten(context)
    local description = ('**%s**\n%s'):format(event, message or '')
    if flat ~= '' then
        description = description .. '\n```' .. flat .. '```'
    end

    local payload = {
        username = (Config.Logging and Config.Logging.WebhookName) or 'CodeX Wallet',
        embeds = {
            {
                title = ('[%s] %s'):format(level, timestamp()),
                description = description,
                color = colours[level] or 0x9CA3AF
            }
        }
    }

    PerformHttpRequest(url, function(status)
        if status ~= 200 and status ~= 204 then
            print(('[%s] Logger: Discord webhook failed with status %s'):format('codex_wallet', tostring(status)))
        end
    end, 'POST', json.encode(payload), { ['Content-Type'] = 'application/json' })
end

--- Log a wallet event.
-- @param level   'DEBUG' | 'INFO' | 'WARN' | 'ERROR'
-- @param event   short event name, e.g. 'deposit'
-- @param message human readable message
-- @param context optional table with structured data
function Logger.Log(level, event, message, context)
    level = string.upper(tostring(level or 'INFO'))
    if not LEVELS[level] then
        level = 'INFO'
    end

    if not shouldLog(level) then
        return
    end

    local line = ('[%s] [%s] [%s] %s'):format(timestamp(), level, tostring(event or 'general'), tostring(message or ''))
    local flat = flatten(context)
    if flat ~= '' then
        line = line .. ' | ' .. flat
    end

    if Config.Debug or (Config.Logging and Config.Logging.Console) then
        print(('[codex_wallet] %s'):format(line))
    end

    local ok, err = pcall(appendFile, line)
    if not ok then
        print(('[codex_wallet] Logger file error: %s'):format(tostring(err)))
    end

    ok, err = pcall(sendWebhook, level, event, message, context)
    if not ok then
        print(('[codex_wallet] Logger webhook error: %s'):format(tostring(err)))
    end
end

function Logger.Debug(event, message, context)
    Logger.Log('DEBUG', event, message, context)
end

function Logger.Info(event, message, context)
    Logger.Log('INFO', event, message, context)
end

function Logger.Warn(event, message, context)
    Logger.Log('WARN', event, message, context)
end

function Logger.Error(event, message, context)
    Logger.Log('ERROR', event, message, context)
end

return Logger
