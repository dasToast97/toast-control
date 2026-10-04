-- Toast Control: Infoscreen - eigene Station mit Monitor(en), irgendwo aufgebaut.
-- Nur Anzeige (keine Steuerung): zeigt die gewaehlte Kategorie (alle/farm/mining)
-- oder eine bestimmte Turtle. Daten kommen per Funk von der Zentrale.
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
local gpsHost=common.gpsHost(cfg)
local function poll()
    common.refreshModems()
    pcall(rednet.send,cfg.controllerId,{kind="hello",role="info",version=1,controllerId=cfg.controllerId,
        info=common.nodeInfo(cfg,"info",gpsHost and {gps=gpsHost.served} or nil)},common.remoteProtocol)
end
-- show = "storage": Lageransicht (Kisten / Inhalt), Monitor antippen = umschalten
local STORE=cfg.show=="storage"
local function storeUi(s)
    if not s.st.ui then
        s.st.ui=UI.new(s.dev,cfg);s.st.ui.storeOnly=true;s.st.ui.filter="store";s.st.ui.canUpdate=false
    else s.st.ui.setScreen(s.dev) end
    return s.st.ui
end
local storeStats={}
local function storeFleet()
    local nodes=fleet.nodes or {ids={},entries={}}
    for id,e in pairs(nodes.entries or {}) do
        if e.role=="storage" and storeStats[id] and e.data then e.data.stats=storeStats[id] end
    end
    local ids,entries={},{}
    for _,id in ipairs(nodes.ids or {}) do local e=nodes.entries[id];if e and e.role=="storage" then ids[#ids+1]=id;entries[id]=e end end
    return {ids={},entries={},nodes={ids=ids,entries=entries}}
end
local function draw()
    for _,s in ipairs(screens) do
        local ok,why
        if STORE then
            local ui=storeUi(s)
            ok,why=pcall(ui.draw,storeFleet(),connected(),connected() and "" or "Keine Verbindung zur Zentrale")
        else ok,why=pcall(UI.drawInfo,s.dev,fleet,connected(),s.st,cfg.show) end
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
local tick,due=0,0
local function loop()
    poll();draw()
    local timer=os.startTimer(cfg.network.pollInterval);due=os.clock()+cfg.network.pollInterval*3
    while true do
        local e,a,b,c,d,f=os.pullEvent()
        if gpsHost and gpsHost.event(e,a,b,c,d,f) then
            -- GPS-Anfrage beantwortet
        elseif e=="rednet_message" and a==cfg.controllerId and c==common.remoteProtocol and type(b)=="table"
            and b.kind=="fleet" and b.controllerId==cfg.controllerId and validFleet(b.fleet) then
            fleet,seen=b.fleet,os.clock()
        elseif e=="rednet_message" and a==cfg.controllerId and c==common.remoteProtocol and type(b)=="table"
            and b.kind=="nodestats" and b.controllerId==cfg.controllerId and type(b.stats)=="table" then
            storeStats=b.stats;if STORE then draw() end
        elseif e=="rednet_message" and a==cfg.controllerId and c==common.remoteProtocol and type(b)=="table"
            and b.kind=="update" and b.controllerId==cfg.controllerId then
            local ok,why=common.selfUpdate(nil,b.target)
            if not ok then common.log("Update: "..tostring(why)) end
        elseif (e=="timer" and a==timer) or os.clock()>=due then
            -- "due": falls der Timer verloren ging (z.B. waehrend einer GPS-Abfrage), trotzdem weiter
            due=os.clock()+cfg.network.pollInterval*3
            tick=tick+1;if tick%2==0 or not connected() then poll() end
            draw();timer=os.startTimer(cfg.network.pollInterval);due=os.clock()+cfg.network.pollInterval*3
        elseif e=="peripheral" or e=="peripheral_detach" or e=="monitor_resize" or e=="term_resize" then
            bind();draw()
        elseif STORE and e=="monitor_touch" then
            for _,s in ipairs(screens) do if s.name==a and s.st.ui then s.st.ui.action(s.st.ui.click(b,c)) end end
            draw()
        elseif STORE and e=="mouse_click" then
            for _,s in ipairs(screens) do if not s.name and s.st.ui then s.st.ui.action(s.st.ui.click(b,c)) end end
            draw()
        elseif STORE and e=="char" then
            for _,s in ipairs(screens) do if not s.name and s.st.ui then s.st.ui.action(s.st.ui.char(a)) end end
            draw()
        elseif STORE and e=="key" then
            for _,s in ipairs(screens) do if not s.name and s.st.ui then s.st.ui.action(s.st.ui.key(keys.getName(a))) end end
            draw()
        elseif e=="char" and (a=="q" or a=="Q") then return end
    end
end
local ok,why=pcall(loop)
for _,s in ipairs(screens) do pcall(function() s.dev.setBackgroundColor(colors.black);s.dev.clear();UI.resetTrack(s.dev) end) end
term.setBackgroundColor(colors.black);term.clear();term.setCursorPos(1,1)
if not ok and why~="Terminated" then error(why,0) end
print("Infoscreen beendet.")
