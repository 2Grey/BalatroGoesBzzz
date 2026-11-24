--[[
websocket client pure lua implement for love2d
by flaribbit

usage:
    local client = require("websocket").new("127.0.0.1", 5000)
    function client:onmessage(s) print(s) end
    function client:onopen() self:send("hello from love2d") end
    function client:onclose() print("closed") end

    function love.update()
        client:update()
    end
]]

local socket = require"socket"
local bit = require"bit"
local band, bor, bxor = bit.band, bit.bor, bit.bxor
local shl, shr = bit.lshift, bit.rshift
local seckey = "osT3F7mvlojIvf3/8uIsJQ=="
local CONNECT_TIMEOUT = 5
local WRITE_TIMEOUT = 2
local MAX_QUEUED_BYTES = 65536
local MAX_HEADER_BYTES = 8192

local OPCODE = {
    CONTINUE = 0,
    TEXT     = 1,
    BINARY   = 2,
    CLOSE    = 8,
    PING     = 9,
    PONG     = 10,
}

local STATUS = {
    CONNECTING = 0,
    OPEN       = 1,
    CLOSING    = 2,
    CLOSED     = 3,
    TCPOPENING = 4,
}

---@class wsclient
---@field socket table
---@field url table
---@field _head integer|nil
local _M = {
    OPCODE = OPCODE,
    STATUS = STATUS,
}
_M.__index = _M
function _M:onopen() end
function _M:onmessage(message) end
function _M:onerror(error) end
function _M:onclose(code, reason) end

---create websocket connection
---@param host string
---@param port integer
---@param path string
---@return wsclient
function _M.new(host, port, path)
    local m = {
        url = {
            host = host,
            port = port,
            path = path or "/",
        },
        _continue = "",
        _buffer = "",
        _length = 2,
        _head = nil,
        _deadline = socket.gettime() + CONNECT_TIMEOUT,
        _writes = {},
        _queued_bytes = 0,
        _http_partial = "",
        _http_bytes = 0,
        status = STATUS.TCPOPENING,
        socket = socket.tcp(),
    }
    m.socket:settimeout(0)
    setmetatable(m, _M)
    return m
end

local mask_key = {1, 14, 5, 14}
local function frame(opcode, message)
    message = message or ""
    local length = #message
    local header = string.char(bor(0x80, opcode))
    if length > 65535 then
        header = header..string.char(0xff, 0, 0, 0, 0,
            band(shr(length, 24), 0xff), band(shr(length, 16), 0xff),
            band(shr(length, 8), 0xff), band(length, 0xff))
    elseif length > 125 then
        header = header..string.char(0xfe, band(shr(length, 8), 0xff), band(length, 0xff))
    else
        header = header..string.char(bor(length, 0x80))
    end

    local masked = {}
    for i = 1, length do
        masked[i] = string.char(bxor(message:byte(i), mask_key[(i-1)%4+1]))
    end
    return header..string.char(unpack(mask_key))..table.concat(masked)
end

function _M:fail(reason)
    if self.status == STATUS.CLOSED then return end
    self.status = STATUS.CLOSED
    self.socket:close()
    self._writes, self._queued_bytes = {}, 0
    self:onerror(reason)
end

