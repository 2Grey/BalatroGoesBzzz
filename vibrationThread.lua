require 'love'
require 'love.filesystem'
require 'love.timer'
local json = require('Mods.BalatroBuzz.json')
local websocket = require('Mods.BalatroBuzz.websocket')
local Router = require('Mods.BalatroBuzz.deviceRouter')
local input = love.thread.getChannel('vibration_channel_in')
local output = love.thread.getChannel('vibration_channel_out')
local host, port = input:demand(), input:demand()
-- Send language-neutral status codes; UI translation belongs to the main thread.
local client, connected, connection = nil, false, 'connecting'
local connection_detail
local message_id, max_ping, last_ping = 0, 0, 0

local function send(kind, body)
    if not client then return end
    message_id = message_id + 1
    body.Id = message_id
    client:send(json.encode({{[kind]=body}}))
end
local router = Router.new(send, function(devices)
    output:push({type='devices', devices=devices, connection=connection, connection_detail=connection_detail})
end)
local function disconnect(reason, detail)
    connected, max_ping, connection = false, 0, reason or 'disconnected'
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
        send('RequestServerInfo', {ClientName='BalatroBuzz', MessageVersion=2})
    end
    function client:onmessage(data)
        local ok, messages = pcall(json.decode, data)
        if not ok or type(messages) ~= 'table' then return end
        for _, envelope in ipairs(messages) do
            for kind, body in pairs(envelope) do
                if kind == 'ServerInfo' then
                    connected, connection, connection_detail = true, 'connected', nil
                    max_ping = tonumber(body.MaxPingTime) or 0
                    last_ping = love.timer.getTime()
                    router:notify()
                    refresh()
                elseif kind == 'DeviceList' then router:replace(body.Devices)
                elseif kind == 'DeviceAdded' then router:add(body)
                elseif kind == 'DeviceRemoved' then router:remove(body.DeviceIndex)
                elseif kind == 'Error' then
                    output:push('[BalatroBuzz] Intiface: '..tostring(body.ErrorMessage))
                end
            end
        end
    end
    function client:onclose(_, reason) disconnect(reason and 'closed_reason' or 'closed', reason) end
    function client:onerror(reason) disconnect('connection_error', reason) end
end
connect()
while true do
    client:update()
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
