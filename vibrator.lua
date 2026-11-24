-- BalatroGoesBzzz: event feedback and touch-accessible settings.
local Settings = require('Mods.BalatroGoesBzzz.settings')
local Feedback = require('Mods.BalatroGoesBzzz.feedback')
local Menu = require('Mods.BalatroGoesBzzz.menu')
local tr = require('Mods.BalatroGoesBzzz.translation').get
local version = require('Mods.BalatroGoesBzzz.version')

print('[BalatroGoesBzzz] Loaded v'..version)
local defaults = {
    enabled = true,
    device_default_intensity = 100,
    card_enabled = true, card_intensity = {{lovely:card_pulse_strength}} * 100,
    card_duration_ms = {{lovely:card_pulse_duration}} * 1000,
    scoring_enabled = true, scoring_intensity = {{lovely:scoring_strength}} * 100,
    flame_enabled = true, flame_intensity = {{lovely:flame_strength}} * 100,
    discard_enabled = true, discard_intensity = 25,
    purchase_enabled = true, purchase_intensity = 30,
    booster_enabled = true, booster_intensity = 40,
    blind_enabled = true, blind_intensity = 60,
}
local menu
local test = {}
local return_to_options = false
local menu_page = 1
local device_page = 1
local rebuild_menu
local status = {key = 'autosave'}

local function set_status(key)
    status.key, status.text = key, tr(key)
end

local store = Settings.new(defaults, set_status)
local settings, save_settings = store.get, store.save

local worker_threads = setmetatable({}, {__mode='k'})

local function install_thread_error_handler()
    local previous = love.threaderror
    love.threaderror = function(thread, detail)
        if worker_threads[thread] then
            local manager = G.VIBRATION_MANAGER
            if manager and manager.thread == thread then manager.thread_error = tostring(detail) end
        elseif previous then
            return previous(thread, detail)
        else
            error(detail, 0)
        end
    end
end

local function start_vibration_thread(manager)
    manager.in_channel:clear()
    manager.out_channel:clear()
    manager.output_signature = nil
    manager.thread_error, manager.worker_stopped = nil, nil
    manager.thread = nil
    manager.connection, manager.connection_detail = 'connecting', nil
    manager.devices_dirty = true

    local ok, result = pcall(function()
        local thread = love.thread.newThread('/Mods/BalatroGoesBzzz/vibrationThread.lua')
        worker_threads[thread] = true
        thread:start('{{lovely:intiface_host}}', {{lovely:intiface_port}})
        return thread
    end)
    if ok then manager.thread = result
    else manager.thread_error = tostring(result) end
end

local function ensure_vibration_manager()
    if not G.VIBRATION_MANAGER then
        local manager = {
            in_channel = love.thread.getChannel('vibration_channel_in'),
            out_channel = love.thread.getChannel('vibration_channel_out'),
        }
        G.VIBRATION_MANAGER = manager
        install_thread_error_handler()
        start_vibration_thread(manager)
    end
    return G.VIBRATION_MANAGER
end

local function report_thread_failure(manager)
    local thread = manager.thread
    if thread and thread:isRunning() then return end
    if manager.worker_stopped then return end
    local detail = manager.thread_error or (thread and thread:getError()) or 'Intiface worker stopped'
    manager.worker_stopped = true
    manager.connection, manager.connection_detail = 'connection_error', detail
    manager.devices, manager.devices_dirty = {}, true
    manager.in_channel:clear()
    manager.out_channel:clear()
    print('[BalatroGoesBzzz] '..detail)
end

