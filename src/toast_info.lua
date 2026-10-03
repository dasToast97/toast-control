-- Toast Control: Infoscreen. Nur Anzeige (keine Knoepfe): holt sich die Daten
-- von der Zentrale und zeigt sie auf allen angeschlossenen Farbmonitoren.
local common=dofile("/toast/toast_common.lua")
local cfg=common.load();assert(cfg.role=="info","Infoscreen erforderlich.")
common.modem()
local UI=dofile("/toast/toast_ui.lua")
local screens={}
local function bind()
    local old={}
    for _,s in ipairs(screens) do old[s.name or "term"]=s.st end
    screens={}
    if cfg.display.monitor~="terminal" then
        for _,n in ipairs(peripheral.getNames()) do
            if peripheral.getType(n)=="monitor" and (cfg.display.monitor=="auto" or cfg.display.monitor==n) then
                local m=peripheral.wrap(n)
                if m and m.isColor and m.isColor() then
                    common.applyScale(m,cfg.display,"info")
                    screens[#screens+1]={dev=m,name=n,st=old[n] or {}}
                end
            end
        end
    end
    if #screens==0 then screens[1]={dev=term,st=old.term or {}} end
end
bind()
local fleet,seen={ids={},entries={}},nil
local function connected() return seen~=nil and os.clock()-seen<cfg.network.staleAfter end
local function poll()
    common.refreshModems()
    pcall(rednet.send,cfg.controllerId,{kind="hello",role="info",version=1,controllerId=cfg.controllerId},common.remoteProtocol)
end
local function draw()
    for _,s in ipairs(screens) do
        local ok,why=pcall(UI.drawInfo,s.dev,fleet,connected(),s.st)
        if not ok then common.log("Infoscreen: "..tostring(why)) end
    end
end
local function validFleet(f)
    if type(f)~="table" or type(f.ids)~="table" or type(f.entries)~="table" or #f.ids>cfg.network.maxDevices then return false end
    for _,id in ipairs(f.ids) do
        local e=f.entries[id]
        if not common.id(id) or type(e)~="table" or (e.data~=nil and type(e.data)~="table") then return false end
        e.label=common.label(e.label)
    end
    return true
end
local function loop()
    poll();draw()
    local timer=os.startTimer(cfg.network.pollInterval)
    while true do
        local e,a,b,c=os.pullEvent()
        if e=="rednet_message" and a==cfg.controllerId and c==common.remoteProtocol and type(b)=="table"
            and b.kind=="fleet" and b.controllerId==cfg.controllerId and validFleet(b.fleet) then
            fleet,seen=b.fleet,os.clock()
        elseif e=="timer" and a==timer then
            poll();draw();timer=os.startTimer(cfg.network.pollInterval)
        elseif e=="peripheral" or e=="peripheral_detach" or e=="monitor_resize" or e=="term_resize" then
            bind();draw()
        elseif e=="char" and (a=="q" or a=="Q") then return end
    end
end
local ok,why=pcall(loop)
for _,s in ipairs(screens) do pcall(function() s.dev.setBackgroundColor(colors.black);s.dev.clear() end) end
term.setBackgroundColor(colors.black);term.clear();term.setCursorPos(1,1)
if not ok and why~="Terminated" then error(why,0) end
print("Infoscreen beendet.")
