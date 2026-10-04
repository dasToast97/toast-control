-- Gemeinsame Config-Pruefung. Programme im Wurzelverzeichnis installieren.
local M = { protocol = "toast.farm.v2", remoteProtocol = "toast.farm.remote.v2" }
local function integer(n,lo,hi)
    return type(n)=="number" and n==n and n%1==0 and n>=lo and n<=hi
end
function M.load(c)
    if not c then
        assert(fs.exists("/farm.config.lua"), "Config fehlt: edit /toast.config.lua")
        c = dofile("/farm.config.lua")
    end
    assert(type(c)=="table", "Config muss eine Tabelle zurueckgeben.")
    assert(integer(c.controllerId,0,65500), "controllerId: ganze ID 0 bis 65500.")
    c.role = c.role or "auto"
    if c.role=="auto" then c.role=turtle and "turtle" or (pocket and "pocket" or "controller") end
    assert(c.role=="controller" or c.role=="turtle" or c.role=="pocket", "role: auto/controller/turtle/pocket")
    local used = {[c.controllerId]=true}
    for _,key in ipairs({"turtleIds","pocketIds"}) do
        assert(type(c[key])=="table", key.." muss eine Liste sein.")
        local count=0
        for k,id in pairs(c[key]) do
            assert(integer(k,1,#c[key]) and integer(id,0,65500) and not used[id], key..": ungueltige/doppelte ID.")
            used[id]=true; count=count+1
        end
        assert(count==#c[key], key..": Liste ohne Luecken verwenden.")
    end
    assert(#c.turtleIds>0, "Mindestens eine turtleIds-ID eintragen.")
    c.labels=c.labels or {}; assert(type(c.labels)=="table","labels muss eine Tabelle sein.")
    local f=c.farm; assert(type(f)=="table", "farm fehlt.")
    assert(integer(f.width,1,32) and integer(f.length,1,32), "Feldgroesse: 1 bis 32.")
    assert(({wheat=true,carrots=true,potatoes=true,beetroot=true})[f.crop], "Unbekannte crop.")
    assert(integer(f.interval,1,86400) and integer(f.seedReserve,0,256), "interval/seedReserve ungueltig.")
    assert(f.maxInterval==nil or integer(f.maxInterval,0,86400), "maxInterval: 0 (aus) bis 86400 Sekunden.")
    assert(f.radioTimeout==0 or integer(f.radioTimeout,10,300), "radioTimeout: 0 (aus) oder 10 bis 300 Sekunden.")
    assert(type(f.water)=="table", "farm.water muss eine Liste sein (auch {} erlaubt).")
    local cells={}
    for _,v in ipairs(f.water) do
        assert(type(v)=="table" and integer(v.column,1,f.width) and integer(v.row,1,f.length), "Wasserzelle ausserhalb Feld.")
        local key=v.column..":"..v.row; assert(not cells[key], "Doppelte Wasserzelle.");cells[key]=true
    end
    c.display=c.display or {}; local d=c.display
    assert(type(d.monitor)=="string" and type(d.textScale)=="number" and integer(d.textScale*2,1,10), "Monitor/textScale ungueltig.")
    assert(integer(d.pageSize,0,1000), "pageSize: 0 (auto) bis 1000.")
    local n=c.network; assert(type(n)=="table", "network fehlt.")
    assert(type(n.pollInterval)=="number" and n.pollInterval>=0.25 and n.pollInterval<=5, "pollInterval: 0.25 bis 5.")
    assert(type(n.staleAfter)=="number" and n.staleAfter>=n.pollInterval*2 and n.staleAfter<=60, "staleAfter zu klein/gross.")
    assert(type(n.commandTimeout)=="number" and n.commandTimeout>=1 and n.commandTimeout<=15, "commandTimeout: 1 bis 15.")
    assert(f.radioTimeout==0 or f.radioTimeout>=n.pollInterval*3, "radioTimeout muss mindestens 3 Pollintervalle sein.")
    if c.role=="controller" then assert(os.getComputerID()==c.controllerId,"Diese Zentrale hat eine andere ID: controllerId korrigieren.") end
    if c.role=="turtle" then assert(turtle,"role turtle benoetigt eine Turtle."); assert(os.getComputerID()~=c.controllerId,"Turtle-ID darf nicht controllerId sein.") end
    if c.role=="pocket" then assert(pocket,"role pocket benoetigt einen Pocket Computer.") end
    return c
end
function M.refreshModems()
    local modems={peripheral.find("modem",function(_,v)
        local ok,wireless=pcall(v.isWireless)
        return ok and wireless
    end)}
    local count,first=0,nil
    for _,m in ipairs(modems) do
        local ok=pcall(function() rednet.open(peripheral.getName(m)) end)
        if ok then count=count+1;first=first or m end
    end
    return count,first
end
function M.modem()
    local count,m=M.refreshModems()
    assert(count>0,"Funk-/Endermodem fehlt oder kann nicht geoeffnet werden.")
    return m
end
function M.contains(list,id) for _,v in ipairs(list) do if v==id then return true end end; return false end
function M.number(n) return type(n)=="number" and n==n and n>-math.huge and n<math.huge and n or 0 end
function M.serial(n) return integer(n,1,9007199254740991) end
return M
