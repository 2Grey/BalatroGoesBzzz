-- Owns validation, migration, persistence and delayed saves.
local json = require('Mods.BalatroGoesBzzz.json')
local Settings = {}

function Settings.new(defaults, set_status)
    local settings_path = 'Mods/BalatroGoesBzzz/settings.json'
    local config, saved_signature, changed_at, pending_signature
    local keys = {}
    for key in pairs(defaults) do keys[#keys+1] = key end
    table.sort(keys)

    local function sanitize(data)
        local result = {}
        for key, default in pairs(defaults) do
            local value
            if type(data) == 'table' then
                value = data[key]
                if key == 'device_default_intensity' and value == nil then value = data.master_intensity end
            end
            if type(default) == 'boolean' then
                if type(value) ~= 'boolean' then value = default end
                result[key] = value
            else
                if type(value) ~= 'number' or value ~= value or math.abs(value) == math.huge then value = default end
                local minimum, maximum = 0, 100
                if key == 'device_default_intensity' then minimum = 10 end
                if key == 'card_duration_ms' then minimum, maximum = 40, 400 end
                result[key] = math.max(minimum, math.min(maximum, value))
            end
        end
        result.device_intensities = {}
        if type(data) == 'table' and type(data.device_intensities) == 'table' then
            for name, value in pairs(data.device_intensities) do
                if type(name) == 'string' and type(value) == 'number' and value == value then
                    result.device_intensities[name] = math.max(10, math.min(100, value))
                end
            end
        end
        return result
    end

    local function signature(data)
        local values = {}
        for _, key in ipairs(keys) do values[#values+1] = key..'='..tostring(data[key]) end
        local devices = {}
        for name in pairs(data.device_intensities or {}) do devices[#devices+1] = name end
        table.sort(devices)
        for _, name in ipairs(devices) do
            values[#values+1] = #name..':'..name..'='..tostring(data.device_intensities[name])
        end
        return table.concat(values, ':')
    end

    local function settings()
        if not config then
            local data
            local ok, content = pcall(love.filesystem.read, settings_path)
            if ok and content then
                local decoded, value = pcall(json.decode, content)
                if decoded then data = value else print('[BalatroGoesBzzz] Invalid settings; using defaults') end
            end
            config = sanitize(data)
            saved_signature = signature(config)
        end
        return config
    end

    local function save_settings()
        local data = sanitize(settings())
        local ok, result, reason = pcall(function()
            return love.filesystem.write(settings_path, json.encode(data))
        end)
        if ok and result then
            saved_signature = signature(config)
            pending_signature, changed_at = nil, nil
            set_status('saved')
            return true
        end
        set_status('save_error')
        print('[BalatroGoesBzzz] Could not save settings: '..tostring(reason or result))
        pending_signature = signature(config)
        changed_at = love.timer.getTime() + 5 -- Retry without flooding the log every frame.
        return false
    end

    local function update()
        local cfg, now = settings(), love.timer.getTime()
        local current = signature(cfg)
        if current == saved_signature then
            if pending_signature then set_status('saved') end
            pending_signature, changed_at = nil, nil
        else
            if current ~= pending_signature then
                pending_signature, changed_at = current, now
                set_status('saving')
            elseif changed_at and now - changed_at > 0.4 then save_settings() end
        end
    end

    local function reset()
        local cfg = settings()
        for key, value in pairs(defaults) do cfg[key] = value end
        cfg.device_intensities = {}
        return cfg
    end

    return {get=settings, save=save_settings, update=update, reset=reset}
end

return Settings
