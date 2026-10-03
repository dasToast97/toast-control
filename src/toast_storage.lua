-- Toast Control: Lager / Kistenueberwachung.
-- Ein Computer neben den Kisten (oder per Netzwerkkabel + Kabelmodem mit vielen
-- Kisten verbunden) liest alle Kisten, Faesser, Shulker usw. aus:
--   - Fuellstand je Kiste und gesamt (orange = fast voll, rot = voll)
--   - Inhalt: welche Items, wie viele, in welchen Kisten (mit Suche)
-- Anzeige auf dem eigenen Monitor (oder Computerbildschirm). Die Zentrale und
-- die Pockets zeigen dasselbe im Reiter "Lager".
local common=dofile("/toast/toast_common.lua")
local cfg=common.load();assert(cfg.role=="storage","Lager erforderlich.")
local C=cfg.storage
local UI=dofile("/toast/toast_ui.lua")
pcall(common.refreshModems)
local gpsHost=common.gpsHost(cfg)
local ME=os.getComputerID()
-- ===== Kisten finden und auslesen =====
local maxCount,display={},{}
local function shortName(id)
    local s=tostring(id):gsub("^[^:]+:",""):gsub("_"," ")
    return (s:gsub("^%l",string.upper))
end
local KIND={chest="Kiste",trapped_chest="Kiste",barrel="Fass",shulker_box="Shulker",hopper="Trichter",
    dropper="Spender",dispenser="Werfer",furnace="Ofen",blast_furnace="Hochofen",smoker="Raeucher"}
local SIDES={left="links",right="rechts",top="oben",bottom="unten",front="vorne",back="hinten"}
local function isInventory(n)
    local t=tostring(peripheral.getType(n) or "")
    if t:find("turtle",1,true) or t=="computer" or t=="monitor" or t=="modem" then return false end
    if peripheral.hasType then
        local ok,r=pcall(peripheral.hasType,n,"inventory");if ok and r then return true end
    end
    local m=peripheral.wrap(n)
    return m~=nil and type(m.list)=="function" and type(m.size)=="function"
end
local function label(n)
    if type(C.names)=="table" and type(C.names[n])=="string" and C.names[n]~="" then return C.names[n] end
    local t=tostring(peripheral.getType(n) or n):gsub("^[^:]+:","")
    if t:find("shulker_box",1,true) then t="shulker_box" end
    local kind=KIND[t] or shortName(t)
    if SIDES[n] then return kind.." "..SIDES[n] end
    local num=n:match("_(%d+)$")
    return kind..(num and (" "..num) or "")
