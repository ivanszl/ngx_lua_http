-- Copyright (C) 2013 Ivan Lin (ivan)

local strsub = string.sub
local tcp = ngx.socket.tcp
local insert = table.insert
local strlen = string.len
local escape_uri = ngx.escape_uri
local unescape_uri = ngx.unescape_uri
local strfind = string.find
local format = string.format
local concat = table.concat
local setmetatable = setmetatable
local error = error
local tonumber = tonumber
local type = type

module(...)

_VERSION = '0.10'

local STATE_CONNECTED = 1
local STATE_COMMAND_SENT = 2

local mt = { __index = _M }

local function parse_url(url)
  local default_ports = {http = 80, ftp = 21, https = 443}
	local _, _, scheme = strfind(url, "(.-)://")
	local _, _, host, uri = strfind(url, "://([%a%d%.:]-)/(.*)")
	if not host then
		return nil, "that is not the links"
	end
	local _, _, host, port = strfind(host, "([%a%d%.]*):?(%d*)")
	local _, len,query = strfind(uri, "%?(.*)")
	port = tonumber(port) or default_ports[scheme]
	local path = "/" .. uri
	if _ then
		path = "/" .. strsub(uri, 0, _ - 1)
	end
	return {scheme = scheme, host = host, port = port, path = path, query = query}
end

local function httprequest(self, url_parts, http_method, headers, body)
	if type(headers) ~= "table" then
		headers = {headers}
	end
	local url, sock = url_parts.path, self.sock
	if url_parts.query then
		url = url .. "?" .. url_parts.query
	end
	local host = url_parts.host
	if (url_parts.scheme == "http" and url_parts.port ~= 80) and (url_parts.scheme == "https" and url_parts.port ~= 443) then
		host = host .. ":" .. url_parts.port
	end
	insert(headers, 1, format("%s %s HTTP/1.0", http_method, url))
	insert(headers, 3, "Host: " .. host)
	insert(headers, "Accept: */*" )
	insert(headers, "Accept-Language: zh-cn")
	insert(headers, "Pragma: no-cache")
	insert(headers, "Cache-Control: no-cache")
	insert(headers, "Connection: Close")
	if body then
		insert(headers, "Content-length: " .. strlen(body))
	end
	insert(headers, "\r\n")
	local bytes, err = sock:send(concat(headers, "\r\n"))
	if not bytes then
		return nil, err
	end
	
	local line, err, partail = sock:receive()
	if not line then
		return nil, err
	end
	local status = tonumber(strsub(line, 10, 13)) or 200
	
	while true do
		line, err, partail = sock:receive()
		if line == "\r\n" or line == "" or line == "\n" then
			break
		end
		if not line then
			break
		end
		local _, _, key, val = strfind(line, "(%a+)%s*:%s*(%a+)")
		
		if not key then
			if key == "Location" or key == "URI" then
				if not strfind(val, "://") then
					local redirect = url_parts.scheme .. "://" .. url_parts.host .. ":" .. url_parts.port
					if not strfind(val, "/") then
						redirect = redirect .. "/" .. val
					else
						redirect = redirect .. val
					end
					return status, redirect
				end
			end
		end
	end
	
	local str = ""
	while true do2048
		line, err, partail = sock:receive("*a")
		if not line then
			break
		end
		str = str .. line
	end
	return status, str
end

function new(self)
	local sock, err = tcp()
	if not sock then
		return nil, err
	end
	return setmetatable({ sock = sock }, mt)
end

function set_timeout(self, timeout)
	local sock = self.sock
	if not sock then
		return nil, "not initialized"
	end
	return sock:settimeout(timeout)
end


function request(self, url, method, ...)
	local sock = self.sock
	if not sock then
		return nil, "not initialized"
	end
	local res, err = parse_url(url)
	if not res then
		return nil, err
	end
	
	if res.scheme ~= "http" and res.scheme ~= "https" then
		return nil, "Invalid protocol: " .. res.scheme
	end
	local ok, err = sock:connect(res.host, res.port)
	if not ok then
		return nil, "failed to connect: " .. err
	end
	return httprequest(self, res, method, ...)
end

function get(self, url, header)
	local sock, err, result = self.sock
    if not sock then
        return nil, "not initialized"
    end
    
    while true do
    	local status, data = request(self, url, "GET", header)
    	
    	if not status then
    		err = data
    		break
    	end
    	
    	if status == 302 then
    		url = data
    	end
    	
    	if status == 200 then
    		result = data
    		break
    	end
    end
    
    return result, err    	
end

function post(self, url, header, body)
	local sock, err, result = self.sock
    if not sock then
        return nil, "not initialized"
    end
    
    while true do
    	local status, data = request(self, url, "POST", header, body)
    	
    	if not status then
    		err = data
    		break
    	end
    	
    	if status == 302 then
    		url = data
    	end
    	
    	if status == 200 then
    		result = data
    		break
    	end
    end
    
    return result, err 
end

function close(self)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    return sock:close()
end
