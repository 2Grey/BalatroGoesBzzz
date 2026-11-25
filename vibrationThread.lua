-- Loaded lazily in a separate Lua state through Lovely.
return function(host, port)
    require 'love'
    require 'love.filesystem'
    require 'love.timer'
    local json = require('Mods.BalatroGoesBzzz.json')
    local websocket = require('Mods.BalatroGoesBzzz.websocket')
    local Router = require('Mods.BalatroGoesBzzz.deviceRouter')
    local input = love.thread.getChannel('vibration_channel_in')
    local output = love.thread.getChannel('vibration_channel_out')
    -- Send language-neutral status codes; UI translation belongs to the main thread.
    local client, connected, connection = nil, false, 'connecting'
    local connection_detail, server_info_deadline
    local message_id, max_ping, last_ping = 0, 0, 0

    local function send(kind, body)
        if not client then return false end
        message_id = message_id + 1
        body.Id = message_id
        return client:send(json.encode({{[kind]=body}}))
    end
    local router = Router.new(send, function(devices)
        output:push({type='devices', devices=devices, connection=connection, connection_detail=connection_detail})
    end)
    local function disconnect(reason, detail)
        connected, max_ping, connection = false, 0, reason or 'disconnected'
        server_info_deadline = nil
        connection_detail = detail and tostring(detail) or nil
        router:clear()
    end
    local function refresh()
        send('RequestDeviceList', {})
        send('StartScanning', {})
    end
    local function connect()
        disconnect('connecting')
        client = websocket.new(host, port, '/')
        function client:onopen()
            server_info_deadline = love.timer.getTime() + 5
            send('RequestServerInfo', {ClientName='BalatroGoesBzzz', MessageVersion=2})
        end
        function client:onmessage(data)
            local ok, messages = pcall(json.decode, data)
            if not ok or type(messages) ~= 'table' then return end
            for _, envelope in ipairs(messages) do
                for kind, body in pairs(envelope) do
                    if kind == 'ServerInfo' then
                        connected, connection, connection_detail = true, 'connected', nil
                        server_info_deadline = nil
                        max_ping = tonumber(body.MaxPingTime) or 0
                        last_ping = love.timer.getTime()
                        router:notify()
                        refresh()
                    elseif kind == 'DeviceList' then router:replace(body.Devices)
                    elseif kind == 'DeviceAdded' then router:add(body)
                    elseif kind == 'DeviceRemoved' then router:remove(body.DeviceIndex)
                    elseif kind == 'Error' then
                        output:push('[BalatroGoesBzzz] Intiface: '..tostring(body.ErrorMessage))
                    end
                end
            end
        end
        function client:onclose(_, reason) disconnect(reason ~= '' and reason and 'closed_reason' or 'closed', reason) end
        function client:onerror(reason) disconnect('connection_error', reason) end
    end
    connect()
    while true do
        client:update()
        if server_info_deadline and love.timer.getTime() >= server_info_deadline then
            client:fail('Intiface protocol handshake timed out')
        end
        if client.status == websocket.STATUS.CLOSED and connected then
            disconnect('closed')
        end
        local latest, scan = nil, false
        local data = input:pop()
        while data ~= nil do
            if type(data) == 'table' then
                if data.type == 'output' then latest = data.targets
                elseif data.type == 'scan' then scan = true end
            end
            data = input:pop()
        end
        if scan then
            if connected then refresh()
            elseif client.status == websocket.STATUS.CLOSED then connect() end
        end
        if connected and latest then router:output(latest) end
        if connected and max_ping > 0 and love.timer.getTime() - last_ping >= max_ping / 2000 then
            send('Ping', {})
            last_ping = love.timer.getTime()
        end
        love.timer.sleep(0.005)
    end
end