end
local data={chests={},items={},used=0,size=0,pct=0,warn=C.warnAt,count=0,types=0}
local scanning=false
local function scan()
    scanning=true
    local names={}
    for _,n in ipairs(peripheral.getNames()) do if isInventory(n) then names[#names+1]=n end end
    table.sort(names)
    local chests,items,byId={},{},{}
    local used,size,fill=0,0,0
    for _,n in ipairs(names) do
        local inv=peripheral.wrap(n)
        local okS,sz=pcall(inv.size)
        local okL,lst=pcall(inv.list)
        if okS and okL and type(sz)=="number" and type(lst)=="table" then
            local u,f,content=0,0,{}
            for slot,it in pairs(lst) do
                if type(it)=="table" and it.name then
                    u=u+1
                    local id=it.name
                    if not maxCount[id] then
                        local okD,det=pcall(inv.getItemDetail,slot)
                        maxCount[id]=(okD and type(det)=="table" and det.maxCount) or 64
                        display[id]=(okD and type(det)=="table" and det.displayName) or shortName(id)
                    end
                    f=f+it.count/math.max(1,maxCount[id])
                    content[id]=(content[id] or 0)+it.count
                end
            end
            local idx=#chests+1
            chests[idx]={n=label(n),pid=n,p=sz>0 and math.floor(f/sz*100+0.5) or 0,u=u,s=sz}
            used,size,fill=used+u,size+sz,fill+f
            for id,c in pairs(content) do
                local e=byId[id]
                if not e then e={id=id,n=display[id] or shortName(id),c=0,w={}};byId[id]=e;items[#items+1]=e end
                e.c=e.c+c;e.w[#e.w+1]={i=idx,c=c}
            end
        end
    end
    table.sort(items,function(a,b) return a.c>b.c end)
    for _,e in ipairs(items) do table.sort(e.w,function(a,b) return a.c>b.c end) end
    data={chests=chests,items=items,used=used,size=size,pct=size>0 and math.floor(fill/size*100+0.5) or 0,
        warn=C.warnAt,count=#chests,types=#items,full=0}
    for _,ch in ipairs(chests) do if ch.p>=C.warnAt then data.full=data.full+1 end end
    scanning=false
end
-- Fuer Zentrale/Pocket: kompakt (max. 64 Kisten, 150 Sorten, je 6 Fundorte)
local function compact()
    local ch={}
    for i=1,math.min(64,#data.chests) do local c=data.chests[i];ch[i]={n=c.n,p=c.p,u=c.u,s=c.s} end
    local it={}
    for i=1,math.min(150,#data.items) do
        local e=data.items[i];local w={}
        for k=1,math.min(6,#e.w) do if e.w[k].i<=64 then w[#w+1]=e.w[k] end end
        it[i]={id=e.id,n=e.n,c=e.c,w=w}
    end
    return {chests=ch,items=it,used=data.used,size=data.size,pct=data.pct,warn=data.warn,count=data.count,
        types=data.types,full=data.full,gps=gpsHost and gpsHost.served or nil}
end
-- ===== Anzeige =====
local screens={}
local function bind()
    local old={}
    for _,s in ipairs(screens) do old[s.name or "term"]=s.ui end
    screens={}
    if cfg.display.monitor~="terminal" then
        for _,n in ipairs(peripheral.getNames()) do
            if peripheral.getType(n)=="monitor" and (cfg.display.monitor=="auto" or cfg.display.monitor==n) then
                local m=peripheral.wrap(n)
                if m and m.isColor and m.isColor() then
                    common.applyScale(m,cfg.display,"info")
                    screens[#screens+1]={dev=m,name=n,ui=old[n]}
                end
            end
        end
    end
    -- Computerbildschirm zeigt immer mit (Suche per Tastatur)
    screens[#screens+1]={dev=term,name=nil,ui=old.term}
    for _,s in ipairs(screens) do
        if not s.ui then
            s.ui=UI.new(s.dev,cfg);s.ui.storeOnly=true;s.ui.filter="store";s.ui.canUpdate=false
            s.ui.storeView=s.name and "chests" or "items"
        else s.ui.setScreen(s.dev) end
    end
end
local function fleet()
    local name=(cfg.label and cfg.label~="" and cfg.label) or (cfg.name and cfg.name~="" and cfg.name) or "Lager"
    return {ids={},entries={},nodes={ids={ME},entries={[ME]={role="storage",label=name,online=true,data={stats=data}}}}}
end
local notice=""
local function draw()
    local f=fleet()
    for _,s in ipairs(screens) do
        local ok,why=pcall(s.ui.draw,f,true,notice)
        if not ok then common.log("Lager-Anzeige: "..tostring(why)) end
    end
end
local function beacon() common.nodeBeacon(cfg,"storage",compact()) end
-- ===== Ablauf =====
bind()
term.clear();term.setCursorPos(1,1);print("Lese Kisten ...")
scan();draw();beacon()
local scanTimer=os.startTimer(C.interval)
local beaconTimer=os.startTimer(10)
local function screenOf(name) for _,s in ipairs(screens) do if s.name==name then return s end end end
local function act(s,a)
    if not s or not a then return end
    s.ui.action(a);draw()
end
while true do
    local e,a,b,c,d,f=os.pullEvent()
    if gpsHost and gpsHost.event(e,a,b,c,d,f) then
        -- GPS-Anfrage beantwortet
    elseif e=="rednet_message" and common.isUpdateFor(cfg,a,b) then
        notice="Update wird installiert ...";draw()
        local ok,why=common.selfUpdate(nil,b.target)
        if not ok then notice="Update: "..tostring(why);common.log(notice);draw() end
    elseif e=="timer" and a==scanTimer then
        scan();draw();scanTimer=os.startTimer(C.interval)
    elseif e=="timer" and a==beaconTimer then
        pcall(common.refreshModems);beacon();beaconTimer=os.startTimer(10)
    elseif e=="monitor_touch" then local s=screenOf(a);if s then act(s,s.ui.click(b,c)) end
    elseif e=="mouse_click" then local s=screenOf(nil);act(s,s.ui.click(b,c))
    elseif e=="mouse_scroll" then local s=screenOf(nil);act(s,a>0 and "down" or "up")
    elseif e=="char" then local s=screenOf(nil);act(s,s.ui.char(a))
    elseif e=="key" then local s=screenOf(nil);act(s,s.ui.key(keys.getName(a)))
    elseif e=="peripheral" or e=="peripheral_detach" or e=="monitor_resize" or e=="term_resize" then
        bind();if e~="monitor_resize" and e~="term_resize" then scan() end;draw()
    end
end
