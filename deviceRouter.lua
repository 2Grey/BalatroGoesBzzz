-- Protocol v2 device routing. Runtime indexes are never saved as identities.
local Router = {}
Router.__index = Router

local function clamp(value)
    if type(value) ~= 'number' or value ~= value then return 0 end
    return math.max(0, math.min(1, value))
end

function Router.new(send, publish)
    return setmetatable({devices={}, generation=0, send=send, publish=publish}, Router)
end

function Router:list()
    local result = {}
    for _, device in pairs(self.devices) do
        result[#result+1] = {index=device.index, name=device.name,
            features=device.features, generation=device.generation, unnamed=device.unnamed}
    end
    table.sort(result, function(a,b) return a.index < b.index end)
    return result
end

function Router:notify() self.publish(self:list()) end

function Router:describe(info)
    local attrs = (info.DeviceMessages or {}).VibrateCmd
    local count = type(attrs) == 'table' and attrs.FeatureCount
    if type(info.DeviceIndex) ~= 'number' or info.DeviceIndex < 0 or
        info.DeviceIndex % 1 ~= 0 or type(count) ~= 'number' or count < 1 or
        count % 1 ~= 0 then return nil end
    return {index=info.DeviceIndex, name=tostring(info.DeviceName or 'Device'),
        unnamed=info.DeviceName == nil, features=count}
end

function Router:register(info, refresh)
    local device = self:describe(info)
    if not device then return end
    local old = self.devices[device.index]
    if refresh and old and old.name == device.name and old.features == device.features then return end
    self.generation = self.generation + 1
    device.generation = self.generation
    self.devices[device.index] = device
end

function Router:replace(devices)
    local present = {}
    for _, info in ipairs(devices or {}) do
        local device = self:describe(info)
        if device then present[device.index] = true; self:register(info, true) end
    end
    for index in pairs(self.devices) do if not present[index] then self.devices[index] = nil end end
    self:notify()
end

function Router:add(info)
    -- Even a new unsupported device may reuse an old runtime index.
    if type(info.DeviceIndex) == 'number' then self.devices[info.DeviceIndex] = nil end
    self:register(info, false)
    self:notify()
end
function Router:remove(index) self.devices[index] = nil; self:notify() end
function Router:clear() self.devices = {}; self:notify() end

function Router:vibrate(device, value)
    if device.last_strength == value then return end
    local speeds = {}
    for index=0, device.features-1 do speeds[#speeds+1] = {Index=index, Speed=value} end
    self.send('VibrateCmd', {DeviceIndex=device.index, Speeds=speeds})
    device.last_strength = value
end

function Router:output(targets)
    local values = {}
    for _, target in ipairs(targets or {}) do
        local device = self.devices[target.index]
        if device and device.generation == target.generation then
            values[target.index] = clamp(target.strength)
        end
    end
    for index, device in pairs(self.devices) do
        if values[index] ~= nil then
            self:vibrate(device, values[index])
        elseif device.last_strength and device.last_strength > 0 then
            -- Deselecting a device stops only output previously started by us.
            self:vibrate(device, 0)
        end
    end
end

return Router