function _M:queue(data)
    if self.status == STATUS.CLOSED then return false end
    if self._queued_bytes + #data > MAX_QUEUED_BYTES then
        self:fail("WebSocket write queue is full")
        return false
    end
    self._writes[#self._writes+1] = {data=data, offset=1, queued=socket.gettime()}
    self._queued_bytes = self._queued_bytes + #data
    return true
end

function _M:flush()
    for _ = 1, 32 do
        local entry = self._writes[1]
        if not entry then return true end
        if socket.gettime() - entry.queued >= WRITE_TIMEOUT then
            self:fail("WebSocket write timed out")
            return false
        end
        -- LuaSocket returns the index of the last byte sent, including on timeout.
        local last, err, partial = self.socket:send(entry.data, entry.offset)
        entry.offset = (last or partial or (entry.offset - 1)) + 1
        if not last and err ~= "timeout" then
            self:fail(err or "WebSocket write failed")
            return false
        end
        if entry.offset <= #entry.data then return true end
        self._queued_bytes = self._queued_bytes - #entry.data
        table.remove(self._writes, 1)
    end
    return true
end

function _M:send_frame(opcode, message)
    if self.status ~= STATUS.OPEN and self.status ~= STATUS.CLOSING then return false end
    return self:queue(frame(opcode, message))
end

---read a message
---@return string|nil res message
---@return number|nil head websocket frame header
---@return string|nil err error message
function _M:read()
    local res, err, part
    ::RECIEVE::
    res, err, part = self.socket:receive(self._length-#self._buffer)
    if err=="closed" then return nil, nil, err end
    if part or res then
        self._buffer = self._buffer..(part or res)
    else
        return nil, nil, nil
    end
    if not self._head then
        if #self._buffer<2 then
            return nil, nil, "buffer length less than 2"
        end
        local length = band(self._buffer:byte(2), 0x7f)
        if length==126 then
            if self._length==2 then self._length = 4 goto RECIEVE end
            if #self._buffer<4 then
                return nil, nil, "buffer length less than 4"
            end
            local b1, b2 = self._buffer:byte(3, 4)
            self._length = shl(b1, 8) + b2
        elseif length==127 then
            if self._length==2 then self._length = 10 goto RECIEVE end
            if #self._buffer<10 then
                return nil, nil, "buffer length less than 10"
            end
            local b5, b6, b7, b8 = self._buffer:byte(7, 10)
            self._length = shl(b5, 24) + shl(b6, 16) + shl(b7, 8) + b8
        else
            self._length = length
        end
        self._head, self._buffer = self._buffer:byte(1), ""
        if length>0 then goto RECIEVE end
    end
    if #self._buffer>=self._length then
        local ret, head = self._buffer, self._head
        self._length, self._buffer, self._head = 2, "", nil
        return ret, head, nil
    else
        return nil, nil, "buffer length less than "..self._length
    end
end

---send a message
---@param message string
function _M:send(message)
    return self:send_frame(OPCODE.TEXT, message)
end

---send a ping message
---@param message string
function _M:ping(message)
    return self:send_frame(OPCODE.PING, message)
end

---send a pong message (no need)
---@param message any
function _M:pong(message)
    return self:send_frame(OPCODE.PONG, message)
end

function _M:read_upgrade()
    for _ = 1, 32 do
        local line, err, partial = self.socket:receive("*l", self._http_partial)
        if self._http_bytes + #(line or partial or "") > MAX_HEADER_BYTES then
            return self:fail("WebSocket response headers are too large")
        end
        if not line then
            if err ~= "timeout" then return self:fail(err or "WebSocket upgrade failed") end
            self._http_partial = partial or self._http_partial
            return
        end
        self._http_partial = ""
        self._http_bytes = self._http_bytes + #line + 2
        if not self._http_status then
            if not line:match("^HTTP/1%.[01]%s+101%s") and not line:match("^HTTP/1%.[01]%s+101$") then
                return self:fail("WebSocket server refused the upgrade")
            end
            self._http_status = true
        elseif line == "" then
            self.status = STATUS.OPEN
            self:onopen()
            return
        end
    end
end

function _M:update()
    if self.status == STATUS.CLOSED then return end
    local sock = self.socket
    if self.status == STATUS.TCPOPENING or self.status == STATUS.CONNECTING then
        if socket.gettime() >= self._deadline then return self:fail("WebSocket handshake timed out") end
    end
    if self.status == STATUS.TCPOPENING then
        local url = self.url
        local ok, err = sock:connect(url.host, url.port)
        if not ok and err ~= "already connected" then
            if err ~= "timeout" and err ~= "Operation already in progress" and err ~= "Operation now in progress" then
                return self:fail(err or "TCP connection failed")
            end
            return
        end
        self.status = STATUS.CONNECTING
        self:queue("GET "..url.path.." HTTP/1.1\r\n"..
            "Host: "..url.host..":"..url.port.."\r\n"..
            "Connection: Upgrade\r\nUpgrade: websocket\r\nSec-WebSocket-Version: 13\r\n"..
            "Sec-WebSocket-Key: "..seckey.."\r\n\r\n")
    end
    if not self:flush() then return end
    if self.status == STATUS.CONNECTING then
        if #self._writes == 0 then self:read_upgrade() end
        return
    end
    for _ = 1, 64 do
        local res, head, err = self:read()
        if err == "closed" then return self:fail(err) end
        if res == nil then return end
        local opcode = band(head, 0x0f)
        local fin = band(head, 0x80) == 0x80
        if opcode == OPCODE.CLOSE then
            local code = #res >= 2 and (shl(res:byte(1), 8) + res:byte(2)) or 1005
            sock:close()
            self.status = STATUS.CLOSED
            self._writes, self._queued_bytes = {}, 0
            self:onclose(code, res:sub(3))
            return
        elseif opcode == OPCODE.PING then
            self:pong(res)
        elseif opcode == OPCODE.CONTINUE then
            self._continue = self._continue..res
            if fin then
                local message = self._continue
                self._continue = ""
                self:onmessage(message)
            end
        elseif opcode == OPCODE.TEXT or opcode == OPCODE.BINARY then
            if fin then self:onmessage(res) else self._continue = res end
        end
        if self.status == STATUS.CLOSED then return end
    end
end

---close websocket connection
---@param code integer|nil
---@param message string|nil
function _M:close(code, message)
    local payload = code and string.char(shr(code, 8), band(code, 0xff))..(message or "")
    if self:send_frame(OPCODE.CLOSE, payload) then self.status = STATUS.CLOSING end
end

return _M
