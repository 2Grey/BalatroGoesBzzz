-- Native Balatro UI definitions. Runtime actions are provided by the controller.
local tr = require('Mods.BalatroGoesBzzz.translation').get
local version = require('Mods.BalatroGoesBzzz.version')
local Menu = {}

-- Fit text once. Balatro applies container maxw by multiplying live text scales on every layout pass.
local function fit_scale(text, scale, width)
    local font = G.LANG and G.LANG.font
    if not font or not font.FONT or not G.TILESIZE then return scale end
    local unscaled_width = font.FONT:getWidth(text) * font.squish * font.FONTSCALE / G.TILESIZE
    return unscaled_width > 0 and math.min(scale, width / unscaled_width) or scale
end

local function localized_toggle(args)
    args.label_scale = fit_scale(args.label, args.label_scale, args.w - 0.1)
    return create_toggle(args)
end

local function menu_button(args)
    local button = UIBox_button(args)
    for _, row in ipairs(button.nodes[1].nodes) do
        local label = row.nodes[1].config
        row.config.maxw = nil
        label.scale = fit_scale(label.text, label.scale, args.minw - 0.2)
    end
    return button
end

local function text_row(text, scale)
    return {n=G.UIT.R, config={align='cm', padding=0.04}, nodes={
        {n=G.UIT.T, config={text=text, scale=fit_scale(text, scale, 8.4), colour=G.C.UI.TEXT_LIGHT}}}}
end

local status_keys = {'autosave', 'saved', 'save_error', 'saving', 'enable_device', 'enable_event', 'scan_requested'}

local function status_scale()
    local scale = 0.27
    for _, key in ipairs(status_keys) do scale = fit_scale(tr(key), scale, 8.35) end
    return scale
end

