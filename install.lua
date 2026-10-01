-- TOAST CONTROL 2.1 – Ein-Datei-Installer (alle Programme sind hier eingebaut).
local FILES={}
FILES["toast.lua"]=[======[
-- Ein Startprogramm fuer Zentrale, Pocket, Farm, Mining und Repeater.
-- Neu: Waechter startet das Programm nach einem Absturz automatisch neu.
local common=dofile("/toast/toast_common.lua")
local args={...}

local function runOnce()
    local cfg=common.load()
    if cfg.role=="turtle" then
        local name=cfg.job=="farm" and "farm" or "mine"
        local workerCommon=dofile("/toast/"..name.."_common.lua")
        local checked=workerCommon.load(common.workerConfig(cfg))
        checked.recovery=common.recovery(cfg.recovery)
        workerCommon.load=function()return checked end
        local nativeDofile,nativeRednet=dofile,rednet
        local radio={}
        for k,v in pairs(nativeRednet) do radio[k]=v end
        radio.send=function(id,msg,protocol)
            if type(msg)=="table" and msg.kind=="status" then
                msg.label=cfg.label;msg.job=cfg.job;msg.controllerId=cfg.controllerId;msg.toast=common.version
            end
            return nativeRednet.send(id,msg,protocol)
        end
        local env=setmetatable({
            rednet=radio,
            dofile=function(path)
                if path=="/"..name.."_common.lua" then return workerCommon end
                if path=="/toast_common.lua" then return common end
                return nativeDofile(path)
            end,
        },{__index=_ENV})
        return assert(loadfile("/toast/"..name.."_turtle.lua","t",env))(table.unpack(args))
    end
    local program=({controller="toast_control.lua",pocket="toast_pocket.lua",repeater="repeater.lua"})[cfg.role]
    return assert(loadfile("/toast/"..program,"t",_ENV))(table.unpack(args))
end

-- Startargumente wie --dock/--new nur beim ersten Start verwenden.
local restarts,windowStart=0,os.clock()
while true do
    local ok,why=pcall(runOnce)
    if ok then return end
    why=tostring(why)
    if why=="Terminated" then print("Toast beendet.");return end
    common.log("Absturz: "..why)
    local okCfg,cfg=pcall(common.load)
    local r=okCfg and cfg.recovery or common.recovery(nil)
    if os.clock()-windowStart>600 then restarts,windowStart=0,os.clock() end
    restarts=restarts+1
    printError(why)
    if not r.autoRestart or restarts>r.maxRestarts then
        print("Kein automatischer Neustart mehr ("..(restarts-1).." in 10 min).")
        print("Fehler steht in /toast/fehler.log. Neustart: toast.lua")
        return
    end
    args={}
    print("Automatischer Neustart in "..r.restartDelay.."s ("..restarts.."/"..r.maxRestarts..")")
    print("Beliebige Taste: abbrechen")
    local timer=os.startTimer(r.restartDelay)
    while true do
        local e,a=os.pullEventRaw()
        if e=="timer" and a==timer then break end
        if e=="key" or e=="terminate" then print("Neustart abgebrochen.");return end
    end
end
]======]
FILES["toast_common.lua"]=[======[
local M={
    version="2.1",
    protocol="toast.control.v1", remoteProtocol="toast.control.remote.v1",
    workerProtocols={farm="toast.farm.v2",mining="toast.mine.v1"},
    legacyRemote={farm="toast.farm.remote.v2",mining="toast.mine.remote.v1"},
    actions={start=true,stop=true,once=true,reset=true},
}
-- Standardwerte fuer Stabilitaet. Fehlen sie in einer alten Config, werden sie ergaenzt.
M.recoveryDefaults={autoRestart=true,restartDelay=5,maxRestarts=5,autoRetry=3,retryDelay=30,moveRetries=8}
function M.integer(n,lo,hi)
    return type(n)=="number" and n==n and n%1==0 and n>=lo and n<=hi
end
function M.id(n) return M.integer(n,0,65500) end
function M.serial(n) return M.integer(n,1,9007199254740991) end
function M.number(n) return type(n)=="number" and n==n and n>-math.huge and n<math.huge and n or 0 end
function M.contains(list,id) for _,v in ipairs(list or {}) do if v==id then return true end end;return false end
function M.job(j) return j=="farm" or j=="mining" end
function M.label(v)
    return type(v)=="string" and v:gsub("[%c]"," "):sub(1,48) or ""
end
function M.recovery(r)
    r=type(r)=="table" and r or {}
    for k,v in pairs(M.recoveryDefaults) do if r[k]==nil then r[k]=v end end
    assert(type(r.autoRestart)=="boolean","recovery.autoRestart: true oder false.")
    assert(M.integer(r.restartDelay,1,300),"recovery.restartDelay: 1 bis 300 Sekunden.")
    assert(M.integer(r.maxRestarts,0,100),"recovery.maxRestarts: 0 bis 100.")
    assert(M.integer(r.autoRetry,0,100),"recovery.autoRetry: 0 bis 100.")
    assert(M.integer(r.retryDelay,5,3600),"recovery.retryDelay: 5 bis 3600 Sekunden.")
    assert(M.integer(r.moveRetries,1,64),"recovery.moveRetries: 1 bis 64.")
    return r
end
function M.load(c)
    c=c or dofile("/toast.config.lua")
    assert(type(c)=="table","Config muss eine Tabelle sein.")
    c.role=c.role or "auto"
    if c.role=="auto" then c.role=turtle and "turtle" or (pocket and "pocket" or "controller") end
    assert(({controller=true,turtle=true,pocket=true,repeater=true})[c.role],"role: auto/controller/turtle/pocket/repeater")
    assert(M.id(c.controllerId),"controllerId: ganze ID 0 bis 65500.")
    if c.role=="controller" then assert(os.getComputerID()==c.controllerId,"controllerId stimmt nicht mit Zentralen-ID ueberein.") end
    if c.role=="turtle" then
        assert(turtle and M.job(c.job),"Turtle: job=farm oder mining einstellen.")
        assert(os.getComputerID()~=c.controllerId,"Turtle und Zentrale duerfen nicht dieselbe ID haben.")
    end
    if c.role=="pocket" then assert(pocket and os.getComputerID()~=c.controllerId,"Pocket/Zentralen-ID ungueltig.") end
    assert(type(c.autoDiscover)=="boolean" and type(c.autoPairPockets)=="boolean","autoDiscover/autoPairPockets: true oder false.")
    assert(type(c.devices)=="table" and type(c.pocketIds)=="table","devices/pocketIds fehlen.")
    local used={[c.controllerId]=true};local count=0
    for id,d in pairs(c.devices) do
        assert(M.id(id) and not used[id] and type(d)=="table" and (M.job(d.job) or d.job=="auto"),"devices: ungueltige ID oder job.")
        assert(d.label==nil or type(d.label)=="string","devices.label: Text verwenden.")
        used[id]=true;count=count+1
    end
    local pc=0
    for i,id in pairs(c.pocketIds) do
        assert(M.integer(i,1,#c.pocketIds) and M.id(id) and not used[id],"pocketIds: ungueltige/doppelte ID.")
        used[id]=true;pc=pc+1
    end
    assert(pc==#c.pocketIds,"pocketIds: Liste ohne Luecken.")
    local d=c.display;assert(type(d)=="table" and type(d.monitor)=="string","display.monitor fehlt.")
    assert(M.integer(M.number(d.textScale)*2,1,10) and M.integer(d.pageSize,0,1000),"textScale/pageSize ungueltig.")
    local n=c.network;assert(type(n)=="table","network fehlt.")
    assert(M.number(n.pollInterval)>=0.25 and M.number(n.pollInterval)<=5,"pollInterval: 0.25 bis 5.")
    assert(M.number(n.staleAfter)>=n.pollInterval*2 and M.number(n.staleAfter)<=60,"staleAfter ungueltig.")
    assert(M.number(n.commandTimeout)>=1 and M.number(n.commandTimeout)<=15,"commandTimeout: 1 bis 15.")
    assert(M.integer(n.maxDevices,1,1024) and count<=n.maxDevices,"maxDevices: 1 bis 1024; Liste zu gross.")
    c.recovery=M.recovery(c.recovery)
    c.label=M.label(c.label)
    return c
end
function M.workerConfig(c)
    return {role="turtle",controllerId=c.controllerId,turtleIds={os.getComputerID()},pocketIds={},
        labels={},farm=c.farm,mine=c.mine,display=c.display,network=c.network,recovery=M.recovery(c.recovery)}
end
function M.refreshModems()
    local modems={peripheral.find("modem",function(_,m)
        local ok,v=pcall(m.isWireless);return ok and v
    end)}
    local count=0
    for _,m in ipairs(modems) do
        if pcall(function()rednet.open(peripheral.getName(m))end) then count=count+1 end
    end
    return count
end
function M.modem() assert(M.refreshModems()>0,"Funk-/Endermodem fehlt.") end
-- Robustes Laden: Eine halb geschriebene .tmp-Datei (Absturz/Serverstopp beim
-- Speichern) blockiert den Start nicht mehr; dann gilt die letzte gute Datei.
function M.readFileTable(path)
    if not fs.exists(path) then return nil end
    local f=fs.open(path,"r");if not f then return nil end
    local ok,s=pcall(textutils.unserialize,f.readAll());f.close()
    if ok and type(s)=="table" then return s end
end
function M.readState(path,required)
    local s=M.readFileTable(path..".tmp") or M.readFileTable(path)
    if s then return s end
    if required and (fs.exists(path) or fs.exists(path..".tmp")) then error("Zustand beschaedigt: "..path,0) end
    return {}
end
function M.saveState(path,s)
    local f=assert(fs.open(path..".tmp","w"));f.write(textutils.serialize(s));f.close()
    if fs.exists(path) then fs.delete(path) end
    fs.move(path..".tmp",path)
end
function M.log(text)
    pcall(function()
        local path="/toast/fehler.log"
        if fs.exists(path) and fs.getSize(path)>16000 then
            if fs.exists(path..".alt") then fs.delete(path..".alt") end
            fs.move(path,path..".alt")
        end
        local f=fs.open(path,"a")
        if f then
            f.writeLine("["..(os.date and os.date("%Y-%m-%d %H:%M:%S") or tostring(os.clock())).."] "..tostring(text))
            f.close()
        end
    end)
end
-- Fehler, bei denen ein automatischer neuer Versuch gefaehrlich waere.
function M.retryable(fault)
    if type(fault)~="string" or fault=="" then return false end
    for _,word in ipairs({"Lava","Wasser","Geschuetzt","Nicht abbaubar","Fuelbedarf","Position unklar"}) do
        if fault:find(word,1,true) then return false end
    end
    return true
end
return M
]======]
FILES["toast_control.lua"]=[======[
local common=dofile("/toast/toast_common.lua")
local cfg=common.load();assert(cfg.role=="controller","Zentrale erforderlich.")
common.modem()
local screen,name
-- Monitor suchen; faellt er weg (Chunk/Abbau), wird der Computerbildschirm genutzt
-- und ein neu angeschlossener Monitor automatisch wieder uebernommen.
local function bindScreen()
    local found
    if cfg.display.monitor=="auto" then
        found=peripheral.find("monitor",function(_,m)return m.isColor()end)
    elseif cfg.display.monitor~="terminal" then
        local m=peripheral.wrap(cfg.display.monitor)
        if m and m.isColor and m.isColor() then found=m end
    end
    if found then
        screen,name=found,peripheral.getName(found)
        pcall(screen.setTextScale,cfg.display.textScale)
    else
        if cfg.display.monitor~="auto" and cfg.display.monitor~="terminal" then
            print("Advanced Monitor '"..cfg.display.monitor.."' fehlt, nutze Bildschirm.")
        end
        screen,name=term,nil
    end
end
bindScreen()
local ui=dofile("/toast/toast_ui.lua").new(screen,cfg)
local model=dofile("/toast/toast_model.lua").new(cfg)
local dirty=true
-- Zeichnen gedrosselt: Viele Statusmeldungen loesen nicht mehr je ein
-- komplettes Neuzeichnen aus (verhinderte Lag bei grossen Flotten).
local function draw()
    local ok,why=pcall(ui.draw,model.fleet(),true,model.notice)
    if not ok then
        common.log("Anzeigefehler: "..tostring(why))
        bindScreen();ui.setScreen(screen)
        pcall(ui.draw,model.fleet(),true,model.notice)
    end
    dirty=false
end
local function action(a)
    local cmd=ui.action(a);if cmd then model.command(cmd,ui.target())end;draw()
end
local quit=false
local function loop()
    rednet.host(common.protocol,"toast-"..cfg.controllerId)
    model.tick();draw()
    local timer=os.startTimer(cfg.network.pollInterval)
    local frame=os.startTimer(0.25)
    while true do
        local e,a,b,c=os.pullEvent()
        if e=="rednet_message" then
            if model.ingest(a,b,c) or model.remote(a,b,c) then dirty=true end
        elseif e=="timer" and a==timer then model.tick();dirty=true;timer=os.startTimer(cfg.network.pollInterval)
        elseif e=="timer" and a==frame then
            if dirty then draw() end
            frame=os.startTimer(0.25)
        elseif e=="peripheral" or e=="peripheral_detach" then
            common.refreshModems()
            local before=screen;bindScreen()
            if screen~=before then
                if before~=term then pcall(term.clear) end
                ui.setScreen(screen);draw()
            end
        elseif e=="monitor_touch" and a==name then action(ui.click(b,c))
        elseif e=="mouse_click" and not name and a==1 then action(ui.click(b,c))
        elseif (e=="monitor_resize" and a==name) or (e=="term_resize" and not name) then draw()
        elseif e=="char" then
            if a=="q" or a=="Q" then quit=true;return end
            action(ui.keys[a])
        elseif e=="key" then if a==keys.left then action("prev")elseif a==keys.right then action("next")end end
    end
end
local ok,why=pcall(loop)
local deliberate=ok or why=="Terminated"
if deliberate then
    -- Bewusst beendet: STOP mehrfach senden, damit auch entfernte Turtles es hoeren.
    pcall(model.command,"stop","all")
    for _=1,4 do sleep(0.5);pcall(model.tick) end
end
pcall(rednet.unhost,common.protocol)
if screen~=term then pcall(screen.clear) end
term.clear();term.setCursorPos(1,1)
if deliberate then
    print("Zentrale beendet. Stopp/Heimfahrt fuer alle Turtles angefordert.")
else
    -- Absturz: Turtles NICHT stoppen; der Waechter startet die Zentrale neu.
    error(why,0)
end
]======]
FILES["toast_model.lua"]=[======[
local common=dofile("/toast/toast_common.lua")
local M={}
function M.new(cfg)
    local m={entries={},pending={},notice="Warte auf Geraete...",config=cfg}
    local PATH="/toast_control_state"
    local s=common.readState(PATH)
    local serial=common.serial(s.serial) and s.serial or 0
    local devices,pockets,remote={}, {}, {}
    if type(s.remote)=="table" then
        for k,v in pairs(s.remote) do if type(k)=="string" and common.serial(v) then remote[k]=v end end
    end
    if cfg.autoDiscover and type(s.devices)=="table" then
        for id,d in pairs(s.devices) do
            if common.id(id) and id~=cfg.controllerId and type(d)=="table" and (common.job(d.job) or d.job=="auto")
                and not common.contains(cfg.pocketIds,id) then devices[id]={job=d.job,label=common.label(d.label)} end
        end
    end
    for id,d in pairs(cfg.devices) do devices[id]={job=d.job,label=common.label(d.label)} end
    for _,id in ipairs(cfg.pocketIds) do pockets[id]=true end
    if cfg.autoPairPockets and type(s.pockets)=="table" then
        for id,v in pairs(s.pockets) do if v==true and common.id(id) and id~=cfg.controllerId and not devices[id] then pockets[id]=true end end
    end
    local function count()local n=0;for _ in pairs(devices)do n=n+1 end;return n end
    -- Zu grosse gespeicherte Liste nicht mehr als Startfehler behandeln: kuerzen.
    if count()>cfg.network.maxDevices then
        local ids={};for id in pairs(devices)do if not cfg.devices[id] then ids[#ids+1]=id end end
        table.sort(ids,function(a,b)return a>b end)
        for _,id in ipairs(ids)do if count()<=cfg.network.maxDevices then break end;devices[id]=nil end
    end
    local function save()pcall(common.saveState,PATH,{serial=serial,devices=devices,pockets=pockets,remote=remote})end
    local function send(id,b,p)pcall(rednet.send,id,b,p)end
    local function dispatch(id,msg,job)
        if job=="auto" then for _,p in pairs(common.workerProtocols) do send(id,msg,p) end
        elseif common.workerProtocols[job] then send(id,msg,common.workerProtocols[job]) end
    end
    function m.online(id)
        local e=m.entries[id];return e~=nil and os.clock()-e.seen<cfg.network.staleAfter
    end
    function m.fleet(scope)
        local ids,entries={},{}
        for id,d in pairs(devices) do if scope==nil or scope=="all" or d.job==scope then ids[#ids+1]=id end end
        table.sort(ids)
        for _,id in ipairs(ids)do
            local e=m.entries[id];local d=devices[id]
            entries[id]={job=d.job,label=d.label,online=m.online(id),data=e and e.data or nil,pending=m.pending[id]~=nil}
        end
        return {ids=ids,entries=entries}
    end
    function m.ingest(id,b,p)
        local job
        for j,protocol in pairs(common.workerProtocols)do if protocol==p then job=j end end
        if not job or not common.id(id) or id==cfg.controllerId or pockets[id] or type(b)~="table"
            or b.kind~="status" or b.version~=2 or b.id~=id
            or (b.controllerId~=nil and b.controllerId~=cfg.controllerId) then return false end
        local d=devices[id]
        if not d then
            if not cfg.autoDiscover or count()>=cfg.network.maxDevices then return false end
            d={job=job,label=""};devices[id]=d
        end
        local changed=d.job~=job or not m.entries[id]
        if d.job~=job then m.pending[id]=nil end
        d.job=job
        local label=cfg.devices[id] and common.label(cfg.devices[id].label) or ""
        if label=="" then label=common.label(b.label);if label=="" then label=d.label end end
        if d.label~=label then d.label=label;changed=true end
        local old=m.entries[id] and m.entries[id].data
        if b.fault and (not old or old.fault~=b.fault) then common.log("Turtle #"..id.." Fehler: "..tostring(b.fault)) end
        m.entries[id]={data=b,seen=os.clock()}
        local pending=m.pending[id]
        if pending and common.number(b.ack)>=pending.message.serial then m.pending[id]=nil end
        if changed then save() end
        return true
    end
    local function matches(id,d,target)
        return target=="all" or target==id or target==d.job
    end
    function m.command(action,target)
        if not common.actions[action] then return false end
        if target~="all" and target~="farm" and target~="mining" and not (common.id(target) and devices[target]) then return false end
        local changed={}
        local always=action=="stop" or action=="reset"
        for id,d in pairs(devices) do
            local e=m.entries[id]
            if matches(id,d,target) and (always or (m.online(id) and not e.data.recovery)) then
                serial=math.max(serial+1,os.epoch("utc"),e and common.number(e.data.ack)+1 or 0)
                m.pending[id]={message={kind="command",action=action,serial=serial},at=os.clock(),job=d.job}
                changed[#changed+1]=id
            end
        end
        if #changed==0 then m.notice="Kein erreichbares Ziel / Position unklar";return false end
        save()
        for _,id in ipairs(changed)do local p=m.pending[id];dispatch(id,p.message,p.job) end
        m.notice=string.upper(action)..": "..#changed.." Turtle(s), warte auf ACK"
        return true
    end
    local function key(id,protocol)return protocol..":"..id end
    function m.reply(id,protocol)
        protocol=protocol or common.remoteProtocol
        local scope="all";for j,p in pairs(common.legacyRemote)do if p==protocol then scope=j end end
        local f=m.fleet(scope);local labels={}
        for _,tid in ipairs(f.ids)do labels[tid]=f.entries[tid].label end
        send(id,{kind="fleet",version=protocol==common.remoteProtocol and 1 or 2,
            controllerId=cfg.controllerId,fleet=f,labels=labels,ack=remote[key(id,protocol)] or 0,notice=m.notice},protocol)
    end
    function m.remote(id,b,protocol)
        local scope="all";local valid=protocol==common.remoteProtocol
        for j,p in pairs(common.legacyRemote)do if p==protocol then scope=j;valid=true end end
        if not valid or not common.id(id) or id==cfg.controllerId or devices[id] or type(b)~="table" then return false end
        if not pockets[id] then
            if not (cfg.autoPairPockets and protocol==common.remoteProtocol and b.kind=="hello"
                and b.version==1 and b.role=="pocket" and b.controllerId==cfg.controllerId) then return false end
            local n=0;for _ in pairs(pockets)do n=n+1 end
            if n>=64 then return false end
            pockets[id]=true;save()
        end
        if b.kind=="command" and common.serial(b.serial) and b.serial>(remote[key(id,protocol)] or 0) then
            local target=b.target
            if scope~="all" then
                if target=="all" then target=scope
                elseif not devices[target] or devices[target].job~=scope then m.reply(id,protocol);return true end
            end
            if m.command(b.action,target) then remote[key(id,protocol)]=b.serial;save() end
        end
        m.reply(id,protocol);return true
    end
    function m.tick()
        common.refreshModems()
        for id,d in pairs(devices)do dispatch(id,{kind="poll"},d.job)end
        if cfg.autoDiscover then for _,p in pairs(common.workerProtocols)do pcall(rednet.broadcast,{kind="poll"},p)end end
        local waiting,expired=0,0
        for id,p in pairs(m.pending)do
            if os.clock()-p.at>=cfg.network.commandTimeout then m.pending[id]=nil;expired=expired+1
            else waiting=waiting+1;dispatch(id,p.message,p.job) end
        end
        if expired>0 then m.notice="Befehl nicht bestaetigt: "..expired
        elseif waiting==0 and m.notice:find("warte auf ACK",1,true) then m.notice="Befehl von Turtle(s) bestaetigt" end
        for id in pairs(pockets)do m.reply(id)end
    end
    function m.waiting()local n=0;for _ in pairs(m.pending)do n=n+1 end;return n end
    return m
end
return M
]======]
FILES["toast_ui.lua"]=[======[
local common=dofile("/toast/toast_common.lua")
local M={}
function M.new(screen,cfg)
    local ui={filter="all",selected=nil,page=1,buttons={},ids={}}
    local function num(n)return common.number(n)end
    local function short(n)
        n=num(n);if math.abs(n)>=1000000 then return string.format("%.1fM",n/1000000)end
        if math.abs(n)>=10000 then return string.format("%.1fk",n/1000)end
        return tostring(math.floor(n))
    end
    function ui.setScreen(s)screen=s end
    function ui.draw(fleet,link,notice)
        local w,h=screen.getSize();ui.buttons={}
        screen.setBackgroundColor(colors.black);screen.setTextColor(colors.white);screen.clear()
        local function text(x,y,s,fg,bg)
            if x<1 or x>w or y<1 or y>h then return end
            screen.setCursorPos(x,y);screen.setTextColor(fg or colors.white);screen.setBackgroundColor(bg or colors.black)
            screen.write(tostring(s):sub(1,w-x+1))
        end
        local function button(x,y,width,label,action,bg,enabled)
            local color=enabled and bg or colors.gray
            text(x,y,string.rep(" ",width),colors.white,color)
            text(x,y,tostring(label):sub(1,width),colors.white,color)
            ui.buttons[#ui.buttons+1]={x=x,y=y,w=width,action=action,enabled=enabled}
        end
        if w<26 or h<18 then
            text(1,1,"TOAST CONTROL",colors.cyan);text(1,3,"Minimum: 26 x 18 Zeichen",colors.yellow)
            text(1,5,"Monitor vergroessern /");text(1,6,"textScale=0.5 einstellen.");return
        end
        local entries=fleet.entries or {};local ids={}
        local farms,mines,online,faults,totalFarm,totalMine,fuel,seeds,slots=0,0,0,0,0,0,0,0,0
        local unlimited=false
        for _,id in ipairs(fleet.ids or {})do
            local e=entries[id] or {};local d=e.data or {}
            if e.job=="farm" then farms=farms+1 elseif e.job=="mining" then mines=mines+1 end
            if ui.filter=="all" or e.job==ui.filter then
                ids[#ids+1]=id
                if link and e.online then online=online+1 end
                if d.fault or d.recovery then faults=faults+1 end
                if e.job=="farm" then totalFarm=totalFarm+num(d.total) elseif e.job=="mining" then totalMine=totalMine+num(d.total) end
                seeds=seeds+num(d.seeds);slots=slots+num(d.freeSlots)
                if d.fuel=="unlimited" then unlimited=true else fuel=fuel+num(d.fuel) end
            end
        end
        ui.ids=ids
        if ui.selected and not common.contains(ids,ui.selected)then ui.selected=nil end
        local selected=ui.selected and entries[ui.selected];local data=selected and selected.data or {}
        local title=ui.filter=="farm" and "FARM" or ui.filter=="mining" and "MINING" or "ALLE"
        text(1,1,"TOAST CONTROL / "..(link and "ONLINE" or "OFFLINE"),colors.cyan)
        text(1,2,"Farm "..farms.." | Mine "..mines.." | "..online.."/"..#ids..(faults>0 and (" | Fehler "..faults) or ""),
            faults>0 and colors.orange or colors.lightGray)
        local third=math.floor(w/3)
        for i,v in ipairs({{"ALLE","all"},{"FARM","farm"},{"MINING","mining"}})do
            button(1+(i-1)*third,3,i==3 and w-2*third or third,v[1],"filter:"..v[2],
                ui.filter==v[2] and colors.blue or colors.gray,true)
        end
        local label=selected and (selected.label~="" and selected.label or "Turtle") or title.." TURTLES"
        if ui.selected then label=label.." #"..ui.selected end
        text(1,4,label,colors.cyan)
        local statusColor=(data.fault or data.recovery) and colors.orange or colors.yellow
        text(1,5,selected and (link and selected.online and tostring(data.status or "Verbunden") or "OFFLINE / alte Werte") or "Gemeinsame Uebersicht",
            selected and statusColor or colors.yellow)
        text(1,6,selected and tostring(data.detail or "Noch keine Daten") or "START / STOP / RESET fuer "..title,colors.lightGray)
        if selected then
            text(1,7,(selected.job=="farm" and "Ernte " or "Beute ")..short(data.total)..
                (selected.job=="farm" and " | Saat "..short(data.seeds) or " | Slots "..short(data.freeSlots)))
            text(1,8,"Fuel "..(data.fuel=="unlimited" and "unbegrenzt" or short(data.fuel)).." | "..(selected.job=="farm" and "Runden " or "Gaenge ")..short(data.rounds))
            local pc=math.floor(math.max(0,math.min(1,num(data.scanned)/math.max(1,num(data.cells))))*100)
            text(1,9,"Fortschritt "..pc.."% | "..(selected.job=="farm" and "Pflanzen " or "Bloecke ")..short(data.harvested),colors.lightGray)
        else
            text(1,7,"Ernte "..short(totalFarm).." | Beute "..short(totalMine))
            text(1,8,"Fuel "..(unlimited and "teils unbegrenzt" or short(fuel)))
            text(1,9,"Saat "..short(seeds).." | Freie Slots "..short(slots),colors.lightGray)
        end
        local available=math.max(1,h-16)
        local pageSize=cfg.display.pageSize>0 and math.min(available,cfg.display.pageSize) or available
        local pages=math.max(1,math.ceil(#ids/pageSize));ui.pages=pages;ui.page=math.min(ui.page,pages)
        for row=1,pageSize do
            local id=ids[(ui.page-1)*pageSize+row];if not id then break end
            local e=entries[id] or {};local d=e.data or {}
            local prefix=e.job=="farm" and "F" or e.job=="mining" and "M" or "?"
            local name=e.label and e.label~="" and e.label or ""
            local status=link and e.online and tostring(d.status or "ONLINE") or "OFFLINE"
            local bg=ui.selected==id and colors.blue or ((d.fault or d.recovery) and link and e.online and colors.brown or colors.gray)
            button(1,10+row,w,(d.fault or d.recovery) and "!"..prefix.."#"..id.." "..name.." "..status or prefix.."#"..id.." "..name.." "..status,"id:"..id,bg,true)
        end
        text(1,h-5,tostring(notice or ""),colors.lightGray)
        local half=math.floor(w/2)
        button(1,h-4,half,"< Seite "..ui.page.."/"..pages,"pageprev",colors.gray,true)
        button(half+1,h-4,w-half,"Seite >","pagenext",colors.gray,true)
        for i,v in ipairs({{"< Ziel","prev"},{"Ziel >","next"},{"GRUPPE","group"}})do
            button(1+(i-1)*third,h-3,i==3 and w-2*third or third,v[1],v[2],colors.blue,true)
        end
        button(1,h-2,w,"RESET: Fehler loeschen + heim","reset",colors.orange,link and #ids>0)
        local canStart=false
        for _,id in ipairs(ids)do
            local e=entries[id]
            if link and (not ui.selected or ui.selected==id) and e and e.online and e.data and not e.data.recovery then canStart=true end
        end
        local once=selected and (selected.job=="farm" and "1 RUNDE" or "1 GANG") or ui.filter=="farm" and "1 RUNDE" or ui.filter=="mining" and "1 GANG" or "1 LAUF"
        for i,v in ipairs({{"START","start",colors.green},{"STOP","stop",colors.red},{once,"once",colors.blue}})do
            button(1+(i-1)*third,h-1,i==3 and w-2*third or third,v[1],v[2],v[3],v[2]=="stop" and link or canStart)
        end
        text(1,h,ui.selected and ("Ziel #"..ui.selected.." | 0: Gruppe") or ("Ziel "..title.." | Q: Ende"),colors.lightGray)
    end
    function ui.action(a)
        if not a then return end
        if a:match("^filter:")then ui.filter=a:sub(8);ui.selected=nil;ui.page=1
        elseif a:match("^id:")then ui.selected=tonumber(a:sub(4))
        elseif a=="group" then ui.selected=nil
        elseif a=="pageprev" then ui.page=math.max(1,ui.page-1)
        elseif a=="pagenext" then ui.page=math.min(ui.pages or 1,ui.page+1)
        elseif a=="next" or a=="prev" then
            local index=0;for i,id in ipairs(ui.ids)do if id==ui.selected then index=i end end
            index=(index+(a=="next" and 1 or -1))%(#ui.ids+1)
            ui.selected=ui.ids[index]
        else return a end
    end
    function ui.target()return ui.selected or ui.filter end
    function ui.click(x,y)
        for _,b in ipairs(ui.buttons)do if b.enabled and y==b.y and x>=b.x and x<b.x+b.w then return b.action end end
    end
    ui.keys={["0"]="group",["1"]="start",["2"]="stop",["3"]="once",["4"]="reset",["a"]="filter:all",["f"]="filter:farm",["m"]="filter:mining"}
    return ui
end
return M
]======]
FILES["toast_pocket.lua"]=[======[
local common=dofile("/toast/toast_common.lua")
local cfg=common.load();assert(cfg.role=="pocket","Pocket erforderlich.")
common.modem()
local ui=dofile("/toast/toast_ui.lua").new(term,cfg)
local PATH="/toast_pocket_state"
local state=common.readState(PATH)
local serial=common.serial(state.serial) and state.serial or 0
local fleet,seen,pending
local notice="Warte auf Zentrale #"..cfg.controllerId
local function connected()return seen~=nil and os.clock()-seen<cfg.network.staleAfter end
local function send(b)pcall(rednet.send,cfg.controllerId,b,common.remoteProtocol)end
local function poll()
    common.refreshModems()
    send({kind="hello",role="pocket",version=1,controllerId=cfg.controllerId})
end
local function draw()ui.draw(fleet or {ids={},entries={}},connected(),notice)end
local function validFleet(f)
    if type(f)~="table" or type(f.ids)~="table" or type(f.entries)~="table" or #f.ids>cfg.network.maxDevices then return false end
    local used={}
    for _,id in ipairs(f.ids)do
        local e=f.entries[id]
        if not common.id(id) or used[id] or type(e)~="table" or not (common.job(e.job) or e.job=="auto")
            or type(e.online)~="boolean" or (e.data~=nil and type(e.data)~="table") then return false end
        e.label=common.label(e.label);used[id]=true
    end
    return true
end
local function action(a)
    local cmd=ui.action(a)
    if cmd and connected() and common.actions[cmd] then
        local target=ui.target();local eligible=cmd=="stop" or cmd=="reset"
        for _,id in ipairs(fleet.ids)do
            local e=fleet.entries[id]
            if (target=="all" or target==id or target==e.job) and e.online and e.data and not e.data.recovery then eligible=true end
        end
        if eligible then
            serial=math.max(serial+1,os.epoch("utc"))
            pcall(common.saveState,PATH,{serial=serial})
            pending={message={kind="command",action=cmd,target=target,serial=serial},at=os.clock()}
            send(pending.message);notice="Warte auf Zentrale..."
        end
    end
    draw()
end
local function loop()
    poll();draw();local timer=os.startTimer(cfg.network.pollInterval)
    while true do
        local e,a,b,c=os.pullEvent()
        if e=="rednet_message" and a==cfg.controllerId and c==common.remoteProtocol and type(b)=="table"
            and b.kind=="fleet" and b.version==1 and b.controllerId==cfg.controllerId and validFleet(b.fleet) then
            fleet,seen=b.fleet,os.clock();serial=math.max(serial,common.number(b.ack))
            if pending and common.number(b.ack)>=pending.message.serial then pending=nil end
            notice=pending and "Warte auf Zentrale..." or tostring(b.notice or "Verbunden");draw()
        elseif e=="timer" and a==timer then
            poll()
            if pending then
                if not connected() or os.clock()-pending.at>=cfg.network.commandTimeout then pending=nil;notice="Befehl unbestaetigt/verfallen"
                else send(pending.message)end
            end
            draw();timer=os.startTimer(cfg.network.pollInterval)
        elseif e=="peripheral" or e=="peripheral_detach" then poll()
        elseif e=="mouse_click" and a==1 then action(ui.click(b,c))
        elseif e=="term_resize" then draw()
        elseif e=="char" then
            if a=="q" or a=="Q" then return end
            action(ui.keys[a])
        elseif e=="key" then if a==keys.left then action("prev")elseif a==keys.right then action("next")end end
    end
end
local ok,why=pcall(loop)
term.setBackgroundColor(colors.black);term.setTextColor(colors.white);term.clear();term.setCursorPos(1,1)
if not ok and why~="Terminated" then error(why,0) end
print("Pocket geschlossen. Farmen und Minen laufen weiter.")
]======]
FILES["farm_turtle.lua"]=[======[
-- Toast Farm 2.1 | CC:Tweaked | Mining Turtle + Wireless Modem
-- Feld: Spalten von links nach rechts, Reihen von der Basis nach hinten.
-- Neu: Positions-Wiederherstellung nach Absturz, RESET, Auto-Retry, Mob-Blockaden.
local common = dofile("/farm_common.lua")
local config = common.load()
assert(config.role == "turtle", "Dieses Programm gehoert auf die Turtle.")
local CFG = config.farm
local R = config.recovery or { autoRetry = 3, retryDelay = 30, moveRetries = 8 }
local CROPS = {
    wheat = { block = "minecraft:wheat", seed = "minecraft:wheat_seeds",
        produce = "minecraft:wheat", age = 7, label = "Weizen" },
    carrots = { block = "minecraft:carrots", seed = "minecraft:carrot",
        produce = "minecraft:carrot", age = 7, label = "Karotten" },
    potatoes = { block = "minecraft:potatoes", seed = "minecraft:potato",
        produce = "minecraft:potato", age = 7, label = "Kartoffeln" },
    beetroot = { block = "minecraft:beetroots", seed = "minecraft:beetroot_seeds",
        produce = "minecraft:beetroot", age = 3, label = "Rote Bete" },
}
local PROTOCOL, STATE_FILE = common.protocol, "/toast_farm_state"
local FUEL = { ["minecraft:coal"] = true, ["minecraft:charcoal"] = true, ["minecraft:coal_block"] = true }
local CONTAINERS = { ["minecraft:chest"] = true,
    ["minecraft:trapped_chest"] = true, ["minecraft:barrel"] = true }
local args = { ... }
assert(turtle, "Dieses Programm gehoert auf eine Mining Turtle.")
assert(CROPS[CFG.crop], "Unbekannte Pflanzenart in CFG.crop.")
for _, n in ipairs({ CFG.width, CFG.length }) do
    assert(type(n) == "number" and n >= 1 and n <= 32 and n % 1 == 0,
        "Feldmasse muessen ganze Zahlen zwischen 1 und 32 sein.")
end
assert(CFG.interval >= 1 and CFG.seedReserve >= 1 and CFG.seedReserve <= 256,
    "Ungueltige Wartezeit oder Saatgutreserve.")
local crop = CROPS[CFG.crop]
local budget = CFG.width * CFG.length + CFG.width + CFG.length + 20

local function readTable(path)
    if not fs.exists(path) then return nil end
    local f = fs.open(path, "r")
    if not f then return nil end
    local ok, s = pcall(textutils.unserialize, f.readAll())
    f.close()
    if ok and type(s) == "table" and type(s.x) == "number" and type(s.z) == "number"
        and type(s.dir) == "number" then return s end
end
local function loadState()
    -- Halb geschriebene .tmp-Datei ignorieren und die letzte gute Datei nehmen.
    local s = readTable(STATE_FILE .. ".tmp") or readTable(STATE_FILE)
    if s then return s end
    if fs.exists(STATE_FILE) or fs.exists(STATE_FILE .. ".tmp") then
        error("Farmzustand beschaedigt. Turtle an Basis setzen: toast.lua --dock", 0)
    end
    return { x = 0, z = 0, dir = 0, total = 0, harvested = 0, rounds = 0 }
end
local st = loadState()
local function save()
    local f = assert(fs.open(STATE_FILE .. ".tmp", "w"), "Farmzustand nicht schreibbar.")
    f.write(textutils.serialize(st))
    f.close()
    if fs.exists(STATE_FILE) then fs.delete(STATE_FILE) end
    fs.move(STATE_FILE .. ".tmp", STATE_FILE)
end
local function clearPending() st.pending, st.after, st.pendingFuel = nil, nil, nil end
-- Unterbrochene Bewegung ueber den Fuelstand aufloesen.
local function resolvePending()
    if not st.pending then return true end
    local fuel = turtle.getFuelLevel()
    if st.pending ~= "turn" and type(fuel) == "number" and type(st.pendingFuel) == "number"
        and type(st.after) == "table" then
        if fuel == st.pendingFuel then clearPending(); save(); return true end
        if fuel == st.pendingFuel - 1 then
            st.x, st.z, st.dir = st.after.x, st.after.z, st.after.dir
            clearPending(); save(); return true
        end
    end
    return false
end
local resolvedAtStart = st.pending ~= nil and resolvePending()
for _, arg in ipairs(args) do
    if arg == "--dock" then
        print("Turtle muss an der Basis stehen und zum Feld schauen.")
        write("Zum Bestaetigen DOCK eingeben: ")
        assert(read() == "DOCK", "Positionsreset abgebrochen.")
        st.x, st.z, st.dir = 0, 0, 0
        clearPending()
        st.lastMode = nil
    else
        error("Start: toast.lua [--dock]. IDs in toast.config.lua einstellen.", 0)
    end
end
st.controller = config.controllerId
local layout = CFG.width .. ":" .. CFG.length .. ":" .. CFG.crop
for _,cell in ipairs(CFG.water) do layout = layout .. ":" .. cell.column .. "," .. cell.row end
assert(not st.layout or st.layout == layout or (st.x == 0 and st.z == 0 and not st.pending),
    "Feldparameter nur an der Basis aendern. Bei versetzter Turtle --dock verwenden.")
st.layout = layout
assert(st.controller and st.controller >= 0 and st.controller % 1 == 0
    and st.controller ~= os.getComputerID(), "Ungueltige Computer-ID.")
save()
common.modem()
local run = { mode = "off", status = "Bereit", detail = "START am Touchscreen druecken.",
    scanned = 0, roundYield = 0, roundPlants = 0, waitUntil = 0,
    lastContact = os.clock(), fault = nil, recovery = st.pending ~= nil,
    lastMode = nil, retries = 0, retryAt = nil }
if run.recovery then
    run.status = "Position unklar"
    run.detail = "An Basis setzen; toast.lua --dock starten."
elseif resolvedAtStart then
    run.detail = "Position nach Neustart wiederhergestellt."
end
-- Nach Absturz/Serverneustart den laufenden Auftrag selbst fortsetzen.
if not run.recovery and (st.lastMode == "auto" or st.lastMode == "once") then
    run.mode, run.lastMode = st.lastMode, st.lastMode
    run.status, run.detail = "Fortsetzen", "Auftrag nach Neustart fortgesetzt."
end
local function status(title, detail)
    run.status, run.detail = title, detail or ""
end
local function retryable(fault)
    if type(fault) ~= "string" then return false end
    for _, w in ipairs({ "Lava", "Wasser", "Geschuetzt", "Position unklar" }) do
        if fault:find(w, 1, true) then return false end
    end
    return true
end
local function fail(why) run.mode, run.fault, run.retryAt = "off", why, nil end
local function finish()
    run.mode, run.lastMode = "off", nil
    if st.lastMode then st.lastMode = nil; save() end
end
local function count(name)
    local n = 0
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item and item.name == name then n = n + item.count end
    end
    return n
end
local function freeSlots()
    local n = 0
    for i = 1, 16 do if turtle.getItemCount(i) == 0 then n = n + 1 end end
    return n
end
local function findSlot(name)
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item and item.name == name then return i end
    end
end
local function receiveSlot(name)
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item and item.name == name and turtle.getItemSpace(i) > 0 then return i end
    end
    for i = 1, 16 do if turtle.getItemCount(i) == 0 then return i end end
end
local function isHome() return st.x == 0 and st.z == 0 end
local function active()
    if run.mode ~= "off" and os.clock() - run.lastContact > CFG.radioTimeout then
        fail("Funkverbindung verloren")
    end
    return run.mode ~= "off" and not run.recovery
end
-- Vor Bewegungen werden Marker, Zielposition und Fuelstand gespeichert.
-- Nach einem Neustart klaert der Fuelstand, ob der Schritt ausgefuehrt wurde.
local function action(kind, fn, update)
    local x, z, dir = st.x, st.z, st.dir
    update()
    st.after = { x = st.x, z = st.z, dir = st.dir }
    st.x, st.z, st.dir = x, z, dir
    st.pending, st.pendingFuel = kind, turtle.getFuelLevel()
    save()
    local ok, why = fn()
    if ok then update() end
    clearPending()
    save()
    return ok, why
end
local function face(dir)
    while st.dir ~= dir do
        local left = (st.dir - dir) % 4 == 1
        local ok, why = action("turn", left and turtle.turnLeft or turtle.turnRight,
            function() st.dir = (st.dir + (left and 3 or 1)) % 4 end)
        if not ok then return false, why or "Drehen fehlgeschlagen" end
    end
    return true
end
local DX, DZ = { [0] = 0, 1, 0, -1 }, { [0] = 1, 0, -1, 0 }
local function forward()
    local last
    -- Tiere/Spieler im Weg: angreifen, kurz warten, erneut versuchen.
    for attempt = 1, R.moveRetries do
        local ok, why = action("move", turtle.forward, function()
            st.x, st.z = st.x + DX[st.dir], st.z + DZ[st.dir]
        end)
        if ok then return true end
        last = why
        if tostring(why):lower():find("fuel", 1, true) then break end
        if attempt < R.moveRetries then pcall(turtle.attack); sleep(0.5) end
    end
    return false, "Weg blockiert: " .. tostring(last)
end
local function goTo(x, z, interruptible)
    while st.x ~= x or st.z ~= z do
        if interruptible and not active() then return false, "stopped" end
        local dir
        if st.z ~= z then dir = st.z < z and 0 or 2
        else dir = st.x < x and 1 or 3 end
        local ok, why = face(dir)
        if not ok then return false, why end
        if interruptible and not active() then return false, "stopped" end
        ok, why = forward()
        if not ok then return false, why end
    end
    return true
end
local function home()
    status("Rueckkehr", run.fault or "Fahre zur Basis.")
    local ok, why = goTo(0, 0, false)
    if ok then ok, why = face(0) end
    return ok, why
end
local function container(inspect)
    local ok, block = inspect()
    return ok and CONTAINERS[block.name] == true
end
local function unload()
    if not container(turtle.inspectDown) then
        return false, "Lager fehlt", "Kiste oder Fass direkt UNTER die Basis setzen."
    end
    local keep = CFG.seedReserve
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item and not FUEL[item.name] then
            local amount = item.count
            if item.name == crop.seed then
                local retained = math.min(keep, amount)
                keep, amount = keep - retained, amount - retained
            end
            if amount > 0 then
                turtle.select(i)
                local before = turtle.getItemCount(i)
                turtle.dropDown(amount)
                if before - turtle.getItemCount(i) < amount then
                    return false, "Lager voll", "Ausgabekiste leeren oder erweitern."
                end
            end
        end
    end
    return true
end
local function refuel()
    local function sufficient()
        local fuel = turtle.getFuelLevel()
        return fuel == "unlimited" or fuel >= budget
    end
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item and FUEL[item.name] then
            turtle.select(i)
            while turtle.getItemCount(i) > 0 and not sufficient() do
                if not turtle.refuel(1) then break end
            end
        end
    end
    if sufficient() then return true end
    if not container(turtle.inspectUp) then
        return false, "Treibstoff fehlt", "Kohlekiste direkt UEBER die Basis setzen."
    end
    local slot = receiveSlot("minecraft:coal") or receiveSlot("minecraft:charcoal")
    if not slot then return false, "Inventar voll", "Turtle-Inventar pruefen." end
    turtle.select(slot)
    if not turtle.suckUp(math.max(1, math.ceil((budget - turtle.getFuelLevel()) / 80))) then
        return false, "Treibstoff fehlt", "Kiste oben mit Kohle / Holzkohle fuellen."
    end
    local item = turtle.getItemDetail(slot)
    if not item or not FUEL[item.name] then
        turtle.dropUp()
        return false, "Falscher Brennstoff", "In die obere Kiste nur Kohle / Holzkohle legen."
    end
    while turtle.getItemCount(slot) > 0 and not sufficient() do
        if not turtle.refuel(1) then break end
    end
    if sufficient() then return true end
    return false, "Treibstoff fehlt", "Mehr Kohle / Holzkohle in die obere Kiste legen."
end
local function refillSeeds()
    if count(crop.seed) >= CFG.seedReserve then return true end
    local ok, why = face(2)
    if not ok then return false, "Drehen fehlgeschlagen", why end
    local exists = container(turtle.inspect)
    local badItem = false
    if exists then
        while count(crop.seed) < CFG.seedReserve do
            local slot = receiveSlot(crop.seed)
            if not slot then break end
            turtle.select(slot)
            if not turtle.suck(CFG.seedReserve - count(crop.seed)) then break end
            local item = turtle.getItemDetail(slot)
            if not item or item.name ~= crop.seed then turtle.drop(); badItem = true; break end
        end
    end
    ok, why = face(0)
    if not ok then return false, "Drehen fehlgeschlagen", why end
    if badItem then
        return false, "Saatgutkiste pruefen", "Hinten nur passendes Saatgut einfuellen."
    end
    if count(crop.seed) > 0 then return true end
    return false, "Saatgut fehlt", "Kiste HINTER der Basis mit Saatgut fuellen."
end
local function prepare()
    if not isHome() then
        local ok, why = home()
        if not ok then fail(why); return false, why end
    end
    while active() do
        local ok, title, detail = unload()
        if ok then ok, title, detail = refuel() end
        if ok then ok, title, detail = refillSeeds() end
        if ok then return true end
        status(title, detail)
        for _ = 1, 10 do if not active() then return false, "stopped" end; sleep(0.2) end
    end
    return false, "stopped"
end
local function waterCell(x, z)
    for _, cell in ipairs(CFG.water) do
        if cell.column == x + 1 and cell.row == z then return true end
    end
    return false
end
local function visit(x, z)
    if waterCell(x, z) then return true end
    local exists, block = turtle.inspectDown()
    if exists and block.name ~= crop.block then return true end
    if exists and tonumber((block.state or {}).age) ~= crop.age then return true end
    if count(crop.seed) == 0 then return false, "resupply" end
    if exists and freeSlots() < 2 then return false, "resupply" end
    local before = count(crop.produce)
    if exists then
        status("Ernte", "Reife Pflanzen werden geerntet und neu gepflanzt.")
        if not turtle.digDown() then return false, "Pflanze nicht abbaubar" end
        st.harvested, run.roundPlants = (st.harvested or 0) + 1, run.roundPlants + 1
    else
        status("Pflanzen", "Leere Ackerstellen werden bepflanzt.")
    end
    local slot = findSlot(crop.seed)
    if not slot then return false, "Saatgut fehlt" end
    turtle.select(slot)
    local planted = turtle.placeDown()
    local net = math.max(0, count(crop.produce) - before)
    st.total, run.roundYield = (st.total or 0) + net, run.roundYield + net
    save()
    -- Kein Acker (z.B. Weg/Erde) blockiert nicht mehr die ganze Runde.
    if not planted then run.skipped = (run.skipped or 0) + 1 end
    return true
end
local function scan()
    run.scanned, run.roundYield, run.roundPlants, run.waitUntil, run.skipped = 0, 0, 0, 0, 0
    if not prepare() then return false end
    for index = 1, CFG.width * CFG.length do
        if not active() then return false end
        local row = math.floor((index - 1) / CFG.width) + 1
        local x = (index - 1) % CFG.width
        if row % 2 == 0 then x = CFG.width - 1 - x end
        local done = false
        while not done and active() do
            local fuel = turtle.getFuelLevel()
            local need = math.abs(st.x - x) + math.abs(st.z - row) + x + row + 8
            if fuel ~= "unlimited" and fuel < need then
                if not prepare() then return false end
            end
            status("Feld pruefen", "Reihe " .. row .. " / " .. CFG.length)
            local ok, why = goTo(x, row, true)
            if not ok then
                if why ~= "stopped" then fail(why) end
                return false
            end
            if not active() then return false end
            ok, why = visit(x, row)
            if ok then done = true
            elseif why == "resupply" then
                if not prepare() then return false end
            else
                fail(why)
                return false
            end
        end
        if not done then return false end
        run.scanned = index
    end
    st.rounds = (st.rounds or 0) + 1
    run.retries = 0
    save()
    local ok, why = home()
    if not ok then fail("Rueckweg blockiert: " .. tostring(why)); return false end
    while active() do
        local ok2, title, detail = unload()
        if ok2 then return true end
        status(title, detail)
        for _ = 1, 10 do if not active() then return false end; sleep(0.2) end
    end
    return false
end
local function idle()
    if not isHome() or st.dir ~= 0 then
        local ok, why = home()
        if not ok then status("Rueckweg blockiert", why); return end
    end
    local ok, title, detail = unload()
    if not ok then status(title, detail); return end
    if run.fault then
        local now = os.clock()
        if run.lastMode and retryable(run.fault) and run.retries < R.autoRetry then
            run.retryAt = run.retryAt or now + R.retryDelay
            local contact = now - run.lastContact < CFG.radioTimeout
            if now >= run.retryAt and contact then
                run.retries, run.retryAt, run.fault, run.mode = run.retries + 1, nil, nil, run.lastMode
                status("Neuer Versuch", "Automatisch " .. run.retries .. "/" .. R.autoRetry)
            else
                status(run.fault, contact and ("Neuer Versuch in " .. math.max(0, math.ceil(run.retryAt - now))
                    .. "s (" .. (run.retries + 1) .. "/" .. R.autoRetry .. ") | RESET: abbrechen")
                    or "Warte auf Funkkontakt fuer neuen Versuch")
            end
        else
            status(run.fault, "Problem beheben; RESET loescht Fehler, START startet neu.")
        end
    else
        status("Bereit", "START: Dauerbetrieb | 1 RUNDE: einmal ernten.")
    end
end
local function worker()
    while true do
        if run.recovery then
            sleep(0.2)
        elseif active() then
            local complete = scan()
            if complete and run.mode == "once" then finish() end
            if complete and active() then
                run.waitUntil = os.clock() + CFG.interval
                while active() and run.waitUntil > os.clock() do
                    status("Warten", "Naechster Feldscan startet automatisch."
                        .. ((run.skipped or 0) > 0 and (" " .. run.skipped .. " Felder ohne Acker.") or ""))
                    sleep(0.2)
                end
                run.waitUntil = 0
            end
        else
            idle()
            sleep(0.5)
        end
    end
end
local function snapshot()
    return { kind = "status", version = 2, id = os.getComputerID(), crop = crop.label,
        width = CFG.width, length = CFG.length, status = run.status, detail = run.detail,
        mode = run.mode, recovery = run.recovery, ack = st.commandSerial or 0,
        fault = run.fault, retries = run.retries,
        contactAge = math.max(0, math.floor(os.clock() - run.lastContact)),
        fuel = turtle.getFuelLevel(), budget = budget, seeds = count(crop.seed),
        freeSlots = freeSlots(), x = st.x, z = st.z, total = st.total or 0,
        harvested = st.harvested or 0, rounds = st.rounds or 0,
        roundYield = run.roundYield, roundPlants = run.roundPlants,
        scanned = run.scanned, cells = CFG.width * CFG.length,
        wait = math.max(0, math.ceil(run.waitUntil - os.clock())) }
end
local function sendStatus() pcall(rednet.send, st.controller, snapshot(), PROTOCOL) end
local function reset()
    run.mode, run.fault, run.lastMode, run.retries, run.retryAt, run.waitUntil = "off", nil, nil, 0, nil, 0
    st.lastMode = nil
    if run.recovery and resolvePending() then run.recovery = false end
    if run.recovery then status("Position unklar", "RESET reicht nicht: an Basis setzen, toast.lua --dock")
    else status("Reset", "Fehler geloescht; Turtle faehrt zur Basis.") end
end
local function listener()
    while true do
        local event, sender, message, protocol = os.pullEvent()
        if (event == "key" and sender == keys.q) or (event == "char" and (sender == "q" or sender == "Q")) then
            finish(); run.fault = nil
        elseif event == "peripheral" or event == "peripheral_detach" then common.refreshModems(); sendStatus()
        elseif event == "rednet_message" and sender == st.controller and protocol == PROTOCOL
            and type(message) == "table" then
            if message.kind == "poll" then
                run.lastContact = os.clock()
                sendStatus()
            elseif message.kind == "command" and common.serial(message.serial)
                and ({ start = true, stop = true, once = true, reset = true })[message.action] then
                run.lastContact = os.clock()
                if message.serial > (st.commandSerial or 0) then
                    st.commandSerial = message.serial
                    if message.action == "stop" then
                        finish(); run.fault, run.retries, run.retryAt = nil, 0, nil
                    elseif message.action == "reset" then reset()
                    elseif not run.recovery then
                        run.mode = message.action == "once" and "once" or "auto"
                        run.lastMode = run.mode
                        st.lastMode = run.mode
                        run.fault, run.waitUntil, run.retries, run.retryAt = nil, 0, 0, nil
                    end
                    save()
                end
                sendStatus()
            end
        end
    end
end
local function heartbeat()
    while true do common.refreshModems(); sendStatus(); sleep(2) end
end
term.clear(); term.setCursorPos(1, 1)
print("TOAST FARM 2.1 - Turtle #" .. os.getComputerID())
print("Zentrale #" .. st.controller .. " | " .. crop.label)
print("Q: Stopp + Heimfahrt. Ctrl+T: Programmabbruch.")
if run.recovery then printError(run.detail) elseif resolvedAtStart then print(run.detail) end
local ok, why = pcall(function() parallel.waitForAll(worker, listener, heartbeat) end)
if not ok then
    run.mode = "off"
    run.recovery = st.pending ~= nil and not resolvePending()
    status(run.recovery and "Position unklar" or "Programm beendet", tostring(why))
    sendStatus()
    if why ~= "Terminated" then error(why, 0) end
    printError("Abgebrochen.")
    if run.recovery then print("Vor Neustart: Basisposition mit --dock neu bestaetigen.") end
end
]======]
FILES["farm_common.lua"]=[======[
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
    assert(integer(f.interval,1,86400) and integer(f.seedReserve,1,256), "interval/seedReserve ungueltig.")
    assert(integer(f.radioTimeout,10,300), "radioTimeout: 10 bis 300 Sekunden.")
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
    assert(f.radioTimeout>=n.pollInterval*3, "radioTimeout muss mindestens 3 Pollintervalle sein.")
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
]======]
FILES["mine_turtle.lua"]=[======[
-- Toast Mining 2.1: Strip-Mining mit parallelen Gaengen, mit eigener Basis.
-- Neu: Positions-Wiederherstellung nach Absturz, RESET, Auto-Retry, Mob-Blockaden.
local common=dofile("/mine_common.lua")
local cfg=common.load();assert(cfg.role=="turtle","Mining Turtle erforderlich.")
common.modem()
local R=cfg.recovery or {autoRetry=3,retryDelay=30,moveRetries=8}
local C,FILE,args=cfg.mine,"/toast_mining_state",{...}
local area,cells=C.length,C.length*C.tunnels
local width=(C.tunnels-1)*(C.gap+1)+1
local layout="strip:"..C.length..":"..C.height..":"..C.tunnels..":"..C.gap
local st={x=0,y=0,z=0,dir=0,next=1,total=0,harvested=0,commandSerial=0,layout=layout}
local function readTable(path)
    if not fs.exists(path) then return nil end
    local f=fs.open(path,"r");if not f then return nil end
    local ok,s=pcall(textutils.unserialize,f.readAll());f.close()
    if ok and type(s)=="table" and type(s.x)=="number" and type(s.y)=="number" and type(s.z)=="number"
        and type(s.dir)=="number" and type(s.next)=="number" then return s end
end
-- Halb geschriebene .tmp-Datei ignorieren und die letzte gute Datei nehmen.
local saved=readTable(FILE..".tmp") or readTable(FILE)
if saved then st=saved
elseif fs.exists(FILE) or fs.exists(FILE..".tmp") then
    error("Mining-Zustand beschaedigt. Turtle an Basis setzen: toast.lua --dock --new",0)
end
local function homePosition() return st.x==0 and st.y==0 and st.z==0 end
local function save()
    local f=assert(fs.open(FILE..".tmp","w"));f.write(textutils.serialize(st));f.close()
    if fs.exists(FILE) then fs.delete(FILE) end;fs.move(FILE..".tmp",FILE)
end
local function clearPending() st.pending,st.after,st.pendingFuel=nil,nil,nil end
-- Unterbrochene Bewegung ueber den Fuelstand aufloesen:
-- Fuel unveraendert = Schritt nicht ausgefuehrt, Fuel -1 = Schritt ausgefuehrt.
local function resolvePending()
    if not st.pending then return true end
    local fuel=turtle.getFuelLevel()
    if st.pending~="turn" and type(fuel)=="number" and type(st.pendingFuel)=="number" and type(st.after)=="table" then
        if fuel==st.pendingFuel then clearPending();save();return true end
        if fuel==st.pendingFuel-1 then
            local a=st.after;st.x,st.y,st.z,st.dir=a.x,a.y,a.z,a.dir;clearPending();save();return true
        end
    end
    return false
end
local resolvedAtStart=st.pending~=nil and resolvePending()
for _,arg in ipairs(args) do
    if arg=="--dock" then
        print("An die ORIGINALBASIS setzen und in die Mine schauen.")
        write("DOCK bestaetigen: ");assert(read()=="DOCK","Abgebrochen.")
        st.x,st.y,st.z,st.dir=0,0,0,0;clearPending();st.lastMode=nil
    elseif arg=="--new" then
        assert(homePosition() and not st.pending,"Neuer Auftrag nur an der Basis; ggf. zuerst --dock.")
        write("Neue Gaenge an dieser Basis? NEU eingeben: ");assert(read()=="NEU","Abgebrochen.")
        st.next,st.layout,st.accessHigh,st.lastMode=1,layout,nil,nil
    else error("Start: toast.lua [--dock] [--new]",0) end
end
assert(st.layout==layout,"Abbaumasse geaendert: an Basis mit --new neuen Auftrag bestaetigen.")
assert(st.x>=0 and st.x<width and st.y>=-(C.height-1) and st.y<=0 and st.z>=0 and st.z<=C.length
    and st.dir>=0 and st.dir<=3 and st.dir%1==0 and st.next>=1 and st.next<=cells+1 and st.next%1==0,
    "Mining-Koordinaten ungueltig. An Basis setzen: toast.lua --dock")
save()
local run={mode="off",status=st.next>cells and "Fertig" or "Bereit",detail="START: Auftrag | 1 GANG: aktuellen Gang",
    recovery=st.pending~=nil,lastContact=os.clock(),fault=nil,onceEnd=nil,lastMode=nil,retries=0,retryAt=nil}
if run.recovery then run.status,run.detail="Position unklar","An Originalbasis setzen; toast.lua --dock"
elseif resolvedAtStart then run.detail="Position nach Neustart wiederhergestellt." end
-- Nach Absturz/Serverneustart den laufenden Auftrag selbst fortsetzen.
if not run.recovery and (st.lastMode=="auto" or st.lastMode=="once") and st.next<=cells then
    run.mode,run.lastMode,run.onceEnd=st.lastMode,st.lastMode,st.onceEnd or cells
    run.status,run.detail="Fortsetzen","Auftrag nach Neustart fortgesetzt."
end
local protected={}
for _,name in ipairs(C.protectedBlocks) do protected[name]=true end
local hard={['minecraft:bedrock']=true,['minecraft:chest']=true,['minecraft:trapped_chest']=true,
    ['minecraft:barrel']=true,['minecraft:ender_chest']=true,['minecraft:hopper']=true,
    ['computercraft:turtle_normal']=true,['computercraft:turtle_advanced']=true}
local function status(a,b) run.status,run.detail=a,b or "" end
local function retryable(fault)
    if type(fault)~="string" then return false end
    for _,w in ipairs({"Lava","Wasser","Geschuetzt","Nicht abbaubar","Fuelbedarf","Position unklar"}) do
        if fault:find(w,1,true) then return false end
    end
    return true
end
local function fail(why)
    run.mode,run.fault,run.retryAt="off",why,nil
end
local function active()
    if run.mode~="off" and os.clock()-run.lastContact>C.radioTimeout then fail("Funkverbindung verloren") end
    return run.mode~="off" and not run.recovery
end
local function action(kind,fn,update)
    local x,y,z,dir=st.x,st.y,st.z,st.dir
    update();st.after={x=st.x,y=st.y,z=st.z,dir=st.dir}
    st.x,st.y,st.z,st.dir=x,y,z,dir
    st.pending,st.pendingFuel=kind,turtle.getFuelLevel();save()
    local ok,why=fn();if ok then update() end
    clearPending();save();return ok,why
end
local function face(dir)
    while st.dir~=dir do
        local left=(st.dir-dir)%4==1
        local ok,why=action("turn",left and turtle.turnLeft or turtle.turnRight,
            function()st.dir=(st.dir+(left and 3 or 1))%4 end)
        if not ok then return false,"Drehen fehlgeschlagen: "..tostring(why) end
    end
    return true
end
local function freeSlots()
    local n=0;for i=1,16 do if turtle.getItemCount(i)==0 then n=n+1 end end;return n
end
local function blockReason(b)
    if b.name=="minecraft:lava" or b.name=="minecraft:flowing_lava" then return "Lava erkannt" end
    if b.name=="minecraft:water" or b.name=="minecraft:flowing_water"
        or (b.state and b.state.waterlogged) then return "Wasser erkannt" end
    if protected[b.name] or hard[b.name] or b.name:find("shulker_box",1,true) then return "Geschuetzter Block: "..b.name end
end
local function clear(inspect,dig,interruptible)
    for _=1,C.digRetries do
        if interruptible and not active() then return false,"stopped" end
        local exists,b=inspect()
        if not exists then return true end
        local reason=blockReason(b);if reason then return false,reason end
        if freeSlots()==0 then return false,"Inventar voll / Rueckweg pruefen" end
        local ok,why=dig();if not ok then return false,"Nicht abbaubar: "..b.name.." / "..tostring(why) end
        st.harvested=(st.harvested or 0)+1;save();sleep(0.1)
    end
    local exists,b=inspect();if not exists then return true end
    return false,blockReason(b) or "Zu viel nachrutschender Kies/Sand"
end
local DX,DZ={[0]=0,1,0,-1},{[0]=1,0,-1,0}
local function homeDistance()return st.x+math.max(0,st.z-1)+math.abs(st.y)+(st.z>0 and 1 or 0)end
local function move(kind,interruptible)
    if interruptible and not active() then return false,"stopped" end
    local fuel=turtle.getFuelLevel()
    if interruptible and (freeSlots()<C.freeSlots or (fuel~="unlimited" and fuel<homeDistance()+12)) then return false,"resupply" end
    local inspect,dig,fn,update,attack
    if kind=="up" then inspect,dig,fn,attack=turtle.inspectUp,turtle.digUp,turtle.up,turtle.attackUp;update=function()st.y=st.y-1 end
    elseif kind=="down" then inspect,dig,fn,attack=turtle.inspectDown,turtle.digDown,turtle.down,turtle.attackDown;update=function()st.y=st.y+1 end
    else inspect,dig,fn,attack=turtle.inspect,turtle.dig,turtle.forward,turtle.attack;update=function()st.x,st.z=st.x+DX[st.dir],st.z+DZ[st.dir] end end
    local last
    -- Mobs/Spieler im Weg: angreifen, kurz warten, erneut versuchen.
    for attempt=1,R.moveRetries do
        local ok,why=clear(inspect,dig,interruptible);if not ok then return false,why end
        if interruptible and not active() then return false,"stopped" end
        ok,why=action(kind,fn,update)
        if ok then return true end
        last=why
        if tostring(why):lower():find("fuel",1,true) then break end
        if attempt<R.moveRetries then pcall(attack);sleep(0.5) end
    end
    return false,"Bewegung blockiert: "..tostring(last)
end
local clearHeight
local function horizontal(x,z,interruptible,xFirst)
    while st.x~=x or st.z~=z do
        local dir
        if st.x~=x and (xFirst or st.z==z) then dir=st.x<x and 1 or 3
        else dir=st.z<z and 0 or 2 end
        local ok,why=face(dir);if not ok then return false,why end
        ok,why=move("forward",interruptible);if not ok then return false,why end
        if interruptible and st.z==1 and st.x>(st.accessHigh or -1) then
            ok,why=clearHeight();if not ok then return false,why end
            st.accessHigh=st.x;save()
        end
    end
    return true
end
local function vertical(y,interruptible)
    while st.y~=y do local ok,why=move(st.y<y and "down" or "up",interruptible);if not ok then return false,why end end
    return true
end
local function home()
    status("Rueckkehr",run.fault or "Fahre ueber freigelegte Wege zur Basis.")
    local ok,why=true
    if st.z>0 then
        ok,why=vertical(0,false)
        if ok then ok,why=horizontal(0,1,false,false) end
        if ok then ok,why=vertical(0,false) end
        if ok then ok,why=horizontal(0,0,false,false) end
    end
    if ok then ok,why=face(0) end
    return ok,why
end
local containers={['minecraft:chest']=true,['minecraft:trapped_chest']=true,['minecraft:barrel']=true}
local function container(fn)local ok,b=fn();return ok and containers[b.name] end
local function unload()
    if not container(turtle.inspectDown) then return false,"Ausgabekiste fehlt" end
    for i=1,16 do
        if turtle.getItemCount(i)>0 then
            if not container(turtle.inspectDown) then return false,"Ausgabekiste fehlt" end
            turtle.select(i);local before=turtle.getItemCount(i);turtle.dropDown()
            local delivered=before-turtle.getItemCount(i)
            st.total=(st.total or 0)+delivered;save()
            if turtle.getItemCount(i)>0 then return false,"Lager voll" end
        end
    end
    return true
end
local minimum=2*(width+C.length)+4*C.height+40
local fuelTarget=math.max(C.fuelTarget,minimum)
local limit=turtle.getFuelLimit()
assert(limit=="unlimited" or fuelTarget<=limit,"Fuelbedarf groesser als Tank; Config/Feld verkleinern.")
local FUELS={['minecraft:coal']=80,['minecraft:charcoal']=80,['minecraft:coal_block']=800}
local function refuel()
    if turtle.getFuelLevel()=="unlimited" then return true end
    local value=80
    while turtle.getFuelLevel()<fuelTarget do
        if not active() then return false,"stopped" end
        if not container(turtle.inspectUp) then return false,"Brennstoffkiste fehlt" end
        local slot
        for i=1,16 do if turtle.getItemCount(i)==0 then slot=i;break end end
        if not slot then return false,"Inventar voll" end
        turtle.select(slot)
        local want=math.max(1,math.min(64,math.ceil((fuelTarget-turtle.getFuelLevel())/value)))
        if not turtle.suckUp(want) then return false,"Treibstoff fehlt" end
        local item=turtle.getItemDetail(slot)
        if not item or not FUELS[item.name] then
            turtle.dropUp()
            return false,"Brennstoffkiste: nur Kohle/Holzkohle/Kohleblock"
        end
        value=FUELS[item.name]
        while turtle.getItemCount(slot)>0 and turtle.getFuelLevel()<fuelTarget do
            if not turtle.refuel(1) then return false,"Betanken fehlgeschlagen" end
        end
        -- Ueberschuss zurueck in die Brennstoffkiste, nicht ins Beutelager.
        if turtle.getItemCount(slot)>0 then turtle.dropUp() end
    end
    return true
end
local function supplies()
    local ok,why=home();if not ok then return false,why end
    while active() do
        ok,why=unload();if ok then ok,why=refuel() end
        if ok then return true end
        if why=="stopped" then return false,why end
        status(why,"Problem an Basis beheben. STOP bricht Warten ab.")
        sleep(1)
    end
    return false,"stopped"
end
local function target(index)
    local tunnel=math.floor((index-1)/C.length)
    return tunnel*(C.gap+1),0,(index-1)%C.length+1
end
local function resumePath()
    local x,_,z=target(st.next)
    local ok,why=horizontal(0,1,true,false);if not ok then return false,why end
    ok,why=horizontal(x,1,true,true);if not ok then return false,why end
    return horizontal(x,z,true,false)
end
clearHeight=function()
    for y=1,C.height-1 do
        local ok,why=move("up",true);if not ok then return false,why end
    end
    return vertical(0,true)
end
local function finish()
    run.mode,run.lastMode="off",nil
    if st.lastMode then st.lastMode=nil;save() end
end
local function idle()
    local ok,why=home()
    if not ok then status("Rueckweg blockiert",why);return end
    ok,why=unload()
    if not ok then status(why,"Ausgabe an Basis pruefen.")
    elseif run.fault then
        local now=os.clock()
        if run.lastMode and retryable(run.fault) and run.retries<R.autoRetry then
            run.retryAt=run.retryAt or now+R.retryDelay
            local contact=now-run.lastContact<C.radioTimeout
            if now>=run.retryAt and contact then
                run.retries=run.retries+1;run.retryAt=nil;run.fault=nil;run.mode=run.lastMode
                status("Neuer Versuch","Automatisch "..run.retries.."/"..R.autoRetry)
            else
                status(run.fault,contact and ("Neuer Versuch in "..math.max(0,math.ceil(run.retryAt-now)).."s ("..(run.retries+1).."/"..R.autoRetry..") | RESET: abbrechen")
                    or "Warte auf Funkkontakt fuer neuen Versuch")
            end
        else
            status(run.fault,"Problem beheben; RESET loescht Fehler, START setzt fort.")
        end
    elseif st.next>cells then status("Fertig","Neuer Auftrag: toast.lua --new")
    else status("Bereit","START setzt fort | 1 GANG: aktuellen Gang") end
end
local function work()
    while true do
        if not run.recovery then
            if active() then
                if st.next>cells then finish();status("Fertig","Neuer Auftrag: toast.lua --new")
                else
                    local ok,why=true
                    local fuel=turtle.getFuelLevel()
                    if homePosition() or freeSlots()<C.freeSlots or (fuel~="unlimited" and fuel<homeDistance()+12) then
                        ok,why=supplies()
                    end
                    if ok and active() then
                        status("Abbau","Gang "..(math.floor((st.next-1)/area)+1).." / "..C.tunnels)
                        if homePosition() then ok,why=resumePath()
                        else
                            local x,y,z=target(st.next)
                            if st.y~=0 then
                                ok,why=vertical(0,true)
                                if ok then ok,why=horizontal(x,z,true,false) end
                            elseif (st.next-1)%area==0 then
                                ok,why=supplies();if ok then ok,why=resumePath() end
                            else ok,why=horizontal(x,z,true,false) end
                        end
                    end
                    if ok and active() and not (st.z==1 and st.x<=(st.accessHigh or -1)) then ok,why=clearHeight() end
                    if ok and active() then
                        st.next=st.next+1;save();run.retries=0
                        if run.mode=="once" and st.next>run.onceEnd then finish() end
                        if st.next>cells then finish() end
                    elseif not ok and why=="resupply" then
                        local ready,problem=supplies()
                        if not ready and problem~="stopped" then fail(problem) end
                    elseif not ok and why~="stopped" then fail(why) end
                end
            end
            if not active() then idle() end
        end
        sleep(0.2)
    end
end
local function snapshot()
    return {kind="status",version=2,id=os.getComputerID(),status=run.status,detail=run.detail,
        mode=run.mode,recovery=run.recovery,ack=st.commandSerial or 0,fault=run.fault,retries=run.retries,
        contactAge=math.max(0,math.floor(os.clock()-run.lastContact)),radioTimeout=C.radioTimeout,pollToken=run.pollToken,
        width=width,length=C.length,height=C.height,tunnels=C.tunnels,gap=C.gap,fuel=turtle.getFuelLevel(),freeSlots=freeSlots(),
        x=st.x,y=st.y,z=st.z,total=st.total or 0,harvested=st.harvested or 0,
        rounds=math.floor((st.next-1)/area),scanned=st.next-1,cells=cells}
end
local function sendStatus()pcall(rednet.send,cfg.controllerId,snapshot(),common.protocol)end
local function reset()
    run.mode,run.fault,run.lastMode,run.retries,run.retryAt="off",nil,nil,0,nil
    st.lastMode=nil
    if run.recovery and resolvePending() then run.recovery=false end
    if run.recovery then status("Position unklar","RESET reicht nicht: an Basis setzen, toast.lua --dock")
    else status("Reset","Fehler geloescht; Turtle faehrt zur Basis.") end
end
local function listener()
    while true do
        local e,a,b,c=os.pullEvent()
        if e=="char" and (a=="q" or a=="Q") then finish();run.fault=nil
        elseif e=="peripheral" or e=="peripheral_detach" then common.refreshModems();sendStatus()
        elseif e=="rednet_message" and a==cfg.controllerId and c==common.protocol and type(b)=="table" then
            if b.kind=="poll" then run.lastContact=os.clock();run.pollToken=b.token;sendStatus()
            elseif b.kind=="command" and common.serial(b.serial) and ({start=true,stop=true,once=true,reset=true})[b.action] then
                run.lastContact=os.clock()
                if b.serial>(st.commandSerial or 0) then
                    st.commandSerial=b.serial
                    if b.action=="stop" then finish();run.fault,run.retries,run.retryAt=nil,0,nil
                    elseif b.action=="reset" then reset()
                    elseif not run.recovery and st.next<=cells then
                        run.mode=b.action=="once" and "once" or "auto";run.fault,run.retries,run.retryAt=nil,0,nil
                        run.lastMode=run.mode
                        run.onceEnd=(math.floor((st.next-1)/area)+1)*area
                        st.lastMode,st.onceEnd=run.mode,run.onceEnd
                    end
                    save()
                end
                sendStatus()
            end
        end
    end
end
local function heartbeat()while true do common.refreshModems();sendStatus();sleep(2)end end
term.clear();term.setCursorPos(1,1)
print("TOAST MINING 2.1 / Turtle #"..os.getComputerID())
print(C.tunnels.." Gaenge / "..C.length.." lang / "..C.height.." hoch / Abstand "..C.gap)
print("Zentrale #"..cfg.controllerId)
print("Q: Stopp/Heimfahrt. Ctrl+T: Abbruch.")
if run.recovery then printError(run.detail) elseif resolvedAtStart then print(run.detail) end
local ok,why=pcall(function()parallel.waitForAll(work,listener,heartbeat)end)
if not ok then
    run.mode="off";run.recovery=st.pending~=nil and not resolvePending()
    status(run.recovery and "Position unklar" or "Programm beendet",tostring(why));sendStatus()
    if why~="Terminated" then error(why,0) end
    printError("Abgebrochen.")
end
]======]
FILES["mine_common.lua"]=[======[
-- Gemeinsame Config-Pruefung. Programme im Wurzelverzeichnis installieren.
local M = { protocol = "toast.mine.v1", remoteProtocol = "toast.mine.remote.v1" }
local function integer(n,lo,hi)
    return type(n)=="number" and n==n and n%1==0 and n>=lo and n<=hi
end
function M.load(c)
    if not c then
        assert(fs.exists("/mine.config.lua"), "Config fehlt: edit /toast.config.lua")
        c = dofile("/mine.config.lua")
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
    local f=c.mine; assert(type(f)=="table", "mine fehlt.")
    assert(integer(f.length,1,1024) and integer(f.height,1,5) and integer(f.tunnels,1,64) and integer(f.gap,0,16), "Strip: length 1-1024, height 1-5, tunnels 1-64, gap 0-16.")
    assert(integer(f.fuelTarget,100,20000), "fuelTarget: 100 bis 20000.")
    assert(integer(f.radioTimeout,10,300), "radioTimeout: 10 bis 300 Sekunden.")
    assert(integer(f.freeSlots,2,8), "freeSlots: 2 bis 8.")
    assert(integer(f.digRetries,1,64), "digRetries: 1 bis 64.")
    assert(type(f.protectedBlocks)=="table", "protectedBlocks muss eine Liste sein.")
    for _,name in ipairs(f.protectedBlocks) do assert(type(name)=="string", "protectedBlocks: Blocknamen verwenden.") end
    c.display=c.display or {}; local d=c.display
    assert(type(d.monitor)=="string" and type(d.textScale)=="number" and integer(d.textScale*2,1,10), "Monitor/textScale ungueltig.")
    assert(integer(d.pageSize,0,1000), "pageSize: 0 (auto) bis 1000.")
    local n=c.network; assert(type(n)=="table", "network fehlt.")
    assert(type(n.pollInterval)=="number" and n.pollInterval>=0.25 and n.pollInterval<=5, "pollInterval: 0.25 bis 5.")
    assert(type(n.staleAfter)=="number" and n.staleAfter>=n.pollInterval*2 and n.staleAfter<=60, "staleAfter zu klein/gross.")
    assert(type(n.commandTimeout)=="number" and n.commandTimeout>=1 and n.commandTimeout<=15, "commandTimeout: 1 bis 15.")
    assert(f.radioTimeout>=n.pollInterval*3, "radioTimeout muss mindestens 3 Pollintervalle sein.")
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
]======]
FILES["repeater.lua"]=[======[
-- Toast Wireless Repeater | CC:Tweaked Rednet | Farm + Strip Mining
-- Start: repeater.lua. Q oder Ctrl+T beendet und schliesst eigene Kanaele.
local CHANNEL_REPEAT, CHANNEL_BROADCAST, MAX_ID = 65533, 65535, 65500
local CACHE_SECONDS, CACHE_LIMIT = 30, 4096
local modems, seen, cacheCount = {}, {}, 0
local repeated, duplicates, dropped = 0, 0, 0
local function integer(n,lo,hi)
    return type(n)=="number" and n==n and n%1==0 and n>=lo and n<=hi
end
local function scan()
    local current={}
    for _,name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name)=="modem" then
            local m=peripheral.wrap(name)
            if m and m.isWireless() then
                local owned=modems[name] and modems[name].owned or not m.isOpen(CHANNEL_REPEAT)
                m.open(CHANNEL_REPEAT);current[name]={device=m,owned=owned}
            end
        end
    end
    modems=current
end
local function draw()
    local w,h=term.getSize()
    term.setBackgroundColor(colors.black);term.setTextColor(colors.white);term.clear()
    local function line(y,text)
        if y<=h then term.setCursorPos(1,y);term.write(tostring(text):sub(1,w)) end
    end
    local count=0;for _ in pairs(modems) do count=count+1 end
    line(1,"TOAST / WIRELESS REPEATER")
    line(3,"Computer-ID: "..os.getComputerID())
    line(4,"Funkmodems: "..count..(count==0 and " - BITTE ANBRINGEN" or " / AKTIV"))
    line(6,"Weitergeleitet: "..repeated)
    line(7,"Doppelte ignoriert: "..duplicates)
    line(8,"Cache voll: "..dropped)
    line(10,"Rednet: Farm, Mining, Pocket")
    line(11,"IDs bleiben unveraendert.")
    line(13,"Q / Ctrl+T: beenden")
end
local function cleanup()
    for _,m in pairs(modems) do if m.owned then pcall(m.device.close,CHANNEL_REPEAT) end end
end
local function loop()
    scan();draw();local timer=os.startTimer(1)
    while true do
        local e,name,channel,reply,message=os.pullEventRaw()
        if e=="terminate" or (e=="char" and (name=="q" or name=="Q")) then return
        elseif e=="peripheral" or e=="peripheral_detach" then scan();draw()
        elseif e=="term_resize" then draw()
        elseif e=="timer" and name==timer then
            local now=os.clock()
            for id,expires in pairs(seen) do if expires<=now then seen[id]=nil;cacheCount=cacheCount-1 end end
            draw();timer=os.startTimer(1)
        elseif e=="modem_message" and modems[name] and channel==CHANNEL_REPEAT
            and integer(reply,0,65535) and type(message)=="table"
            and integer(message.nMessageID,0,9007199254740991)
            and integer(message.nRecipient,0,9007199254740991) then
            local id=message.nMessageID
            if seen[id] and seen[id]>os.clock() then duplicates=duplicates+1
            elseif cacheCount>=CACHE_LIMIT then dropped=dropped+1
            else
                if not seen[id] then cacheCount=cacheCount+1 end
                seen[id]=os.clock()+CACHE_SECONDS
                local recipient=message.nRecipient==CHANNEL_BROADCAST and CHANNEL_BROADCAST or message.nRecipient%MAX_ID
                for _,m in pairs(modems) do
                    pcall(m.device.transmit,recipient,reply,message)
                    pcall(m.device.transmit,CHANNEL_REPEAT,reply,message)
                end
                repeated=repeated+1
            end
        end
    end
end
local ok,why=pcall(loop);cleanup()
term.setBackgroundColor(colors.black);term.setTextColor(colors.white);term.clear();term.setCursorPos(1,1)
if not ok then printError(tostring(why)) else print("Repeater beendet.") end
]======]
FILES["toast.config.lua"]=[======[
-- Toast Control 2.1: eine Config pro Geraet. Start mit toast.lua.
-- role=auto erkennt Computer, Pocket und Turtle; Repeater bewusst einstellen.
return {
    role = "auto",
    job = "auto",                     -- Turtle: farm oder mining
    controllerId = 4,
    label = "",                      -- eigener Turtle-Name
    autoDiscover = true,              -- Zentrale lernt meldende Turtles
    autoPairPockets = true,           -- neue Toast-Pockets automatisch anmelden
    devices = {                      -- optional: feste/offline bekannte Geraete
        -- [5] = { job = "farm", label = "Weizen Nord" },
        -- [12] = { job = "mining", label = "Mine Nord" },
    },
    pocketIds = {},                   -- bekannte Pockets; eigene ID erkennt Installer
    display = { monitor = "auto", textScale = 0.5, pageSize = 0 },
    network = { pollInterval = 1, staleAfter = 15, commandTimeout = 10, maxDevices = 256 },
    -- Stabilitaet / Reset nach Fehlern (fehlt der Block, gelten diese Werte):
    recovery = {
        autoRestart = true,           -- Programm nach Absturz selbst neu starten
        restartDelay = 5,             -- Sekunden bis zum Neustart
        maxRestarts = 5,              -- hoechstens so oft in 10 Minuten
        autoRetry = 3,                -- Turtle: Auftrag nach Fehler so oft neu versuchen
        retryDelay = 30,              -- Sekunden Pause vor neuem Versuch
        moveRetries = 8,              -- Versuche, wenn Mob/Spieler den Weg blockiert
    },
    farm = {
        width = 9, length = 9, crop = "wheat", interval = 60,
        seedReserve = 64, radioTimeout = 60,
        water = { { column = 5, row = 5 } },
    },
    mine = {
        length = 100, height = 3, tunnels = 5, gap = 2,
        fuelTarget = 2000, radioTimeout = 60, freeSlots = 2, digRetries = 16,
        protectedBlocks = {
            "minecraft:bedrock", "minecraft:chest", "minecraft:trapped_chest",
            "minecraft:barrel", "minecraft:ender_chest", "minecraft:hopper",
            "minecraft:spawner", "minecraft:furnace", "minecraft:blast_furnace", "minecraft:smoker",
        },
    },
}
]======]
-- TOAST CONTROL 2.1 – Ein-Datei-Installer (alle Programme sind hier eingebaut).
-- Start: wget run <link>            -> Auswahl Update / Komplett neu
--        wget run <link> clean      -> Komplett neu ohne Rueckfrage nach dem Modus
--        wget run <link> farm|mining|repeater
-- Vor dem Schreiben wird ALLES Alte geloescht, damit nichts kollidiert.
local args={...}
local requested,clean
for _,a in ipairs(args) do
    a=a:lower()
    if a=="clean" or a=="neu" then clean=true
    elseif a=="farm" or a=="mining" or a=="repeater" then requested=a
    else error("Optional: farm / mining / repeater / clean",0) end
end
local code=FILES
local common=assert(load(code["toast_common.lua"],"@toast_common.lua"))()
term.clear();term.setCursorPos(1,1)
print("TOAST CONTROL "..common.version.." / Geraet #"..os.getComputerID())
print("")
if clean==nil then
    print("1 Update: alles loeschen,")
    print("  Config + Turtle-Fortschritt behalten")
    print("2 Komplett neu: ALLES loeschen")
    print("  (auch Config und Fortschritt)")
    write("Auswahl [1]: ")
    clean=read()=="2"
end
if clean then
    print("")
    printError("ACHTUNG: Alle Dateien auf diesem Geraet")
    printError("werden geloescht (auch eigene Programme).")
    if turtle then
        printError("Turtle VORHER an ihre Basis stellen,")
        printError("Blick zum Feld bzw. in die Mine!")
    end
    write("Zum Bestaetigen LOESCHEN eingeben: ")
    assert(read()=="LOESCHEN","Abgebrochen. Nichts geloescht.")
end
-- Im Update-Modus bleiben nur diese Dateien erhalten.
local KEEP={["toast.config.lua"]=true,["farm.config.lua"]=true,["mine.config.lua"]=true}
for _,n in ipairs({"toast_farm_state","toast_mining_state","toast_control_state","toast_pocket_state"})do
    KEEP[n]=true;KEEP[n..".tmp"]=true
end
local function readFile(path)
    local f=assert(fs.open(path,"r"));local value=f.readAll();f.close();return value
end
local function config(path)
    if clean or not fs.exists(path) then return nil end
    local fn,why=load(readFile(path),"@"..path)
    if not fn then printError("Config defekt, wird ersetzt: "..path.." / "..tostring(why));return nil end
    local ok,result=pcall(fn)
    if not ok or type(result)~="table" then printError("Config defekt, wird ersetzt: "..path);return nil end
    return result
end
local oldFarm,oldMine=config("/farm.config.lua"),config("/mine.config.lua")
local existing=config("/toast.config.lua")
if existing and not pcall(function()
    local copy=textutils.unserialize(textutils.serialize(existing));copy.role=nil;common.load(copy) end) then
    -- Kaputte/inkompatible Config nicht uebernehmen, sondern neu anlegen.
    printError("Vorhandene toast.config.lua ungueltig, wird neu erstellt.")
    existing=nil
end
local c=existing or assert(load(code["toast.config.lua"],"@toast.config.lua"))()
local role=turtle and "turtle" or (pocket and "pocket" or "controller")
if requested=="repeater" or (not turtle and not pocket and c.role=="repeater") then role="repeater" end
assert(role~="repeater" or (not turtle and not pocket),"Repeater auf stationaerem Computer installieren.")
assert(not requested or requested=="repeater" or role=="turtle","farm/mining nur fuer Turtles.")
if existing and not requested and not (c.role==nil or c.role=="auto" or c.role==role) then
    printError("Gespeicherte Rolle passt nicht zum Geraet, wird neu erkannt.")
    existing=nil;c=assert(load(code["toast.config.lua"],"@toast.config.lua"))()
end
local function chooseJob()
    while true do
        write("Turtle-Aufgabe: 1 Farm / 2 Mining: ")
        local answer=read():lower()
        if answer=="1" or answer=="farm" or answer=="f" then return "farm" end
        if answer=="2" or answer=="mining" or answer=="m" then return "mining" end
    end
end
local job
if role=="turtle" then
    if requested then job=requested
    elseif existing and common.job(c.job) then job=c.job
    elseif oldFarm and not oldMine then job="farm"
    elseif oldMine and not oldFarm then job="mining"
    else job=chooseJob() end
end
local function mergeLegacy(old,j)
    if not old then return end
    local section=j=="farm" and "farm" or "mine"
    if type(old[section])=="table" then c[section]=old[section] end
    if role=="controller" then
        for _,id in ipairs(old.turtleIds or {})do
            if common.id(id) and id~=os.getComputerID() then
                local prior=c.devices[id]
                c.devices[id]={job=prior and prior.job~=j and "auto" or j,label=common.label((old.labels or {})[id])}
            end
        end
        for _,id in ipairs(old.pocketIds or {})do
            if common.id(id) and not common.contains(c.pocketIds,id) then c.pocketIds[#c.pocketIds+1]=id end
        end
    end
end
if not existing then
    mergeLegacy(oldFarm,"farm");mergeLegacy(oldMine,"mining")
    local source=job=="farm" and oldFarm or job=="mining" and oldMine or oldMine or oldFarm
    if source then
        c.controllerId=common.id(source.controllerId) and source.controllerId or c.controllerId
        if type(source.display)=="table" then c.display=source.display end
        if type(source.network)=="table" then for k,v in pairs(source.network)do c.network[k]=v end end
        if job then c.label=common.label((source.labels or {})[os.getComputerID()]) end
    end
    if role=="controller" then c.controllerId=os.getComputerID()
    elseif role~="repeater" and not source then
        local found={}
        if common.refreshModems()>0 then
            print("Suche Zentrale...")
            found={rednet.lookup(common.protocol)}
            if #found==1 and common.id(found[1]) and found[1]~=os.getComputerID() then
                c.controllerId=found[1];print("Zentrale gefunden: #"..found[1])
            else found={} end
        end
        if #found==0 then
            while true do
                write("ID der Zentrale ["..c.controllerId.."]: ")
                local value=read();local id=value=="" and c.controllerId or tonumber(value)
                if common.id(id) and id~=os.getComputerID()then c.controllerId=id;break end
                print("Bitte eine andere gueltige Computer-ID eingeben.")
            end
        end
    end
end
c.role=role;c.job=job or c.job or "auto"
if job and (c.label==nil or c.label=="") then c.label=common.label(os.getComputerLabel and os.getComputerLabel() or "") end
common.load(c)
local names={"toast.lua","toast_common.lua"}
if role=="controller" then
    for _,name in ipairs({"toast_control.lua","toast_model.lua","toast_ui.lua"})do names[#names+1]=name end
elseif role=="pocket" then names[#names+1]="toast_pocket.lua";names[#names+1]="toast_ui.lua"
elseif role=="turtle" then
    local prefix=job=="farm" and "farm" or "mine"
    names[#names+1]=prefix.."_turtle.lua";names[#names+1]=prefix.."_common.lua"
else names[#names+1]="repeater.lua" end
for _,name in ipairs(names)do assert(code[name] and load(code[name],"@"..name),"Installer beschaedigt: "..name) end
if role=="turtle" then
    local prefix=job=="farm" and "farm" or "mine"
    assert(load(code[prefix.."_common.lua"]))().load(common.workerConfig(c))
end
-- Alles ist geprueft: jetzt restlos aufraeumen, dann neu schreiben.
local wipe={}
for _,name in ipairs(fs.list("/")) do
    local path="/"..name
    local local_drive=not fs.getDrive or fs.getDrive(path)=="hdd"
    if name~="rom" and local_drive and not fs.isReadOnly(path) and (clean or not KEEP[name]) then wipe[#wipe+1]=path end
end
if #wipe>0 then
    print("Loesche "..#wipe.." alte Dateien/Ordner...")
    for _,path in ipairs(wipe) do
        local ok,why=pcall(fs.delete,path)
        if not ok then printError("Nicht loeschbar: "..path.." / "..tostring(why)) end
    end
end
fs.makeDir("/toast")
for _,name in ipairs(names)do
    local path=name=="toast.lua" and "/toast.lua" or "/toast/"..name
    local f=assert(fs.open(path,"w"));f.write(code[name]);f.close()
end
if clean or not existing or requested then
    local f=assert(fs.open("/toast.config.lua","w"))
    f.write("-- Toast Control: edit /toast.config.lua\nreturn "..textutils.serialize(c).."\n");f.close()
end
print("")
print("TOAST CONTROL "..common.version.." installiert / Geraet #"..os.getComputerID())
print("Rolle: "..role..(job and " / "..job or "").." | Zentrale #"..c.controllerId)
print(clean and "Komplett neu: alles geloescht." or "Update: Config + Fortschritt behalten.")
print("Frei: "..math.floor(fs.getFreeSpace("/")/1024).." KB")
write("Config jetzt bearbeiten? (j/n) [n]: ")
if read():lower()=="j"then shell.run("edit","/toast.config.lua")end
local checked=common.load()
assert(checked.role==role,"role passt nicht zum erkannten Geraet.")
if role=="turtle" then
    local prefix=checked.job=="farm" and "farm" or "mine"
    assert(fs.exists("/toast/"..prefix.."_common.lua"),"Fuer andere Aufgabe Installer mit farm/mining erneut starten.")
    dofile("/toast/"..prefix.."_common.lua").load(common.workerConfig(checked))
end
write("Autostart einrichten? (j/n) [j]: ")
if read():lower()~="n"then
    local f=assert(fs.open("/startup.lua","w"));f.write('shell.run("/toast.lua")\n');f.close()
    print("Autostart eingerichtet.")
end
write("Jetzt starten? (j/n) [j]: ")
if read():lower()~="n"then shell.run("/toast.lua")end