local function receive_devices(manager, message)
    local previous = manager.devices or {}
    local old, counts, devices = {}, {}, {}
    for _, device in ipairs(previous) do old[device.index] = device end
    for _, device in ipairs(message.devices or {}) do counts[device.name] = (counts[device.name] or 0) + 1 end
    local cfg = settings()
    manager.ambiguous_names = manager.ambiguous_names or {}
    for name, count in pairs(counts) do
        if count > 1 then
            manager.ambiguous_names[name] = true
            cfg.device_intensities[name] = nil
        end
    end
    for _, info in ipairs(message.devices or {}) do
        local device = old[info.index]
        if not device or device.generation ~= info.generation or device.name ~= info.name or device.unnamed ~= info.unnamed then
            device = {index=info.index, name=info.name, unnamed=info.unnamed, generation=info.generation,
                selected=false, intensity=not manager.ambiguous_names[info.name] and cfg.device_intensities[info.name]
                    or cfg.device_default_intensity}
            device.intensity = device.intensity or cfg.device_default_intensity
        end
        -- Protocol v2 has no persistent hardware ID. Never merge identical names.
        device.profile_name = not manager.ambiguous_names[info.name] and info.name or nil
        devices[#devices+1] = device
    end
    table.sort(devices, function(a,b) return a.index < b.index end)
    local changed = #devices ~= #previous or manager.connection ~= message.connection or
        manager.connection_detail ~= message.connection_detail
    if not changed then
        for i, device in ipairs(devices) do
            if device ~= previous[i] then changed = true; break end
        end
    end
    manager.devices, manager.connection = devices, message.connection
    manager.connection_detail = message.connection_detail
    manager.devices_dirty = manager.devices_dirty or changed
end

local function output_devices(manager, strength, cfg)
    local targets, parts = {}, {}
    for _, device in ipairs(manager.devices or {}) do
        if device.profile_name then cfg.device_intensities[device.profile_name] = device.intensity end
        if device.selected then
            local value = strength * device.intensity / 100
            if test.event == 'device' and (device.index ~= test.device_index or
                device.generation ~= test.device_generation) then value = 0 end
            targets[#targets+1] = {index=device.index, generation=device.generation, strength=value}
            parts[#parts+1] = device.index..'/'..device.generation..'='..tostring(value)
        end
    end
    local current = table.concat(parts, ':')
    if not manager.worker_stopped and current ~= manager.output_signature then
        manager.in_channel:push({type='output', targets=targets})
        manager.output_signature = current
    end
end

local function apply_vibration(manager)
    local cfg = settings()
    local strength = Feedback.strength(manager, cfg, love.timer.getTime(), G, test,
        menu and G.OVERLAY_MENU == menu)
    output_devices(manager, strength, cfg)
    manager.strength = strength
end

function balatrogoesbzzz_scoring_vibrate(intensity)
    local manager, cfg = ensure_vibration_manager(), settings()
    if cfg.enabled and cfg.scoring_enabled and (tonumber(intensity) or 0) > 0 then
        manager.scoring_until = love.timer.getTime() + 2
    else
        manager.scoring_until = nil
    end
    apply_vibration(manager)
end

function balatrogoesbzzz_card_pulse()
    local manager, cfg = ensure_vibration_manager(), settings()
    if cfg.enabled and cfg.card_enabled then
        manager.pulse_until = love.timer.getTime() + cfg.card_duration_ms / 1000
    end
    apply_vibration(manager)
end

function balatrogoesbzzz_event(key, variant)
    if not Feedback.priorities[key] then return end
    local manager, cfg = ensure_vibration_manager(), settings()
    if not cfg.enabled or not cfg[key..'_enabled'] or G.SETTINGS.paused then return end
    local now = love.timer.getTime()
    Feedback.sequence_value(manager, now, cfg)
    local previous = manager.buzz_event
    if previous and Feedback.priorities[previous.key] > Feedback.priorities[key] then return end
    local pattern = key == 'blind' and variant == 'loss' and 'blind_loss' or key
    manager.buzz_event = {key=key, pattern=pattern, started=now}
    if key == 'blind' then manager.scoring_until, manager.pulse_until = nil, nil end
    apply_vibration(manager)
end

local function bind_device_test(device)
    local manager = ensure_vibration_manager()
    local callback = 'balatrogoesbzzz_test_device_'..device.index
    local generation = device.generation
    G.FUNCS[callback] = function()
        if not menu or G.OVERLAY_MENU ~= menu then return end
        local found = false
        for _, current in ipairs(manager.devices or {}) do
            if current == device and current.generation == generation then found = true end
        end
        if not found or not device.selected or not settings().enabled then
            set_status('enable_device')
            return
        end
        test.event, test.variant, test.until_time = 'device', nil, love.timer.getTime()+1
        test.device_index, test.device_generation = device.index, device.generation
        apply_vibration(manager)
    end
    return callback
end

local function build_menu()
    local context = {
        settings=settings(), status=status, page=menu_page, device_page=device_page,
        manager=ensure_vibration_manager(), bind_device_test=bind_device_test,
    }
    local definition = Menu.build(context)
    device_page = context.device_page
    return definition
end

local function open_menu()
    G.SETTINGS.paused = true
    G.FUNCS.overlay_menu({definition=build_menu(), config={offset={x=0,y=0}}})
    menu = G.OVERLAY_MENU
    apply_vibration(ensure_vibration_manager())
end

rebuild_menu = function()
    local manager = ensure_vibration_manager()
    if menu and G.OVERLAY_MENU == menu and menu_page == 3 then
        G.FUNCS.balatrogoesbzzz_stop_test()
        G.FUNCS.exit_overlay_menu()
        open_menu()
    end
    manager.devices_dirty = nil
end

local function register_callbacks()
    if G.FUNCS.balatrogoesbzzz_close then return end
    local exit_overlay = G.FUNCS.exit_overlay_menu
    G.FUNCS.exit_overlay_menu = function(...)
        if menu and G.OVERLAY_MENU == menu then
            test.event, test.until_time = nil, nil
            apply_vibration(ensure_vibration_manager())
            save_settings()
            menu = nil
        end
        return exit_overlay(...)
    end
    G.FUNCS.balatrogoesbzzz_open = function()
        -- Leave the options overlay first to balance the native cursor context.
        G.FUNCS.exit_overlay_menu()
        return_to_options = true
        open_menu()
    end
    G.FUNCS.balatrogoesbzzz_close = function()
        local back_to_options = return_to_options
        return_to_options = false
        G.FUNCS.exit_overlay_menu()
        if back_to_options then G.FUNCS.options() end
    end
    G.FUNCS.balatrogoesbzzz_stop_test = function()
        test.event, test.until_time = nil, nil
        apply_vibration(ensure_vibration_manager())
    end
    for _, entry in ipairs({{'card'}, {'scoring'}, {'flame'}, {'discard'},
        {'purchase'}, {'booster'}, {'blind'}, {'blind', 'blind_loss'}}) do
        local key = entry[1]
        local event_key, variant = key, entry[2]
        G.FUNCS['balatrogoesbzzz_test_'..(variant or key)] = function()
            if not menu or G.OVERLAY_MENU ~= menu then return end
            if not settings().enabled or not settings()[event_key..'_enabled'] then
                set_status('enable_event')
                return
            end
            test.event, test.variant, test.until_time = event_key, variant, love.timer.getTime() + 1
            apply_vibration(ensure_vibration_manager())
        end
    end
    local function change_page(page)
        G.FUNCS.balatrogoesbzzz_stop_test()
        G.FUNCS.exit_overlay_menu()
        menu_page = page
        open_menu()
    end
    G.FUNCS.balatrogoesbzzz_page_cards = function() change_page(1) end
    G.FUNCS.balatrogoesbzzz_page_events = function() change_page(2) end
    G.FUNCS.balatrogoesbzzz_page_devices = function() change_page(3) end
    G.FUNCS.balatrogoesbzzz_devices_prev = function()
        device_page = math.max(1, device_page-1)
        rebuild_menu()
    end
    G.FUNCS.balatrogoesbzzz_devices_next = function()
        device_page = device_page+1
        rebuild_menu()
    end
    G.FUNCS.balatrogoesbzzz_devices_scan = function()
        local manager = ensure_vibration_manager()
        report_thread_failure(manager)
        if manager.worker_stopped then start_vibration_thread(manager)
        else manager.in_channel:push({type='scan'}) end
        set_status('scan_requested')
    end
    G.FUNCS.balatrogoesbzzz_reset = function()
        G.FUNCS.balatrogoesbzzz_stop_test()
        local cfg = store.reset()
        for _, device in ipairs(ensure_vibration_manager().devices or {}) do
            device.intensity = cfg.device_default_intensity
        end
        save_settings()
        -- Close first so the native cursor context does not accumulate another layer.
        G.FUNCS.exit_overlay_menu()
        open_menu()
    end
end

function balatrogoesbzzz_toggle_menu()
    if not G or not G.FUNCS or not G.FUNCS.exit_overlay_menu or not G.CONTROLLER or
        not G.ROOM or not G.SETTINGS or G.CONTROLLER.text_input_hook then return false end
    register_callbacks()
    if menu and G.OVERLAY_MENU == menu then
        G.FUNCS.balatrogoesbzzz_close()
        return true
    end
    if G.OVERLAY_MENU or G.SETTINGS.paused then return true end
    open_menu()
    return true
end

function update_vibrator()
    status.text = tr(status.key)
    local manager = ensure_vibration_manager()
    register_callbacks()
    if menu and G.OVERLAY_MENU ~= menu then
        test.event, test.until_time, menu = nil, nil, nil
        save_settings()
    end
    report_thread_failure(manager)
    local out = manager.out_channel:pop()
    while out do
        if type(out) == 'table' and out.type == 'devices' then
            receive_devices(manager, out)
        elseif type(out) == 'string' then print(out) end
        out = manager.out_channel:pop()
    end
    -- Allow the controller to finish a click, touch or drag before replacing the overlay.
    local controller = G.CONTROLLER
    local pointer_active = controller and (controller.is_cursor_down or controller.L_cursor_queue or
        (controller.dragging and controller.dragging.target))
    if manager.devices_dirty and not pointer_active then rebuild_menu() end
    apply_vibration(manager)
    store.update()
end