local function device_rows(context)
    local manager = context.manager
    local device_page = context.device_page
    local devices, rows = manager.devices or {}, {}
    device_page = math.max(1, math.min(device_page, math.max(1, math.ceil(#devices / 2))))
    rows[#rows+1] = text_row(tr(manager.connection or 'connecting', {detail=manager.connection_detail}), 0.3)
    if #devices == 0 then
        rows[#rows+1] = text_row(tr('no_devices'), 0.27)
    end
    for i=(device_page-1)*2+1, math.min(device_page*2, #devices) do
        local device = devices[i]
        local callback = context.bind_device_test(device)
        rows[#rows+1] = text_row((device.unnamed and tr('device') or device.name)..' (#'..device.index..')', 0.3)
        rows[#rows+1] = {n=G.UIT.R, config={align='cm', padding=0.04}, nodes={
            localized_toggle({col=true, label=tr('use'), ref_table=device, ref_value='selected',
                w=2.5, scale=0.7, label_scale=0.3}),
            create_slider({ref_table=device, ref_value='intensity', min=10, max=100,
                w=2.5, h=0.3, text_scale=0.3, colour=G.C.BLUE}),
            menu_button({col=true, label={tr('test')}, button=callback,
                minw=1.15, minh=0.55, scale=0.32, colour=G.C.BLUE})}}
    end
    rows[#rows+1] = {n=G.UIT.R, config={align='cm', padding=0.04}, nodes={
        menu_button({col=true, label={'<'}, button='balatrogoesbzzz_devices_prev', minw=0.7, minh=0.5, scale=0.3}),
        {n=G.UIT.T, config={text=device_page..' / '..math.max(1,math.ceil(#devices/2)), scale=0.3, colour=G.C.UI.TEXT_LIGHT}},
        menu_button({col=true, label={'>'}, button='balatrogoesbzzz_devices_next', minw=0.7, minh=0.5, scale=0.3}),
        menu_button({col=true, label={tr('scan')}, button='balatrogoesbzzz_devices_scan',
            minw=3.2, minh=0.5, scale=0.3, colour=G.C.BLUE})}}
    context.device_page = device_page
    return rows
end

function Menu.build(context)
    local status, cfg, menu_page = context.status, context.settings, context.page
    status.text = tr(status.key)
    local function event_row(key, label)
        return {n=G.UIT.R, config={align='cm', padding=0.06}, nodes={
            localized_toggle({col=true, label=label, ref_table=cfg, ref_value=key..'_enabled',
                w=3.5, scale=0.7, label_scale=0.32}),
            create_slider({ref_table=cfg, ref_value=key..'_intensity', min=0, max=100,
                w=2.5, h=0.3, text_scale=0.3, colour=G.C.BLUE}),
            menu_button({col=true, label={tr('test')}, button='balatrogoesbzzz_test_'..key,
                minw=1.15, minh=0.55, scale=0.32, colour=G.C.BLUE})}}
    end
    local contents = {
        text_row(tr('title')..' · v'..version, 0.48),
        localized_toggle({label=tr('enabled'), ref_table=cfg, ref_value='enabled',
            w=3.5, scale=0.8, label_scale=0.35}),
        {n=G.UIT.R, config={align='cm', padding=0.05}, nodes={
            menu_button({col=true, label={tr('tab_cards')}, button='balatrogoesbzzz_page_cards',
                minw=2.3, minh=0.55, scale=0.3, colour=menu_page == 1 and G.C.BLUE or G.C.GREY}),
            menu_button({col=true, label={tr('tab_events')}, button='balatrogoesbzzz_page_events',
                minw=2.3, minh=0.55, scale=0.3, colour=menu_page == 2 and G.C.BLUE or G.C.GREY}),
            menu_button({col=true, label={tr('tab_devices')}, button='balatrogoesbzzz_page_devices',
                minw=2.3, minh=0.55, scale=0.3, colour=menu_page == 3 and G.C.BLUE or G.C.GREY})}},
        text_row(menu_page == 3 and tr('device_strength') or
            tr('event_header'), 0.28),
        text_row(menu_page == 3 and tr('device_hint') or
            tr('event_hint'), 0.25),
        {n=G.UIT.R, config={align='cm', padding=0.08}, nodes={
            menu_button({col=true, label={tr('stop_test')}, button='balatrogoesbzzz_stop_test',
                minw=2.7, minh=0.55, scale=0.32, colour=G.C.RED}),
            menu_button({col=true, label={tr('reset')}, button='balatrogoesbzzz_reset',
                minw=2.7, minh=0.55, scale=0.32, colour=G.C.ORANGE})}},
        {n=G.UIT.R, config={align='cm', padding=0.06}, nodes={
            {n=G.UIT.T, config={ref_table=status, ref_value='text', scale=status_scale(),
                colour=G.C.UI.TEXT_LIGHT}}}},
    }
    local rows
    if menu_page == 1 then
        rows = {
        event_row('card', tr('card')),
        event_row('scoring', tr('scoring')),
        event_row('flame', tr('flame')),
        {n=G.UIT.R, config={align='cm', padding=0.08}, nodes={
            {n=G.UIT.T, config={text=tr('card_duration'), scale=0.32, colour=G.C.UI.TEXT_LIGHT}},
            create_slider({ref_table=cfg, ref_value='card_duration_ms', min=40, max=400,
                w=2.5, h=0.3, text_scale=0.3, colour=G.C.BLUE})}},
        }
    elseif menu_page == 2 then
        rows = {
            event_row('discard', tr('discard')),
            event_row('purchase', tr('purchase')),
            event_row('booster', tr('booster')),
            event_row('blind', tr('blind')),
            {n=G.UIT.R, config={align='cm', padding=0.04}, nodes={
                menu_button({label={tr('test_loss')}, button='balatrogoesbzzz_test_blind_loss',
                    minw=3, minh=0.5, scale=0.3, colour=G.C.RED})}},
        }
    else
        rows = device_rows(context)
    end
    for i, row in ipairs(rows) do table.insert(contents, 4+i, row) end
    return create_UIBox_generic_options({contents={
        {n=G.UIT.C, config={align='cm', padding=0.04}, nodes=contents}},
        back_func='balatrogoesbzzz_close', back_label=tr('done'), minw=8.5, padding=0.08})
end

return Menu
