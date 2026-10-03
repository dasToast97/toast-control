-- TOAST CONTROL 2.9 – Ein-Datei-Installer (alle Programme sind hier eingebaut).
local FILES={}
FILES["toast.lua"]=[======[
-- Ein Startprogramm fuer Zentrale, Pocket, Farm, Mining und Repeater.
-- Neu: Waechter startet das Programm nach einem Absturz automatisch neu.
local common=dofile("/toast/toast_common.lua")
local args={...}

local function runOnce()
    local cfg=common.load()
    -- Name auch im Spiel setzen (steht dann an Turtle/Computer und in der Item-Info).
    if cfg.label~="" and os.setComputerLabel and os.getComputerLabel()~=cfg.label then
        pcall(os.setComputerLabel,cfg.label)
    end
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
    local program=({controller="toast_control.lua",pocket="toast_pocket.lua",repeater="repeater.lua",info="toast_info.lua"})[cfg.role]
    return assert(loadfile("/toast/"..program,"t",_ENV))(table.unpack(args))
end

-- Einstellungsmenue: toast.lua config
if args[1]=="config" or args[1]=="--config" then
    local ui=dofile("/toast/toast_setup.lua").new(common)
    local okc,raw=pcall(dofile,"/toast.config.lua")
    local c=common.withDefaults(okc and type(raw)=="table" and raw or {})
    local role=c.role~="auto" and c.role or (turtle and "turtle" or (pocket and "pocket" or "controller"))
    local job=role=="turtle" and c.job or nil
    local before=ui.layoutKey(c,job)
    while true do
        if not ui.run(c,{role=role,job=job}) then print("Abgebrochen, nichts geaendert.");return end
        local ok,why=pcall(function() common.load(common.copy(c)) end)
        if ok then break end
        printError(tostring(why));sleep(2)
    end
    if before~=ui.layoutKey(c,job) then ui.confirmReset(job) end
    c.role=role;c.label=nil
    local f=assert(fs.open("/toast.config.lua","w"));f.write(common.configText(c));f.close()
    term.clear();term.setCursorPos(1,1)
    print("Gespeichert. Starte Toast ...")
    args={}
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
    version="2.9",
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
-- ===== Standardwerte (fehlende Eintraege in der Config werden hiermit ergaenzt) =====
M.DEFAULTS={
    role="auto",job="auto",name="",controllerId=0,
    autoDiscover=true,autoPairPockets=true,devices={},pocketIds={},
    display={monitor="auto",size="3x4",textScale=0.5,pageSize=0},
    show="all",
    network={pollInterval=1,staleAfter=15,commandTimeout=10,maxDevices=256},
    recovery={autoRestart=true,restartDelay=5,maxRestarts=5,autoRetry=3,retryDelay=30,moveRetries=8},
    chunkload={enabled=false,chunks=1,idle=false,wakeOnWorldLoad=true,reportEvery=10},
    farm={length=9,width=9,side="right",crop="wheat",interval=60,seedReserve=0,radioTimeout=60,water={}},
    mine={length=100,height=3,tunnels=5,gap=2,side="right",sideDig=false,useCoal=true,radioTimeout=60,
        fuelTarget=2000,freeSlots=2,digRetries=16,protectedBlocks={}},
}
local function copy(v)
    if type(v)~="table" then return v end
    local t={};for k,x in pairs(v) do t[k]=copy(x) end;return t
end
M.copy=copy
local SECTIONS={display=true,network=true,recovery=true,chunkload=true,farm=true,mine=true}
function M.withDefaults(c)
    c=type(c)=="table" and c or {}
    for k,v in pairs(M.DEFAULTS) do
        if c[k]==nil then c[k]=copy(v)
        elseif SECTIONS[k] and type(c[k])=="table" then
            for sk,sv in pairs(v) do if c[k][sk]==nil then c[k][sk]=copy(sv) end end
        end
    end
    if c.name=="" and type(c.label)=="string" then c.name=c.label end
    return c
end
-- Saubere, kommentierte Config schreiben (nur die Abschnitte, die das Geraet braucht).
local CROP_NAMES={wheat="Weizen",carrots="Karotten",potatoes="Kartoffeln",beetroot="Rote Bete"}
M.CROP_NAMES=CROP_NAMES
function M.configText(c)
    local out={}
    local function q(v)
        if type(v)=="string" then return string.format("%q",v) end
        if type(v)=="table" then
            local parts={}
            for _,x in ipairs(v) do
                if type(x)=="table" then
                    local f={};for k2,x2 in pairs(x) do f[#f+1]=k2.." = "..q(x2) end
                    table.sort(f);parts[#parts+1]="{ "..table.concat(f,", ").." }"
                else parts[#parts+1]=q(x) end
            end
            return #parts==0 and "{}" or "{ "..table.concat(parts,", ").." }"
        end
        return tostring(v)
    end
    local function line(ind,key,val,comment)
        local s=string.rep(" ",ind)..key.." = "..val..","
        if comment then s=s..string.rep(" ",math.max(1,38-#s)).."-- "..comment end
        out[#out+1]=s
    end
    local function section(name,title,fields,t)
        out[#out+1]=""
        out[#out+1]="    -- "..title
        out[#out+1]="    "..name.." = {"
        for _,f in ipairs(fields) do line(8,f[1],q(t[f[1]]),f[2]) end
        out[#out+1]="    },"
    end
    local role,job=c.role,c.job
    local what=role=="turtle" and ("Turtle / "..(job=="farm" and "Farm" or "Mining")) or
        ({controller="Zentrale",pocket="Pocket",repeater="Repeater",info="Infoscreen"})[role] or tostring(role)
    out[#out+1]="-- Toast Control "..M.version.." - Einstellungen"
    out[#out+1]="-- Geraet #"..os.getComputerID().." / "..what
    out[#out+1]="-- Aendern im Spiel:  toast.lua config     (oder: edit /toast.config.lua)"
    out[#out+1]="return {"
    line(4,"role",q(role))
    if role=="turtle" then line(4,"job",q(job),"farm oder mining") end
    line(4,"name",q(c.name or ""),"Anzeigename")
    if role=="controller" then line(4,"controllerId",q(c.controllerId),"= ID dieser Zentrale")
    elseif role~="repeater" then line(4,"controllerId",q(c.controllerId),"ID der Zentrale") end
    if role=="info" then line(4,"show",q(c.show),"\"all\", \"farm\", \"mining\" oder Turtle-ID") end
    if role=="turtle" and job=="mining" then
        section("mine","Mine: Turtle steht an der Basis und schaut in die Mine",{
            {"length","Ganglaenge nach vorne (1-1024)"},{"height","Ganghoehe 1-64 (3, 6, 9 ... sparsam)"},
            {"tunnels","Anzahl Gaenge (1-64)"},{"gap","Bloecke zwischen den Gaengen (0-16)"},
            {"side","Gaenge nach \"right\" oder \"left\""},{"sideDig","nur gap = 0: seitlich mitabbauen"},
            {"useCoal","true = gefundene Kohle direkt als Fuel"},
            {"radioTimeout","s ohne Zentrale bis Stopp (0 = weiter)"},{"fuelTarget","an der Basis bis hierhin tanken"},
            {"freeSlots","so wenige Slots frei -> abladen"},{"digRetries","Versuche bei Kies/Sand"},
            {"protectedBlocks","diese Bloecke nie abbauen"}},c.mine)
    elseif role=="turtle" then
        section("farm","Feld: Turtle steht an der Basis und schaut aufs Feld",{
            {"length","Feldlaenge nach vorne (1-32)"},{"width","Feldbreite zur Seite (1-32)"},
            {"side","Feld nach \"right\" oder \"left\""},{"crop","wheat, carrots, potatoes, beetroot"},
            {"interval","Pause zwischen Runden in s"},{"seedReserve","Saatgut behalten (0 = so viel wie das Feld braucht)"},
            {"radioTimeout","s ohne Zentrale bis Stopp (0 = weiter)"},{"water","leer lassen: wird erkannt"}},c.farm)
    end
    if role=="turtle" then
        section("chunkload","Chunks laden (Mod CCChunkloader)",{
            {"enabled","true = arbeitet auch ohne Spieler"},{"chunks","1 / 9 / 21 (1 reicht, wandert mit)"},
            {"idle","true = auch an der Basis wach"},{"wakeOnWorldLoad","nach Serverneustart weiter"},
            {"reportEvery","alle x s kurz funken"}},c.chunkload)
    end
    if role=="controller" then
        section("display","Bildschirm",{
            {"monitor","\"auto\", \"terminal\" oder Name"},{"size","Bloecke Hoehe x Breite, z.B. \"3x4\", oder \"auto\""},
            {"textScale","nur ohne size: Schrift 0.5 bis 5"},{"pageSize","Zeilen pro Seite (0 = auto)"}},c.display)
    elseif role=="info" then
        section("display","Bildschirm",{
            {"monitor","\"auto\" = alle Monitore, oder Name"},{"size","Bloecke Hoehe x Breite, z.B. \"3x4\", oder \"auto\""},
            {"textScale","nur ohne size: Schrift 0.5 bis 5"}},c.display)
        out[#out+1]=""
        line(4,"autoDiscover",q(c.autoDiscover),"neue Turtles automatisch aufnehmen")
        line(4,"autoPairPockets",q(c.autoPairPockets),"neue Pockets automatisch aufnehmen")
        out[#out+1]="    devices = {                       -- feste Namen: [ID] = { job = ..., name = ... }"
        local ids={};for id in pairs(c.devices or {}) do ids[#ids+1]=id end;table.sort(ids)
        for _,id in ipairs(ids) do
            local d=c.devices[id]
            out[#out+1]="        ["..id.."] = { job = "..q(d.job)..", name = "..q(d.name or d.label or "").." },"
        end
        out[#out+1]="    },"
        line(4,"pocketIds",q(c.pocketIds or {}),"bekannte Pockets")
    end
    if role=="controller" or role=="pocket" or role=="info" then
        section("network","Funk",{
            {"pollInterval","Abfrage alle x s"},{"staleAfter","nach x s OFFLINE"},
            {"commandTimeout","Befehl x s wiederholen"},{"maxDevices","hoechstens so viele Turtles"}},c.network)
    end
    section("recovery","Stabilitaet",{
        {"autoRestart","nach Absturz neu starten"},{"restartDelay","Sekunden bis Neustart"},
        {"maxRestarts","hoechstens so oft in 10 min"},{"autoRetry","Turtle: neue Versuche nach Fehler"},
        {"retryDelay","Sekunden bis neuer Versuch"},{"moveRetries","Versuche bei Mob im Weg"}},c.recovery)
    out[#out+1]="}"
    return table.concat(out,"\n").."\n"
end
function M.load(c)
    c=c or dofile("/toast.config.lua")
    assert(type(c)=="table","Config muss eine Tabelle sein.")
    M.withDefaults(c)
    c.role=c.role or "auto"
    if c.role=="auto" then c.role=turtle and "turtle" or (pocket and "pocket" or "controller") end
    assert(({controller=true,turtle=true,pocket=true,repeater=true,info=true})[c.role],"role: auto/controller/turtle/pocket/repeater/info")
    assert(M.id(c.controllerId),"controllerId: ganze ID 0 bis 65500.")
    if c.role=="controller" then assert(os.getComputerID()==c.controllerId,"controllerId stimmt nicht mit Zentralen-ID ueberein.") end
    if c.role=="turtle" then
        assert(turtle and M.job(c.job),"Turtle: job=farm oder mining einstellen.")
        assert(os.getComputerID()~=c.controllerId,"Turtle und Zentrale duerfen nicht dieselbe ID haben.")
    end
    if c.role=="pocket" then assert(pocket and os.getComputerID()~=c.controllerId,"Pocket/Zentralen-ID ungueltig.") end
    if c.role=="info" then
        assert(not turtle and not pocket and os.getComputerID()~=c.controllerId,"Infoscreen: eigener Computer, nicht die Zentrale.")
        assert(c.show=="all" or c.show=="farm" or c.show=="mining" or M.id(c.show),"show: \"all\", \"farm\", \"mining\" oder Turtle-ID (Zahl).")
    end
    assert(type(c.autoDiscover)=="boolean" and type(c.autoPairPockets)=="boolean","autoDiscover/autoPairPockets: true oder false.")
    assert(type(c.devices)=="table" and type(c.pocketIds)=="table","devices/pocketIds fehlen.")
    local used={[c.controllerId]=true};local count=0
    for id,d in pairs(c.devices) do
        assert(M.id(id) and not used[id] and type(d)=="table" and (M.job(d.job) or d.job=="auto"),"devices: ungueltige ID oder job.")
        if d.name~=nil then d.label=d.name end
        assert(d.label==nil or type(d.label)=="string","devices.name: Text in Anfuehrungszeichen verwenden.")
        used[id]=true;count=count+1
    end
    local pc=0
    for i,id in pairs(c.pocketIds) do
        assert(M.integer(i,1,#c.pocketIds) and M.id(id) and not used[id],"pocketIds: ungueltige/doppelte ID.")
        used[id]=true;pc=pc+1
    end
    assert(pc==#c.pocketIds,"pocketIds: Liste ohne Luecken.")
    local d=c.display;assert(type(d)=="table" and type(d.monitor)=="string","display.monitor fehlt.")
    assert(d.size=="auto" or M.parseSize(d.size),"display.size: Hoehe x Breite in Bloecken, z.B. \"3x4\" (max 6x8), oder \"auto\".")
    assert(M.integer(M.number(d.textScale)*2,1,10) and M.integer(d.pageSize,0,1000),"textScale/pageSize ungueltig.")
    local n=c.network;assert(type(n)=="table","network fehlt.")
    assert(M.number(n.pollInterval)>=0.25 and M.number(n.pollInterval)<=5,"pollInterval: 0.25 bis 5.")
    assert(M.number(n.staleAfter)>=n.pollInterval*2 and M.number(n.staleAfter)<=60,"staleAfter ungueltig.")
    assert(M.number(n.commandTimeout)>=1 and M.number(n.commandTimeout)<=15,"commandTimeout: 1 bis 15.")
    assert(M.integer(n.maxDevices,1,1024) and count<=n.maxDevices,"maxDevices: 1 bis 1024; Liste zu gross.")
    c.recovery=M.recovery(c.recovery)
    if c.chunkload~=nil then M.chunkConfig(c.chunkload) end
    -- "name" ist der neue, gut sichtbare Eintrag; "label" bleibt fuer alte Configs gueltig.
    if c.name~=nil then
        assert(type(c.name)=="string","name: Text in Anfuehrungszeichen, z.B. name = \"Mine Nord\"")
        c.label=c.name
    end
    c.label=M.label(c.label);c.name=c.label
    return c
end
function M.workerConfig(c)
    return {role="turtle",controllerId=c.controllerId,turtleIds={os.getComputerID()},pocketIds={},
        labels={},farm=c.farm,mine=c.mine,display=c.display,network=c.network,recovery=M.recovery(c.recovery),
        chunkload=c.chunkload}
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
-- ===== Monitorgroesse in Bloecken (Hoehe x Breite) -> passende Schriftgroesse =====
-- CC:Tweaked: Zeichen = (64 * Bloecke - 20) / (6 bzw. 9 * Schriftgroesse)
M.SCALES={5,4.5,4,3.5,3,2.5,2,1.5,1,0.5}
M.FIT={control={36,18},info={30,14}}       -- Mindestgroesse in Zeichen (Breite, Hoehe)
function M.parseSize(size)
    if type(size)~="string" then return nil end
    local h,w=size:lower():gsub("%s",""):match("^(%d+)x(%d+)$")
    h,w=tonumber(h),tonumber(w)
    if h and w and h>=1 and h<=6 and w>=1 and w<=8 then return h,w end
end
function M.monitorChars(hB,wB,s)
    return math.floor((64*wB-20)/(6*s)+0.5),math.floor((64*hB-20)/(9*s)+0.5)
end
function M.scaleFor(size,kind)
    local hB,wB=M.parseSize(size);if not hB then return nil end
    local fit=M.FIT[kind] or M.FIT.control
    for _,s in ipairs(M.SCALES) do
        local w,h=M.monitorChars(hB,wB,s)
        if w>=fit[1] and h>=fit[2] then return s,w,h end
    end
    return 0.5,M.monitorChars(hB,wB,0.5)
end
-- Schrift fuer einen Monitor setzen. size "HxB": berechnet (und am echten Monitor
-- nachgeprueft), "auto": ausprobiert. Gibt Schriftgroesse zurueck.
function M.applyScale(mon,display,kind)
    if not mon or not mon.setTextScale then return end
    local fit=M.FIT[kind] or M.FIT.control
    local function measure()
        for _,s in ipairs(M.SCALES) do
            pcall(mon.setTextScale,s)
            local w,h=mon.getSize()
            if w>=fit[1] and h>=fit[2] then return s end
        end
        pcall(mon.setTextScale,0.5);return 0.5
    end
    local size=display and display.size
    if size=="auto" or kind=="extra" then return measure() end
    local s=M.scaleFor(size,kind)
    if s then
        pcall(mon.setTextScale,s)
        local w,h=mon.getSize()
        -- Angabe passt nicht zum echten Monitor (z.B. kleiner): selbst ausmessen
        if w<math.min(fit[1],26) or h<math.min(fit[2],12) then return measure() end
        return s
    end
    pcall(mon.setTextScale,display and display.textScale or 0.5)
    return display and display.textScale
end
-- ===== CCChunkloader (Mod) =====
-- Anzahl Chunks -> Radius des Mods (Chunks mit Abstand < Radius werden geladen).
M.CHUNK_RADIUS={[1]=0.5,[9]=1.5,[21]=2.5}
M.MODEM_ITEMS={["computercraft:wireless_modem_normal"]=true,["computercraft:wireless_modem_advanced"]=true}
-- Gleiche Formel wie im Mod (Standardwerte): 0.0333 * 2^Abstand pro Chunk und Tick.
function M.chunkCostPerTick(radius)
    local total,s=0,math.ceil(radius)+1
    for x=-s,s do for z=-s,s do
        local d=math.sqrt(x*x+z*z)
        if d<radius then total=total+0.0333333*2^d end
    end end
    return total
end
function M.chunkFuelPerHour(chunks)
    local r=M.CHUNK_RADIUS[chunks];if not r then return 0 end
    return math.floor(M.chunkCostPerTick(r)*72000+0.5)
end
function M.chunkConfig(c)
    c=type(c)=="table" and c or {}
    local r={enabled=c.enabled==true,chunks=c.chunks or 1,idle=c.idle==true,
        wake=c.wakeOnWorldLoad~=false,report=c.reportEvery or 10}
    assert(type(c.enabled)=="nil" or type(c.enabled)=="boolean","chunkload.enabled: true oder false.")
    assert(M.CHUNK_RADIUS[r.chunks],"chunkload.chunks: 1, 9 oder 21.")
    assert(M.integer(r.report,3,120),"chunkload.reportEvery: 3 bis 120 Sekunden.")
    r.radius=M.CHUNK_RADIUS[r.chunks]
    return r
end
-- Ausruestung mit Chunkloader: Seite A = Chunkloader (bleibt immer dran),
-- Seite B wechselt zwischen Werkzeug (zum Abbauen) und Modem (zum Funken).
-- Das jeweils andere Teil liegt im Inventar.
function M.gear(cl,tools)
    local side
    for _,s in ipairs({"left","right"}) do if peripheral.getType(s)=="chunkloader" then side=s end end
    if not side then return nil,"Chunkloader-Upgrade nicht angebaut (oder chunkload.enabled=false setzen)." end
    local g={side=side,other=side=="left" and "right" or "left",radius=0,cost=0}
    local dev=peripheral.wrap(side)
    local equip=g.other=="left" and turtle.equipLeft or turtle.equipRight
    local function find(set)
        for i=1,16 do local it=turtle.getItemDetail(i);if it and set[it.name] then return i end end
    end
    local function swapIn(set)
        local slot=find(set);if not slot then return false end
        local prev=turtle.getSelectedSlot and turtle.getSelectedSlot()
        turtle.select(slot);local ok=equip()
        if prev then turtle.select(prev) end
        return ok
    end
    function g.hasModem() return peripheral.getType(g.other)=="modem" or find(M.MODEM_ITEMS)~=nil end
    function g.radio()
        if peripheral.getType(g.other)=="modem" then return true end
        local ok=swapIn(M.MODEM_ITEMS);if ok then M.refreshModems() end
        return ok
    end
    function g.tool()
        if peripheral.getType(g.other)~="modem" and not find(tools) then return true end
        return swapIn(tools)
    end
    function g.set(r)
        if r==g.radius then return true end
        local ok=pcall(dev.setRadius,r)
        if ok then g.radius=r;local okr,v=pcall(dev.getFuelRate);g.cost=okr and tonumber(v) or M.chunkCostPerTick(r) end
        return ok
    end
    function g.perSecond() return g.cost*20 end
    local okr,r=pcall(dev.getRadius);if okr and tonumber(r) then g.radius=tonumber(r) end
    local okc,v=pcall(dev.getFuelRate);g.cost=okc and tonumber(v) or 0
    pcall(dev.setWakeOnWorldLoad,cl.wake)
    return g
end
-- Fehler, bei denen ein automatischer neuer Versuch gefaehrlich waere.
function M.retryable(fault)
    if type(fault)~="string" or fault=="" then return false end
    for _,word in ipairs({"Geschuetzt","Nicht abbaubar","Fuelbedarf","Position unklar"}) do
        if fault:find(word,1,true) then return false end
    end
    return true
end
return M
]======]
FILES["toast_setup.lua"]=[======[
-- Toast Control: Einstellungsmenue (Installer und "toast.lua config").
-- Eine Uebersicht mit Nummern; Nummer = aendern, Enter = fertig.
local S={}
function S.new(common)
    local M={}
    local W=({term.getSize()})[1]
    local color=term.isColor and term.isColor()
    local function fg(c) if color then term.setTextColor(c) end end
    local function cut(s) return tostring(s):sub(1,W) end
    local function header(sub)
        term.setBackgroundColor(colors.black);term.clear();term.setCursorPos(1,1)
        fg(colors.cyan);print(cut("TOAST SETUP "..common.version));fg(colors.lightGray);print(cut(sub));fg(colors.white)
    end
    local function hint(s) fg(colors.lightGray);print(cut(s));fg(colors.white) end
    local function ask(label,default,lo,hi)
        while true do
            write(cut(label.." ["..tostring(default).."]: "))
            local v=read()
            if v=="" then return default end
            local n=tonumber(v)
            if n and n%1==0 and n>=lo and n<=hi then return n end
            fg(colors.orange);print(cut("  Bitte "..lo.." bis "..hi));fg(colors.white)
        end
    end
    local function askText(label,default)
        write(cut(label..(default~="" and " ["..default.."]" or "")..": "))
        local v=read()
        if v=="" then return default end
        if v=="-" then return "" end
        return common.label(v)
    end
    local function yesno(label,default)
        while true do
            write(cut(label.." (j/n) ["..(default and "j" or "n").."]: "))
            local v=read():lower()
            if v=="" then return default end
            if v=="j" or v=="ja" or v=="y" then return true end
            if v=="n" or v=="nein" then return false end
        end
    end
    local function askSide(label,default)
        while true do
            write(cut(label.." r/l ["..(default=="left" and "l" or "r").."]: "))
            local v=read():lower()
            if v=="" then return default or "right" end
            if v=="r" or v=="rechts" or v=="right" then return "right" end
            if v=="l" or v=="links" or v=="left" then return "left" end
        end
    end
    local function sideName(s) return s=="left" and "links" or "rechts" end
    local showText,editShow
    -- ---- Zusammenfassungen ----
    local function mineText(m)
        return m.length.."x"..m.height.."x"..m.tunnels.." Abst."..m.gap.." "..sideName(m.side)
            ..(m.sideDig and m.gap==0 and " +seitl" or "")..(m.useCoal~=false and " +Kohle" or "")
    end
    local function farmText(f)
        return f.length.."x"..f.width.." "..sideName(f.side).." "..(common.CROP_NAMES[f.crop] or f.crop)
    end
    local function chunkText(cl)
        if not cl.enabled then return "aus" end
        return cl.chunks.."  -"..common.chunkFuelPerHour(cl.chunks).." Fuel/h"..(cl.idle and " +Basis" or "")
    end
    local function radioText(t) return t==0 and "ohne Zentrale weiter" or ("Stopp nach "..t.." s") end
    -- ---- Bearbeiten ----
    local function editMine(c)
        local m=c.mine
        header("Mine (von der Basis aus nach vorne)")
        hint("Enter = Wert behalten")
        m.length=ask("Laenge (1-1024)",m.length,1,1024)
        m.height=ask("Hoehe (1-64, 3/6/9 sparsam)",m.height,1,64)
        m.tunnels=ask("Gaenge (1-64)",m.tunnels,1,64)
        if m.tunnels>1 then
            m.gap=ask("Abstand (0-16)",m.gap,0,16)
            m.side=askSide("Gaenge nach",m.side)
            if m.gap==0 then
                hint("Seitlich mitabbauen: weniger Fuel,")
                hint("dafuer langsamer.")
                m.sideDig=yesno("Seitlich mitabbauen?",m.sideDig==true)
            else m.sideDig=false end
        else m.sideDig=false end
        hint("Kohle aus der Mine: direkt verbrennen")
        hint("(spart Fahrten) oder abliefern.")
        m.useCoal=yesno("Gefundene Kohle als Fuel nutzen?",m.useCoal~=false)
    end
    local function editFarm(c)
        local f=c.farm
        header("Feld (von der Basis aus nach vorne)")
        hint("Enter = behalten. Wasser wird erkannt.")
        f.length=ask("Laenge (1-32)",f.length,1,32)
        f.width=ask("Breite (1-32)",f.width,1,32)
        if f.width>1 then f.side=askSide("Feld nach",f.side) end
        local crops={"wheat","carrots","potatoes","beetroot"}
        local cur=1;for i,v in ipairs(crops) do if v==f.crop then cur=i end end
        hint("1 Weizen 2 Karotten 3 Kartoffeln 4 Rote Bete")
        f.crop=crops[ask("Pflanze",cur,1,4)]
        f.interval=ask("Pause zwischen Runden (s)",f.interval,1,86400)
        hint("Saatgut aus der Ernte wird behalten.")
        hint("0 = automatisch passend zum Feld")
        f.seedReserve=ask("Saatgut behalten (0-256)",f.seedReserve or 0,0,256)
        f.water={}
    end
    local function editChunks(c,job)
        local cl=c.chunkload
        header("Chunks laden (Mod CCChunkloader)")
        hint("0 = aus")
        for _,n in ipairs({1,9,21}) do
            local fph=common.chunkFuelPerHour(n)
            hint(n.." = ~"..fph.." Fuel/h (~"..math.ceil(fph/80).." Kohle/h)")
        end
        local wasOn=cl.enabled
        local cur=cl.enabled and cl.chunks or 0
        while true do
            local n=ask("Chunks",cur,0,21)
            if n==0 then cl.enabled=false;break end
            if common.CHUNK_RADIUS[n] then cl.enabled=true;cl.chunks=n;break end
            fg(colors.orange);print("  0, 1, 9 oder 21");fg(colors.white)
        end
        if cl.enabled then
            hint("Auch an der Basis geladen lassen?")
            hint("Noetig, damit sie START hoert, wenn")
            hint("niemand in der Naehe ist (z.B. Nether)")
            cl.idle=yesno("An der Basis wach",(not wasOn) or cl.idle==true)
            hint("Anbau: Chunkloader + "..(job=="farm" and "Werkzeug" or "Spitzhacke"))
            hint("Funkmodem ins Turtle-Inventar legen.")
            sleep(1.5)
        end
    end
    local function editRadio(c,job)
        local sec=job=="farm" and c.farm or c.mine
        header("Funk")
        hint("Keine Verbindung zur Zentrale:")
        hint("nach x Sekunden stoppen + heimfahren.")
        hint("0 = trotzdem weiterarbeiten")
        while true do
            local t=ask("Sekunden (0, 10-300)",sec.radioTimeout,0,300)
            if t==0 or t>=10 then sec.radioTimeout=t;break end
        end
    end
    local function editMonitor(c,role)
        local d=c.display
        local kind=role=="info" and "info" or "control"
        header(role=="info" and "Bildschirm des Infoscreens" or "Bildschirm der Zentrale")
        hint("Monitor: auto = Advanced Monitor suchen,")
        hint("terminal = Computerbildschirm")
        local names={}
        for _,n in ipairs(peripheral.getNames()) do if peripheral.getType(n)=="monitor" then names[#names+1]=n end end
        if #names>0 then hint("Gefunden: "..table.concat(names,", ")) end
        write(cut("Monitor ["..d.monitor.."]: "))
        local v=read();if v~="" then d.monitor=v end
        hint("Groesse in Bloecken: Hoehe x Breite")
        hint("z.B. 3x4 (max 6x8), auto = ausmessen")
        while true do
            write(cut("Groesse ["..tostring(d.size).."]: "))
            local sv=read():lower():gsub("%s","")
            if sv=="" then sv=d.size end
            if sv=="auto" or common.parseSize(sv) then d.size=sv;break end
            fg(colors.orange);print("  z.B. 3x4 oder auto");fg(colors.white)
        end
        if d.size~="auto" then
            local s,w,h=common.scaleFor(d.size,kind)
            hint("-> Schrift "..s..", "..w.." x "..h.." Zeichen")
        end
        sleep(1.5)
    end
    function showText(v)
        if type(v)=="number" then return "Turtle #"..v end
        return ({all="Alle Turtles",farm="Alle Farmen",mining="Alle Minen"})[v] or tostring(v)
    end
    function editShow(c)
        header("Was soll der Infoscreen zeigen?")
        print("")
        hint("1 Alle Turtles")
        hint("2 Alle Farmen")
        hint("3 Alle Minen")
        hint("4 Eine bestimmte Turtle")
        local cur=c.show=="farm" and 2 or c.show=="mining" and 3 or type(c.show)=="number" and 4 or 1
        local n=ask("Auswahl",cur,1,4)
        if n==1 then c.show="all" elseif n==2 then c.show="farm" elseif n==3 then c.show="mining"
        else
            hint("ID steht an der Zentrale hinter dem Namen")
            hint("(z.B. Mine Nord #12 -> 12)")
            c.show=ask("Turtle-ID",type(c.show)=="number" and c.show or 1,0,65500)
        end
    end
    local function editDevices(c)
        header("Geraete")
        c.autoDiscover=yesno("Neue Turtles automatisch aufnehmen?",c.autoDiscover)
        c.autoPairPockets=yesno("Neue Pockets automatisch aufnehmen?",c.autoPairPockets)
    end
    local function editController(c)
        header("Zentrale")
        while true do
            local id=ask("ID der Zentrale",c.controllerId,0,65500)
            if id==os.getComputerID() and c.controllerId==id then break end
            if id~=os.getComputerID() then c.controllerId=id;break end
            fg(colors.orange);print("  Das ist die eigene ID.");fg(colors.white)
        end
    end
    local function items(c,info)
        local role,job=info.role,info.job
        local list={{"Name",function() return c.name~="" and c.name or "-" end,function()
            header("Name");hint("Leer lassen = behalten, - = loeschen")
            c.name=askText("Name",c.name);c.label=c.name end}}
        if role~="controller" and role~="repeater" then
            list[#list+1]={"Zentrale",function() return "#"..c.controllerId end,function() editController(c) end}
        end
        if role=="turtle" and job=="mining" then
            list[#list+1]={"Mine",function() return mineText(c.mine) end,function() editMine(c) end}
        elseif role=="turtle" then
            list[#list+1]={"Feld",function() return farmText(c.farm) end,function() editFarm(c) end}
        end
        if role=="turtle" then
            list[#list+1]={"Chunks",function() return chunkText(c.chunkload) end,function() editChunks(c,job) end}
            list[#list+1]={"Funk",function() return radioText((job=="farm" and c.farm or c.mine).radioTimeout) end,
                function() editRadio(c,job) end}
        end
        if role=="controller" or role=="info" then
            list[#list+1]={"Monitor",function() return (c.display.monitor=="auto" and "" or (c.display.monitor.." "))
                ..(c.display.size=="auto" and "Groesse auto" or (tostring(c.display.size).." Bloecke"))
                end,
                function() editMonitor(c,role) end}
        end
        if role=="info" then
            list[#list+1]={"Anzeige",function() return showText(c.show) end,function() editShow(c) end}
        end
        if role=="controller" then
            list[#list+1]={"Geraete",function() return (c.autoDiscover and "Turtles auto" or "Turtles fest")..", "
                ..(c.autoPairPockets and "Pockets auto" or "Pockets fest") end,function() editDevices(c) end}
        end
        return list
    end
    -- Uebersicht; true = uebernehmen, false = abbrechen
    function M.run(c,info)
        local what=info.role=="turtle" and ("Turtle #"..os.getComputerID().." / "..(info.job=="farm" and "Farm" or "Mining"))
            or (({controller="Zentrale",pocket="Pocket",repeater="Repeater",info="Infoscreen"})[info.role].." #"..os.getComputerID())
        while true do
            local list=items(c,info)
            header(what)
            print("")
            for i,it in ipairs(list) do
                fg(colors.yellow);write(i.." ");fg(colors.white)
                write(string.format("%-9s",it[1]))
                fg(colors.lightGray);print(tostring(it[2]()):sub(1,math.max(1,W-12)));fg(colors.white)
            end
            print("")
            hint("Nummer = aendern, Enter = "..(info.installer and "weiter" or "speichern")
                ..(info.installer and "" or ", q = Abbruch"))
            write("> ")
            local v=read()
            if v=="" then return true end
            if v:lower()=="q" and not info.installer then return false end
            local n=tonumber(v)
            if n and list[n] then list[n][3]() end
        end
    end
    -- Neue Minenmasse bei vorhandenem Fortschritt -> neuer Auftrag (Turtle an der Basis)
    function M.layoutKey(c,job)
        if job=="mining" then local m=c.mine
            return table.concat({m.length,m.height,m.tunnels,m.gap,m.side,tostring(m.sideDig==true)},":") end
        if job=="farm" then local f=c.farm return table.concat({f.length,f.width,f.side,f.crop},":") end
        return ""
    end
    function M.confirmReset(job)
        if job~="mining" then return end
        local file="/toast_mining_state"
        if not (fs.exists(file) or fs.exists(file..".tmp")) then return end
        header("Neue Minenmasse")
        print("Neue Masse = neuer Auftrag.")
        print("Die Turtle muss an ihrer Basis stehen")
        print("(Blick in die Mine).")
        if yesno("Steht sie an der Basis?",true) then
            for _,p in ipairs({file,file..".tmp"}) do if fs.exists(p) then fs.delete(p) end end
            return true
        end
        printError("Erst an die Basis stellen, dann: toast.lua --dock --new")
        sleep(2)
    end
    M.yesno=yesno;M.header=header;M.hint=hint;M.ask=ask
    return M
end
return S
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
        common.applyScale(screen,cfg.display,"control")
    else
        if cfg.display.monitor~="auto" and cfg.display.monitor~="terminal" then
            print("Advanced Monitor '"..cfg.display.monitor.."' fehlt, nutze Bildschirm.")
        end
        screen,name=term,nil
    end
end
bindScreen()
local UI=dofile("/toast/toast_ui.lua")
local ui=UI.new(screen,cfg)
local model=dofile("/toast/toast_model.lua").new(cfg)
local dirty=true
-- Zeichnen gedrosselt: Viele Statusmeldungen loesen nicht mehr je ein
-- komplettes Neuzeichnen aus (verhinderte Lag bei grossen Flotten).
local function draw()
    local fleet=model.fleet()
    local ok,why=pcall(ui.draw,fleet,true,model.notice)
    if not ok then
        common.log("Anzeigefehler: "..tostring(why))
        bindScreen();ui.setScreen(screen)
        pcall(ui.draw,fleet,true,model.notice)
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
            if (a=="q" or a=="Q") and not ui.help then quit=true;return end
            action(ui.char(a))
        elseif e=="key" then action(ui.key(keys.getName(a)))
        elseif e=="mouse_scroll" then action(a>0 and "down" or "up") end
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
UI.resetTrack(screen);UI.resetTrack(term)
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
                and b.version==1 and (b.role=="pocket" or b.role=="info") and b.controllerId==cfg.controllerId) then return false end
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
-- Toast Control: Oberflaeche fuer Zentrale (Monitor) und Pocket.
-- Passt sich der Bildschirmgroesse an: Liste aller Turtles mit Farbe je Zustand,
-- Antippen zeigt Details. Farm und Mining zeigen jeweils nur ihre eigenen Werte.
local common=dofile("/toast/toast_common.lua")
local M={}
-- Zustand -> Kurztext + Farbe
local WORK={["Abbau"]="Baut ab",["Ernte"]="Erntet",["Pflanzen"]="Pflanzt",["Feld pruefen"]="Prueft",
    ["Fortsetzen"]="Startet",["Neuer Versuch"]="Startet"}
function M.state(e,link)
    local d=e and e.data
    if not link or not e or not e.online or not d then return "Offline","off" end
    if d.recovery then return "Pos. ?","fault" end
    if d.fault or d.status=="Rueckweg blockiert" then return "Fehler","fault" end
    local s=tostring(d.status or "")
    if WORK[s] then return WORK[s],"work" end
    if s=="Rueckkehr" then return "Heimweg","move" end
    if s=="Warten" then return "Wartet","wait" end
    if s=="Fertig" then return "Fertig","done" end
    if s=="Bereit" or s=="Reset" or s=="" then return "Bereit","idle" end
    return "Problem","warn"
end
local COLOR={work=colors.lime,move=colors.lightBlue,wait=colors.cyan,done=colors.green,
    idle=colors.lightGray,warn=colors.orange,fault=colors.red,off=colors.gray}
M.COLOR=COLOR
local function num(n) return common.number(n) end
local function short(n)
    n=num(n)
    if math.abs(n)>=1000000 then return string.format("%.1fM",n/1000000) end
    if math.abs(n)>=10000 then return string.format("%.1fk",n/1000) end
    return tostring(math.floor(n))
end
-- Dunkler Balken-Hintergrund: "braun" wird umdefiniert (sonst nirgends benutzt),
-- weil CC kein dunkleres Grau als colors.gray kennt.
local TRACK=colors.brown
M.TRACK=TRACK
local function setTrack(screen)
    if screen.isColor and screen.isColor() and screen.setPaletteColour then
        pcall(screen.setPaletteColour,TRACK,0x262626)
    end
end
M.setTrack=setTrack
function M.resetTrack(screen)
    if screen and screen.setPaletteColour and term.nativePaletteColour then
        pcall(function() screen.setPaletteColour(TRACK,term.nativePaletteColour(TRACK)) end)
    end
end
-- Balken in einer Listenzeile: obere 2/3 der Zeile gefuellt (Zeichen 143),
-- unten bleibt ein Spalt -> untereinander stehende Balken beruehren sich nicht.
local function thinBar(text,x,y,width,pc,fg,bg)
    local f=math.floor(width*math.max(0,math.min(1,pc))+0.5)
    text(x,y,string.rep("\143",f),fg or colors.lime,bg or colors.black)
    text(x+f,y,string.rep("\143",width-f),TRACK,bg or colors.black)
end
-- Zeichenhilfen fuer einen Bildschirm (Farbe nur, wenn der Bildschirm sie kann)
local function painter(screen)
    local w,h=screen.getSize()
    local color=screen.isColor and screen.isColor()
    local P={w=w,h=h}
    setTrack(screen)
    local function col(c)
        if color then return c end
        if c==TRACK then return colors.gray end
        if c==colors.black or c==colors.gray or c==colors.lightGray or c==colors.white then return c end
        return colors.white
    end
    function P.fill(y,bg) if y<1 or y>h then return end screen.setCursorPos(1,y);screen.setBackgroundColor(col(bg));screen.write(string.rep(" ",w)) end
    function P.text(x,y,s,fg,bg)
        if x<1 or x>w or y<1 or y>h then return end
        s=tostring(s):sub(1,w-x+1)
        screen.setCursorPos(x,y);screen.setTextColor(col(fg or colors.white));screen.setBackgroundColor(col(bg or colors.black))
        screen.write(s)
    end
    function P.right(y,s,fg,bg,margin) s=tostring(s);P.text(math.max(1,w-#s+1-(margin or 0)),y,s,fg,bg) end
    function P.bar(x,y,width,pc,fg)
        local f=math.floor(width*math.max(0,math.min(1,pc))+0.5)
        P.text(x,y,string.rep(" ",f),colors.white,fg or colors.lime)
        P.text(x+f,y,string.rep(" ",width-f),colors.white,TRACK)
    end
    function P.thin(x,y,width,pc,fg) thinBar(P.text,x,y,width,pc,fg) end
    return P
end
-- ===== Infoscreen: nur Anzeige, keine Knoepfe =====
-- st = Zustandstabelle des Infoscreens (Seite, Verlauf fuer "pro Stunde")
-- Infoscreen fuer genau eine Turtle: grosse Detailseite
local function drawTurtleInfo(screen,fleet,link,st,id)
    local P=painter(screen);local w,h=P.w,P.h
    screen.setBackgroundColor(colors.black);screen.clear()
    local e=(fleet.entries or {})[id]
    local d=e and e.data or {}
    local label,kind=M.state(e,link)
    local name=e and e.label~="" and e.label or ("Turtle #"..id)
    P.fill(1,colors.blue)
    P.text(2,1,name,colors.white,colors.blue)
    P.right(1,(e and (e.job=="farm" and "Farm" or "Mine") or "").." #"..id.." ",colors.white,colors.blue)
    if not e then
        P.text(1,3,"Turtle #"..id.." ist der Zentrale",colors.orange)
        P.text(1,4,"(noch) nicht bekannt.",colors.orange)
        P.text(1,6,"ID in toast.lua config pruefen.",colors.lightGray)
        return
    end
    -- Zustand als grosses Band
    P.fill(3,COLOR[kind]);P.fill(4,COLOR[kind])
    P.text(2,3,label,colors.black,COLOR[kind])
    local why=(kind=="fault" or kind=="warn") and (d.fault or d.status) or nil
    if why then P.text(2,4,tostring(why),colors.black,COLOR[kind]) end
    local det=kind=="off" and "Keine Daten - offline oder Chunk entladen" or tostring(d.detail or "")
    local y=6
    while #det>0 and y<=7 do P.text(1,y,det:sub(1,w),colors.lightGray);det=det:sub(w+1);y=y+1 end
    -- Fortschritt
    y=9
    local pc=math.max(0,math.min(1,num(d.scanned)/math.max(1,num(d.cells))))
    P.text(1,y,"Fortschritt",colors.lightGray);P.right(y,math.floor(pc*100+0.5).."%",colors.white)
    y=y+1;P.bar(1,y,w,pc,kind=="off" and colors.gray or COLOR[kind])
    if h>=20 then y=y+1;P.bar(1,y,w,pc,kind=="off" and colors.gray or COLOR[kind]) end
    y=y+2
    -- pro Stunde fuer diese Turtle
    st.hist=st.hist or {}
    local now=os.clock();local key=e.job=="farm" and num(d.total) or num(d.harvested)
    local last=st.hist[#st.hist]
    if not last or now-last.t>=30 then st.hist[#st.hist+1]={t=now,v=key};while #st.hist>31 do table.remove(st.hist,1) end end
    local first=st.hist[1]
    local perH=(first and now-first.t>=60) and short(math.max(0,(key-first.v)/(now-first.t)*3600)) or "-"
    local rows
    if e.job=="farm" then
        rows={{"Runden",short(d.rounds)},{"Diese Runde",short(d.roundYield).." Items"},{"Geerntet",short(d.harvested).." Pflanzen"},
            {"Ertrag",short(d.total).." Items"},{"Ertrag / Stunde",perH},{"Saatgut",short(d.seeds)}}
        if num(d.wait)>0 then rows[#rows+1]={"Naechste Runde","in "..num(d.wait).." s"} end
    else
        rows={{"Gaenge fertig",short(d.rounds)..(d.tunnels and (" / "..d.tunnels) or "")},{"Abgebaut",short(d.harvested).." Bloecke"},
            {"Abgebaut / Stunde",perH},{"Abgeladen",short(d.total).." Items"},{"Freie Slots",short(d.freeSlots)}}
        if d.useCoal then rows[#rows+1]={"Kohle verbrannt",short(d.coal).."  (+"..short(num(d.coal)*80).." Fuel)"} end
    end
    rows[#rows+1]={"Fuel",d.fuel=="unlimited" and "unbegrenzt" or short(d.fuel)}
    if d.chunks then rows[#rows+1]={"Chunks",d.chunks>0 and (d.chunks.."  (-"..short(d.chunkFuel).." Fuel/h)") or "aus"} end
    -- zweispaltig, wenn breit genug
    local cols=w>=56 and 2 or 1
    local cw=math.floor(w/cols)
    local per=math.ceil(#rows/cols)
    for i,r in ipairs(rows) do
        local c=math.floor((i-1)/per);local yy=y+(i-1)%per
        if yy<=h then
            local x=1+c*cw
            P.text(x,yy,r[1],colors.lightGray)
            P.text(x+cw-1-#r[2]-(cols>1 and c==0 and 2 or 0),yy,r[2],colors.white)
        end
    end
end
-- show: "all", "farm", "mining" oder Turtle-ID (Zahl)
function M.drawInfo(screen,fleet,link,st,show)
    if type(show)=="number" then return drawTurtleInfo(screen,fleet,link,st,show) end
    local P=painter(screen);local w,h=P.w,P.h
    screen.setBackgroundColor(colors.black);screen.clear()
    local entries=fleet.entries or {}
    if show=="farm" or show=="mining" then
        local ids={}
        for _,id in ipairs(fleet.ids or {}) do if (entries[id] or {}).job==show then ids[#ids+1]=id end end
        fleet={ids=ids,entries=entries}
    end
    local count,act={farm=0,mining=0},{farm=0,mining=0}
    local farmTotal,farmHarv,mineHarv,mineTotal,fuel,chunk,progSum,progN=0,0,0,0,0,0,0,0
    local problems,list={},{}
    for _,id in ipairs(fleet.ids or {}) do
        local e=entries[id] or {};local d=e.data or {}
        local job=e.job=="farm" and "farm" or "mining"
        local label,kind=M.state(e,link)
        count[job]=count[job]+1
        if kind=="work" or kind=="move" or kind=="wait" then act[job]=act[job]+1 end
        if job=="farm" then farmTotal=farmTotal+num(d.total);farmHarv=farmHarv+num(d.harvested)
        else mineHarv=mineHarv+num(d.harvested);mineTotal=mineTotal+num(d.total)
            if num(d.cells)>0 then progSum=progSum+num(d.scanned)/num(d.cells);progN=progN+1 end end
        if kind~="off" then
            if d.fuel~="unlimited" then fuel=fuel+num(d.fuel) end
            if num(d.chunks)>0 then chunk=chunk+num(d.chunkFuel) end
        end
        if kind=="fault" or kind=="warn" then problems[#problems+1]={id=id,e=e,label=label,kind=kind} end
        list[#list+1]={id=id,e=e,label=label,kind=kind,job=job}
    end
    -- Verlauf fuer "pro Stunde" (alle 30 s ein Messpunkt, 15 min behalten)
    st.hist=st.hist or {}
    local now=os.clock()
    local last=st.hist[#st.hist]
    if not last or now-last.t>=30 then
        st.hist[#st.hist+1]={t=now,farm=farmTotal,mine=mineHarv}
        while #st.hist>31 do table.remove(st.hist,1) end
    end
    local function rate(key,cur)
        local first=st.hist[1]
        if not first or now-first.t<60 then return "-" end
        return short(math.max(0,(cur-first[key])/(now-first.t)*3600))
    end
    -- Kopf
    P.fill(1,colors.blue)
    local online=0;for _,l in ipairs(list) do if l.kind~="off" then online=online+1 end end
    local clock=""
    if textutils and textutils.formatTime and os.time then
        local ok,t=pcall(function() return textutils.formatTime(os.time(),true) end);if ok then clock=t end
    end
    local rt=link and (online.."/"..#list.." online"..(clock~="" and ("  "..clock) or "").." ") or "keine Verbindung "
    local title=show=="farm" and "Farmen" or show=="mining" and "Minen" or "Uebersicht"
    P.text(2,1,(#rt+10+#title<=w) and ("TOAST  "..title) or "TOAST",colors.white,colors.blue)
    P.right(1,rt,link and colors.white or colors.orange,colors.blue)
    -- Gruppen-Kacheln (nebeneinander, wenn Platz)
    local y=3
    local function panel(x,y0,pw,title,a,n,rows)
        if n==0 then return y0 end
        P.text(x,y0,title,colors.white)
        local s=a.."/"..n.." aktiv"
        P.text(x+pw-#s,y0,s,a>0 and colors.lime or colors.lightGray)
        local yy=y0+1
        for _,r in ipairs(rows) do
            P.text(x,yy,r[1],colors.lightGray)
            P.text(x+pw-#r[2],yy,r[2],colors.white)
            if r.bar then
                -- gruener Balken zwischen Bezeichnung und Prozent
                local bx=x+#r[1]+1;local bw=pw-#r[1]-#r[2]-2
                if bw>=3 then P.thin(bx,yy,bw,r.bar,colors.lime) end
            end
            yy=yy+1
        end
        return yy
    end
    local side=w>=50 and count.farm>0 and count.mining>0
    -- Kleiner Bildschirm: nur die wichtigsten Zeilen, damit die Liste Platz hat
    local compact=not side and h<26 and count.farm>0 and count.mining>0
    local prog=(progN>0 and math.floor(progSum/progN*100+0.5) or 0).."%"
    local farmRows,mineRows
    if compact then
        farmRows={{"Ertrag",short(farmTotal).."  ("..rate("farm",farmTotal).."/h)"}}
        mineRows={{"Abgebaut",short(mineHarv).."  ("..rate("mine",mineHarv).."/h)"},{"Fortschritt",prog,bar=progN>0 and progSum/progN or 0}}
    else
        farmRows={{"Ertrag",short(farmTotal).." Items"},{"pro Stunde",rate("farm",farmTotal)},{"Geerntet",short(farmHarv).." Pfl."}}
        mineRows={{"Abgebaut",short(mineHarv).." Bl."},{"pro Stunde",rate("mine",mineHarv)},
            {"Abgeladen",short(mineTotal).." Items"},{"Fortschritt",prog,bar=progN>0 and progSum/progN or 0}}
    end
    if side then
        local pw=math.floor((w-3)/2)
        local y1=panel(1,y,pw,"FARM",act.farm,count.farm,farmRows)
        local y2=panel(pw+4,y,w-pw-3,"MINE",act.mining,count.mining,mineRows)
        y=math.max(y1,y2)+1
    else
        local gap=compact and 0 or 1
        local y1=panel(1,y,w,"FARM",act.farm,count.farm,farmRows)
        if count.farm>0 then y=y1+gap end
        local y2=panel(1,y,w,"MINE",act.mining,count.mining,mineRows)
        if count.mining>0 then y=y2+1 end
    end
    if #list==0 then
        P.text(1,y,"Noch keine Turtles gemeldet.",colors.lightGray)
        return
    end
    -- Probleme zuerst
    if #problems>0 and y<h-1 then
        local maxP=math.max(1,math.floor((h-y-2)/2))   -- Platz fuer die Liste lassen
        P.text(1,y,"PROBLEME",colors.orange);y=y+1
        for n,p in ipairs(problems) do
            if y>=h-1 or n>maxP then break end
            local d=p.e.data or {}
            local name=p.e.label~="" and p.e.label or ("#"..p.id)
            P.text(1,y,"\7",COLOR[p.kind]);P.text(3,y,name,colors.white)
            local msg=tostring(d.fault or d.status or p.label)
            P.text(math.min(w,4+#name),y,(" "..msg):sub(1,math.max(0,w-3-#name)),COLOR[p.kind])
            y=y+1
        end
        if not compact then y=y+1 end
    end
    -- Alle Turtles (blaettert automatisch)
    local footer=h
    local avail=footer-1-y
    if avail>=2 then
        P.text(1,y,"TURTLES",colors.white);y=y+1;avail=avail-1
        local pages=math.max(1,math.ceil(#list/math.max(1,avail)))
        st.page=st.page or 1
        if not st.flip then st.flip=now
        elseif now-st.flip>=6 then st.page=st.page%pages+1;st.flip=now end
        if st.page>pages then st.page=1 end
        if pages>1 then P.right(y-1,st.page.."/"..pages,colors.lightGray) end
        local barW=w>=60 and 20 or w>=40 and math.min(14,w-30) or w>=30 and 6 or 0
        for i=1,avail do
            local l=list[(st.page-1)*avail+i];if not l then break end
            local d=l.e.data or {}
            local name=l.e.label~="" and l.e.label or ((l.job=="farm" and "Farm" or "Mine").." #"..l.id)
            P.text(1,y,"\7",COLOR[l.kind])
            local stx=w-8
            local val=""
            if l.kind~="off" then val=l.job=="farm" and short(d.total) or short(d.harvested) end
            if barW>0 then
                -- [Zustand] [gruener Balken] [Prozent] [Wert]
                local valW=w>=40 and 6 or 0
                local bx=w-valW-5-barW+1
                stx=bx-9
                if l.kind~="off" then
                    local pc=math.max(0,math.min(1,num(d.scanned)/math.max(1,num(d.cells))))
                    P.thin(bx,y,barW,pc,colors.lime)
                    P.text(bx+barW,y,string.format("%4d%%",math.floor(pc*100+0.5)),colors.lightGray)
                end
                if valW>0 then P.right(y,val,colors.lightGray) end
                P.text(stx,y,l.label,COLOR[l.kind])
            else
                P.text(stx,y,l.label,COLOR[l.kind])
            end
            P.text(3,y,name:sub(1,math.max(1,stx-4)),l.kind=="off" and colors.gray or colors.white)
            y=y+1
        end
    end
    -- Fusszeile
    P.text(1,footer,("Fuel "..short(fuel)..(chunk>0 and ("  Chunks -"..short(chunk).."/h") or "")):sub(1,w),colors.lightGray)
end
function M.new(screen,cfg)
    -- kbd: Tastatur-Bedienung sichtbar (Markierung + Tastenhinweise).
    -- Auf dem eigenen Bildschirm (Pocket/Computer) immer, am Monitor sobald
    -- eine Taste gedrueckt wurde.
    local ui={filter="all",selected=nil,page=1,buttons={},ids={},cursor=nil,kbd=screen==term,help=false}
    function ui.setScreen(s) screen=s;ui.kbd=ui.kbd or s==term end
    local CONFIRM=5
    local function confirming() return ui.confirm and os.clock()-ui.confirm.at<CONFIRM and ui.confirm end
    function ui.draw(fleet,link,notice)
        local w,h=screen.getSize();ui.buttons={}
        local color=screen.isColor and screen.isColor()
        setTrack(screen)
        -- Ohne Farbbildschirm nur Grautoene verwenden
        local function col(c)
            if color then return c end
            if c==TRACK then return colors.gray end
        if c==colors.black or c==colors.gray or c==colors.lightGray or c==colors.white then return c end
            return colors.white
        end
        local function fill(y,bg) screen.setCursorPos(1,y);screen.setBackgroundColor(col(bg));screen.write(string.rep(" ",w)) end
        local function text(x,y,s,fg,bg)
            if x<1 or x>w or y<1 or y>h then return end
            s=tostring(s):sub(1,w-x+1)
            screen.setCursorPos(x,y);screen.setTextColor(col(fg or colors.white));screen.setBackgroundColor(col(bg or colors.black))
            screen.write(s)
        end
        local function right(y,s,fg,bg) s=tostring(s);text(math.max(1,w-#s+1),y,s,fg,bg) end
        local function button(x,y,width,label,action,bg,enabled)
            if width<1 then return end
            local b=enabled and bg or colors.gray
            local l=tostring(label):sub(1,width)
            local pad=math.floor((width-#l)/2)
            text(x,y,string.rep(" ",width),colors.white,b)
            text(x+pad,y,l,enabled and colors.white or colors.lightGray,b)
            ui.buttons[#ui.buttons+1]={x=x,y=y,w=width,action=action,enabled=enabled}
        end
        screen.setBackgroundColor(colors.black);screen.setTextColor(colors.white);screen.clear()
        if not confirming() then ui.confirm=nil end
        if ui.help then
            fill(1,colors.blue);text(2,1,"TOAST - Tasten",colors.white,colors.blue)
            local L={{"\24 \25","Turtle waehlen"},{"Enter","Details oeffnen"},{"\27 Back","zurueck"},
                {"\27 \26 Tab","Reiter wechseln"},{"S","Start"},{"X","Stop"},{"E","1 Runde / 1 Gang"},
                {"R",w>=30 and "Reset (2x druecken)" or "Reset (2x)"},{"Bild\24\25","Seite blaettern"},{"H / ?","diese Hilfe"},{"Q","beenden"}}
            local kw=w>=34 and 11 or 9
            for i,l in ipairs(L) do
                if i+2>h-1 then break end
                text(2,i+2,l[1],colors.yellow);text(2+kw,i+2,l[2],colors.white)
            end
            text(1,h,("Taste druecken = weiter"):sub(1,w),colors.lightGray)
            ui.buttons={{x=1,y=1,w=w,action="help",enabled=true}}
            for y=2,h do ui.buttons[#ui.buttons+1]={x=1,y=y,w=w,action="help",enabled=true} end
            return
        end
        if w<24 or h<12 then
            text(1,1,"TOAST",colors.cyan);text(1,3,"Bildschirm zu klein",colors.orange)
            text(1,4,"mind. 24 x 12 Zeichen");text(1,5,"(Monitor groesser oder");text(1,6," Schrift kleiner)");return
        end
        local entries=fleet.entries or {}
        -- Zaehlen + Gruppenwerte
        local ids,count={},{farm=0,mining=0}
        local g={farm={on=0,act=0,total=0,harv=0},mining={on=0,act=0,total=0,harv=0}}
        local online,faults,chunkFuel=0,0,0
        for _,id in ipairs(fleet.ids or {}) do
            local e=entries[id] or {};local d=e.data or {}
            local job=e.job=="farm" and "farm" or "mining"
            count[job]=count[job]+1
            local _,kind=M.state(e,link)
            local gg=g[job]
            gg.total=gg.total+num(d.total);gg.harv=gg.harv+num(d.harvested)
            if kind~="off" then gg.on=gg.on+1 end
            if kind=="work" or kind=="move" or kind=="wait" then gg.act=gg.act+1 end
            if ui.filter=="all" or e.job==ui.filter then
                ids[#ids+1]=id
                if kind~="off" then online=online+1 end
                if kind=="fault" or kind=="warn" then faults=faults+1 end
                if kind~="off" and num(d.chunks)>0 then chunkFuel=chunkFuel+num(d.chunkFuel) end
            end
        end
        -- Probleme zuerst, dann aktive, dann der Rest (sonst stabile Reihenfolge)
        local rank,pos={fault=1,warn=2,work=3,move=3,wait=3,done=4,idle=4,off=5},{}
        for i,id in ipairs(ids) do local _,k=M.state(entries[id] or {},link);pos[id]=(rank[k] or 4)*10000+i end
        table.sort(ids,function(a,b) return pos[a]<pos[b] end)
        ui.ids=ids
        if ui.selected and not common.contains(ids,ui.selected) then ui.selected=nil end
        if ui.cursor and not common.contains(ids,ui.cursor) then ui.cursor=nil end
        if not ui.cursor then ui.cursor=ui.selected or ids[1] end
        -- Kopfzeile
        fill(1,colors.blue)
        text(2,1,"TOAST",colors.white,colors.blue)
        if link then right(1,online.."/"..#ids.." online ",colors.white,colors.blue)
        else right(1,"keine Verbindung ",colors.orange,colors.blue) end
        -- Reiter
        local tabs={{"Alle "..(count.farm+count.mining),"all"},{"Farm "..count.farm,"farm"},{"Mine "..count.mining,"mining"}}
        local third=math.floor(w/3)
        for i,t in ipairs(tabs) do
            local active=ui.filter==t[2]
            button(1+(i-1)*third,2,i==3 and w-2*third or third,t[1],"filter:"..t[2],active and colors.lightBlue or colors.gray,true)
        end
        -- Fusszeile: Hinweis + 2 Tastenreihen
        local foot=h-2
        local sel=ui.selected and entries[ui.selected]
        local job=sel and sel.job or (ui.filter~="all" and ui.filter) or nil
        local once=job=="farm" and "1 Runde" or job=="mining" and "1 Gang" or "1x"
        local canStart=false
        for _,id in ipairs(ids) do
            local e=entries[id]
            if link and (not ui.selected or ui.selected==id) and e and e.online and e.data and not e.data.recovery then canStart=true end
        end
        for i,b in ipairs({{"START","start",colors.green},{"STOP","stop",colors.red},{once,"once",colors.blue}}) do
            button(1+(i-1)*third,foot+1,i==3 and w-2*third or third,b[1],b[2],b[3],b[2]=="stop" and link or canStart)
        end
        local perPage
        -- ===== Detailansicht =====
        if sel then
            local d=sel.data or {}
            local label,kind=M.state(sel,link)
            local name=(sel.label and sel.label~="" and sel.label or (sel.job=="farm" and "Farm" or "Mine")).." #"..ui.selected
            button(1,3,w,"< "..name,"group",colors.gray,true)
            fill(4,COLOR[kind])
            local why=(kind=="fault" or kind=="warn") and (d.fault or d.status) or nil
            text(2,4,label..(why and (": "..tostring(why)) or ""),colors.black,COLOR[kind])
            -- Detailtext umbrechen (max. 2 Zeilen)
            local det=kind=="off" and "Keine Daten - Turtle offline oder Chunk entladen" or tostring(d.detail or "")
            local y=5
            while #det>0 and y<=6 do text(1,y,det:sub(1,w),colors.lightGray);det=det:sub(w+1);y=y+1 end
            y=7
            -- Fortschrittsbalken
            local pc=math.max(0,math.min(1,num(d.scanned)/math.max(1,num(d.cells))))
            local barW=math.max(4,w-6)
            local fillW=math.floor(barW*pc+0.5)
            text(1,y,string.rep(" ",fillW),colors.white,colors.lime)
            text(1+fillW,y,string.rep(" ",barW-fillW),colors.white,TRACK)
            right(y,math.floor(pc*100+0.5).."%",colors.white)
            y=y+2
            local rows={}
            if sel.job=="farm" then
                rows={{"Runden",short(d.rounds)},{"Geerntet",short(d.harvested).." Pflanzen"},
                    {"Ertrag",short(d.total).." Items"},{"Saatgut",short(d.seeds)}}
                if num(d.roundYield)>0 then table.insert(rows,3,{"Diese Runde",short(d.roundYield).." Items"}) end
            else
                rows={{"Gaenge",short(d.rounds).." fertig"},{"Abgebaut",short(d.harvested).." Bloecke"},
                    {"Abgeladen",short(d.total).." Items"},{"Freie Slots",short(d.freeSlots)}}
                if d.useCoal then rows[#rows+1]={"Kohle -> Fuel",short(d.coal).." Stueck"} end
            end
            rows[#rows+1]={"Fuel",d.fuel=="unlimited" and "unbegrenzt" or short(d.fuel)}
            if d.chunks then rows[#rows+1]={"Chunks",d.chunks>0 and (d.chunks..", -"..short(d.chunkFuel).."/h") or "aus"} end
            for _,r in ipairs(rows) do
                if y>=foot-1 then break end
                text(1,y,r[1],colors.lightGray);text(13,y,r[2],colors.white);y=y+1
            end
        else
        -- ===== Uebersicht =====
            local y=3
            local function group(jobName,title,valLabel,val)
                local gg=g[jobName]
                if count[jobName]==0 then return end
                text(1,y,title,colors.white)
                text(6,y,gg.act.."/"..count[jobName]..(w>=34 and " aktiv" or ""),gg.act>0 and colors.lime or colors.lightGray)
                right(y,valLabel.." "..short(val),colors.lightGray)
                y=y+1
            end
            if ui.filter~="mining" then group("farm","Farm","Ertrag",g.farm.total) end
            if ui.filter~="farm" then group("mining","Mine","Abgebaut",g.mining.harv) end
            local pl=faults>0 and ("! "..faults.." Problem"..(faults>1 and "e" or "")) or ""
            local cl=chunkFuel>0 and ("Chunks -"..short(chunkFuel).."/h") or ""
            if #pl+#cl+1>w then
                text(1,y,pl,colors.orange);y=y+1;right(y,cl,colors.lightGray);y=y+1
            elseif #pl+#cl>0 then
                text(1,y,pl,colors.orange);right(y,cl,colors.lightGray);y=y+1
            end
            if #ids==0 then
                text(1,y+1,"Keine Turtles.",colors.lightGray)
                text(1,y+2,"Turtles melden sich",colors.lightGray)
                text(1,y+3,"automatisch, sobald sie",colors.lightGray)
                text(1,y+4,"laufen.",colors.lightGray)
            end
            -- Liste
            local top=y
            local avail=math.max(1,foot-1-top)
            perPage=cfg.display.pageSize>0 and math.min(avail,cfg.display.pageSize) or avail
            local pages=math.max(1,math.ceil(#ids/perPage));ui.pages=pages;ui.page=math.min(ui.page,pages)
            local wide=w>=44
            ui.perPage=perPage
            -- Seite folgt der Tastatur-Markierung
            if ui.kbd and ui.cursor and ui.followCursor then
                for i,id in ipairs(ids) do if id==ui.cursor then ui.page=math.ceil(i/perPage) end end
                ui.followCursor=false
            end
            for row=1,perPage do
                local id=ids[(ui.page-1)*perPage+row];if not id then break end
                local e=entries[id] or {};local d=e.data or {}
                local label,kind=M.state(e,link)
                local yy=top+row-1
                local name=e.label and e.label~="" and e.label or ((e.job=="farm" and "Farm" or "Mine").." #"..id)
                local stW=8
                -- Rechts: [gruener Balken] [Prozent] [Wert] [Zustand]
                local barW=w>=70 and 20 or w>=44 and 10 or w>=34 and 6 or 0
                local value=wide and string.format("  %-8s%6s",e.job=="farm" and "Ertrag" or "Abgebaut",e.job=="farm" and short(d.total) or short(d.harvested)) or ""
                local block=barW>0 and (barW+5+#value) or 0      -- Balken + " 100%" + Wert
                local nameW=w-2-stW-1-(block>0 and block+1 or 0)
                local mark=ui.kbd and id==ui.cursor
                local bg=mark and colors.gray or colors.black
                local sc=(mark and kind=="off") and colors.lightGray or COLOR[kind]
                text(1,yy,string.rep(" ",w),colors.white,bg)
                text(1,yy,mark and "\16" or "\7",mark and colors.white or sc,bg)
                text(3,yy,name:sub(1,nameW),kind=="off" and (mark and colors.lightGray or colors.gray) or colors.white,bg)
                if block>0 and kind~="off" then
                    local pc=math.max(0,math.min(1,num(d.scanned)/math.max(1,num(d.cells))))
                    local x0=w-stW-block
                    thinBar(text,x0,yy,barW,pc,colors.lime,bg)
                    text(x0+barW,yy,string.format("%4d%%",math.floor(pc*100+0.5)),mark and colors.white or colors.lightGray,bg)
                    if #value>0 then text(x0+barW+5,yy,value,mark and colors.white or colors.lightGray,bg) end
                end
                right(yy,string.format("%-8s",label),sc,bg)
                ui.buttons[#ui.buttons+1]={x=1,y=yy,w=w,action="id:"..id,enabled=true}
            end
        end
        -- Hinweiszeile + untere Tastenreihe
        local info=tostring(notice or "")
        local infoCol=colors.lightGray
        local goal=sel and "diese Turtle" or (ui.filter=="all" and "alle" or ui.filter=="farm" and "alle Farmen" or "alle Minen")
        if confirming() then
            info=#goal+24<=w and ("Reset fuer "..goal.."? Nochmal = ja") or "Reset? Nochmal = ja";infoCol=colors.orange
        elseif info=="" or info:find("bestaetigt",1,true) then
            info="Ziel: "..goal
            local tip
            if ui.kbd then
                tip=sel and (w>=40 and "\24\25 Turtle  \27 zurueck  H Hilfe" or "\27 zurueck  H Hilfe")
                    or (w>=40 and "\24\25 Wahl  Enter Details  H Hilfe" or "\24\25 Enter  H Hilfe")
            else tip=not sel and "Tippen = Details" or nil end
            if tip and #info+2+#tip<=w then info=info..string.rep(" ",w-#info-#tip)..tip
            elseif tip and #tip<=w and ui.kbd then info=tip end
        end
        text(1,foot,info:sub(1,w),infoCol)
        local pages=ui.pages or 1
        local sure=confirming()
        local rbg=sure and colors.red or colors.orange
        if not sel and pages>1 then
            button(1,foot+2,third,"<","pageprev",colors.gray,ui.page>1)
            button(1+third,foot+2,third,sure and "SICHER?" or "RESET","reset",rbg,link and #ids>0)
            button(1+2*third,foot+2,w-2*third,ui.page.."/"..pages.." >","pagenext",colors.gray,ui.page<pages)
        else
            local long=sure and "SICHER? nochmal = RESET" or "RESET  (Fehler loeschen + heim)"
            button(1,foot+2,w,w>=38 and long or (sure and "SICHER?" or "RESET"),"reset",rbg,link and #ids>0)
        end
    end
    local TABS={"all","farm","mining"}
    local function indexOf(id) for i,v in ipairs(ui.ids) do if v==id then return i end end return 0 end
    function ui.action(a)
        if not a then return end
        if a~="reset" then ui.confirm=nil end
        if a=="redraw" then return
        elseif a=="help" then ui.help=not ui.help
        elseif a:match("^filter:") then ui.filter=a:sub(8);ui.selected=nil;ui.page=1;ui.cursor=nil
        elseif a:match("^id:") then ui.selected=tonumber(a:sub(4));ui.cursor=ui.selected
        elseif a=="group" then ui.cursor=ui.selected or ui.cursor;ui.selected=nil;ui.followCursor=true
        elseif a=="pageprev" then ui.page=math.max(1,ui.page-1)
        elseif a=="pagenext" then ui.page=math.min(ui.pages or 1,ui.page+1)
        elseif a=="tabprev" or a=="tabnext" then
            local i=1;for k,t in ipairs(TABS) do if t==ui.filter then i=k end end
            i=(i-1+(a=="tabnext" and 1 or -1))%#TABS+1
            return ui.action("filter:"..TABS[i])
        elseif a=="up" or a=="down" then
            if #ui.ids==0 then return end
            local i=indexOf(ui.selected or ui.cursor)
            if i==0 then i=a=="down" and 1 or #ui.ids else i=math.max(1,math.min(#ui.ids,i+(a=="down" and 1 or -1))) end
            ui.cursor=ui.ids[i];ui.followCursor=true
            if ui.selected then ui.selected=ui.cursor end
        elseif a=="first" or a=="last" then
            if #ui.ids==0 then return end
            ui.cursor=ui.ids[a=="first" and 1 or #ui.ids];ui.followCursor=true
            if ui.selected then ui.selected=ui.cursor end
        elseif a=="open" then
            if not ui.selected and ui.cursor and indexOf(ui.cursor)>0 then ui.selected=ui.cursor end
        elseif a=="next" or a=="prev" then
            local index=indexOf(ui.selected)
            index=(index+(a=="next" and 1 or -1))%(#ui.ids+1)
            ui.selected=ui.ids[index];if ui.selected then ui.cursor=ui.selected end
        elseif a=="reset" then
            -- Sicherheitsabfrage: zweimal innerhalb von 5 s druecken/tippen
            if confirming() then ui.confirm=nil;return "reset" end
            ui.confirm={at=os.clock()};return
        else return a end
    end
    -- Tastatur: Sondertasten (Name aus keys.getName) und Zeichen
    local KEYS={up="up",down="down",enter="open",numPadEnter="open",space="open",backspace="group",
        tab="tabnext",pageUp="pageprev",pageDown="pagenext",home="first",["end"]="last"}
    function ui.key(name)
        if not name then return end
        ui.kbd=true
        if ui.help then ui.help=false;return "redraw" end
        if name=="left" then return ui.selected and "group" or "tabprev" end
        if name=="right" then return ui.selected and nil or "tabnext" end
        local a=KEYS[name]
        if ui.selected and (a=="pageprev" or a=="pagenext") then return a=="pageprev" and "up" or "down" end
        return a
    end
    function ui.char(ch)
        if not ch then return end
        ui.kbd=true
        if ui.help then ui.help=false;return "redraw" end
        return ui.keys[ch:lower()] or ui.keys[ch]
    end
    function ui.target() return ui.selected or ui.filter end
    function ui.click(x,y)
        for i=#ui.buttons,1,-1 do
            local b=ui.buttons[i]
            if b.enabled and y==b.y and x>=b.x and x<b.x+b.w then return b.action end
        end
    end
    ui.keys={["0"]="group",["1"]="start",["2"]="stop",["3"]="once",["4"]="reset",
        s="start",x="stop",e="once",r="reset",h="help",["?"]="help",
        a="filter:all",f="filter:farm",m="filter:mining"}
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
            if (a=="q" or a=="Q") and not ui.help then return end
            action(ui.char(a))
        elseif e=="key" then action(ui.key(keys.getName(a)))
        elseif e=="mouse_scroll" then action(a>0 and "down" or "up") end
    end
end
local ok,why=pcall(loop)
pcall(function() dofile("/toast/toast_ui.lua").resetTrack(term) end)
term.setBackgroundColor(colors.black);term.setTextColor(colors.white);term.clear();term.setCursorPos(1,1)
if not ok and why~="Terminated" then error(why,0) end
print("Pocket geschlossen. Farmen und Minen laufen weiter.")
]======]
FILES["toast_info.lua"]=[======[
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
local function poll()
    common.refreshModems()
    pcall(rednet.send,cfg.controllerId,{kind="hello",role="info",version=1,controllerId=cfg.controllerId},common.remoteProtocol)
end
local function draw()
    for _,s in ipairs(screens) do
        local ok,why=pcall(UI.drawInfo,s.dev,fleet,connected(),s.st,cfg.show)
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
for _,s in ipairs(screens) do pcall(function() s.dev.setBackgroundColor(colors.black);s.dev.clear();UI.resetTrack(s.dev) end) end
term.setBackgroundColor(colors.black);term.clear();term.setCursorPos(1,1)
if not ok and why~="Terminated" then error(why,0) end
print("Infoscreen beendet.")
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
local TOOLS = { ["minecraft:diamond_pickaxe"] = true, ["minecraft:netherite_pickaxe"] = true,
    ["minecraft:diamond_hoe"] = true, ["minecraft:netherite_hoe"] = true }
local NO_TOOL = "Kein Werkzeug: Diamant-Spitzhacke oder -Hacke in die Turtle legen"
local CONTAINERS = { ["minecraft:chest"] = true,
    ["minecraft:trapped_chest"] = true, ["minecraft:barrel"] = true }
local args = { ... }
assert(turtle, "Dieses Programm gehoert auf eine Mining Turtle.")
assert(CROPS[CFG.crop], "Unbekannte Pflanzenart in CFG.crop.")
for _, n in ipairs({ CFG.width, CFG.length }) do
    assert(type(n) == "number" and n >= 1 and n <= 32 and n % 1 == 0,
        "Feldmasse muessen ganze Zahlen zwischen 1 und 32 sein.")
end
assert(CFG.interval >= 1 and CFG.seedReserve >= 0 and CFG.seedReserve <= 256,
    "Ungueltige Wartezeit oder Saatgutreserve.")
local crop = CROPS[CFG.crop]
assert(CFG.side == nil or CFG.side == "right" or CFG.side == "left", "farm.side: right oder left.")
local MIRROR = CFG.side == "left"
CFG.water = CFG.water or {}
-- Saatgut aus der Ernte wird behalten und wieder gepflanzt.
-- seedReserve = 0 (Standard): automatisch so viel, wie das Feld Pflanzstellen hat
-- (mind. 16, max. 3 Stapel). Die Saatgutkiste hinten wird dann nur noch gebraucht,
-- wenn die Turtle gar kein Saatgut mehr hat.
local RESERVE = CFG.seedReserve
if RESERVE == 0 then
    RESERVE = math.max(16, math.min(192, CFG.width * CFG.length - #CFG.water))
end
-- CCChunkloader: Chunkloader bleibt angebaut, Werkzeug <-> Modem werden getauscht.
local TC = dofile("/toast_common.lua")
local CL = TC.chunkConfig(config.chunkload)
local GEAR
if CL.enabled then
    local why
    GEAR, why = TC.gear(CL, TOOLS)
    assert(GEAR, why)
    assert(GEAR.radio(), "Chunkloader: Funk-/Endermodem ins Turtle-Inventar legen.")
end
local drainPerSec = CL.enabled and TC.chunkCostPerTick(CL.radius) * 20 or 0
local budget = CFG.width * CFG.length + CFG.width + CFG.length + 20
    + math.ceil(drainPerSec * (CFG.width * CFG.length * 1.5 + CFG.interval + 90))

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
local function clearPending() st.pending, st.after, st.pendingFuel, st.pendingDrain = nil, nil, nil, nil end
-- Unterbrochene Bewegung ueber den Fuelstand aufloesen.
local function resolvePending()
    if not st.pending then return true end
    local fuel = turtle.getFuelLevel()
    if st.pending ~= "turn" and type(fuel) == "number" and type(st.pendingFuel) == "number"
        and type(st.after) == "table" then
        if fuel == st.pendingFuel then clearPending(); save(); return true end
        -- Chunkloader zieht nebenbei Fuel ab: dann ist "1 weniger" nicht eindeutig.
        if st.pendingDrain then return false end
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
local layout = CFG.width .. ":" .. CFG.length .. ":" .. CFG.crop .. (MIRROR and ":L" or "")
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
    for _, w in ipairs({ "Geschuetzt", "Position unklar" }) do
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
local function equipTool()
    if GEAR then return GEAR.tool() end
    for i = 1, 16 do
        local it = turtle.getItemDetail(i)
        if it and TOOLS[it.name] then
            turtle.select(i)
            for _, side in ipairs({ "left", "right" }) do
                if peripheral.getType(side) ~= "modem" then
                    local fn = side == "left" and turtle.equipLeft or turtle.equipRight
                    if fn() then return true end
                end
            end
        end
    end
    return false
end
local function isHome() return st.x == 0 and st.z == 0 end
local function active()
    -- radioTimeout = 0: auch ohne Zentrale weiterarbeiten.
    if run.mode ~= "off" and CFG.radioTimeout > 0 and os.clock() - run.lastContact > CFG.radioTimeout then
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
    st.pendingDrain = GEAR ~= nil and GEAR.radius > 0 or nil
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
        -- side="left": Feld liegt links -> alle Drehungen gespiegelt.
        local ok, why = action("turn", (left ~= MIRROR) and turtle.turnLeft or turtle.turnRight,
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
-- Chunks nur laden, solange die Turtle unterwegs ist / arbeitet / auf neuen Versuch wartet.
local function chunkTick()
    if not GEAR then return end
    local need = run.mode ~= "off" or not isHome() or (run.fault ~= nil and run.retryAt ~= nil) or CL.idle
    GEAR.set(need and CL.radius or 0)
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
        chunkTick()
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
    local keep = RESERVE
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item and not FUEL[item.name] and not TOOLS[item.name] and not TC.MODEM_ITEMS[item.name] then
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
    if count(crop.seed) >= RESERVE then return true end
    local ok, why = face(2)
    if not ok then return false, "Drehen fehlgeschlagen", why end
    local exists = container(turtle.inspect)
    local badItem = false
    if exists then
        while count(crop.seed) < RESERVE do
            local slot = receiveSlot(crop.seed)
            if not slot then break end
            turtle.select(slot)
            if not turtle.suck(math.min(64, RESERVE - count(crop.seed))) then break end
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
        if GEAR then GEAR.radio() end
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
        local dug, why = turtle.digDown()
        if not dug and tostring(why):find("No tool", 1, true) then
            if not equipTool() then return false, NO_TOOL end
            dug, why = turtle.digDown()
        end
        if not dug then
            return false, tostring(why):find("No tool", 1, true) and NO_TOOL or "Pflanze nicht abbaubar"
        end
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
local sendStatus
local lastRadio = os.clock()
-- Mit Chunkloader: alle reportEvery Sekunden kurz Modem anlegen und funken.
-- Das Werkzeug kommt beim naechsten Ernten automatisch zurueck.
local function radioWindow()
    if not GEAR or os.clock() - lastRadio < CL.report then return end
    if GEAR.radio() then sendStatus(); sleep(1.5) end
    lastRadio = os.clock()
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
            radioWindow()
            local fuel = turtle.getFuelLevel()
            local dist = math.abs(st.x - x) + math.abs(st.z - row) + x + row
            local need = dist * (1 + drainPerSec * 0.6) + 8 + math.ceil(drainPerSec * 90)
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
        if GEAR then GEAR.radio() end
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
            local contact = CFG.radioTimeout == 0 or now - run.lastContact < CFG.radioTimeout
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
    if GEAR then GEAR.radio() end
    chunkTick()
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
                if GEAR then GEAR.radio() end
                while active() and run.waitUntil > os.clock() do
                    chunkTick()
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
        chunks = GEAR and (GEAR.radius > 0 and CL.chunks or 0) or nil,
        chunkFuel = GEAR and math.floor(GEAR.perSecond() * 3600 + 0.5) or nil,
        freeSlots = freeSlots(), x = st.x, z = st.z, total = st.total or 0,
        harvested = st.harvested or 0, rounds = st.rounds or 0,
        roundYield = run.roundYield, roundPlants = run.roundPlants,
        scanned = run.scanned, cells = CFG.width * CFG.length,
        wait = math.max(0, math.ceil(run.waitUntil - os.clock())) }
end
sendStatus = function() pcall(rednet.send, st.controller, snapshot(), PROTOCOL) end
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
if not GEAR then pcall(equipTool) end
term.clear(); term.setCursorPos(1, 1)
print("TOAST FARM 2.1 - Turtle #" .. os.getComputerID())
print("Zentrale #" .. st.controller .. " | " .. crop.label)
if GEAR then print("Chunkloader: " .. CL.chunks .. " Chunk(s), ca. " .. TC.chunkFuelPerHour(CL.chunks) .. " Fuel/h beim Arbeiten") end
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
    assert(integer(f.interval,1,86400) and integer(f.seedReserve,0,256), "interval/seedReserve ungueltig.")
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
]======]
FILES["mine_turtle.lua"]=[======[
-- Toast Mining 2.6: Strip-Mining mit parallelen Gaengen, mit eigener Basis.
-- Fahrweg 2.2: Turtle baut oben/unten beim Vorwaertsfahren mit ab (1 Fuel je Block),
-- Gaenge werden in Schlangenlinie verbunden, Heimfahrt nur wenn noetig.
-- Neu: Positions-Wiederherstellung nach Absturz, RESET, Auto-Retry, Mob-Blockaden.
local common=dofile("/mine_common.lua")
local cfg=common.load();assert(cfg.role=="turtle","Mining Turtle erforderlich.")
-- CCChunkloader: Chunkloader bleibt angebaut, Spitzhacke <-> Modem werden getauscht.
local TC=dofile("/toast_common.lua")
local CL=TC.chunkConfig(cfg.chunkload)
local GEAR
if CL.enabled then
    local why
    GEAR,why=TC.gear(CL,{['minecraft:diamond_pickaxe']=true,['minecraft:netherite_pickaxe']=true})
    assert(GEAR,why)
    assert(GEAR.radio(),"Chunkloader: Funk-/Endermodem ins Turtle-Inventar legen.")
end
common.modem()
local R=cfg.recovery or {autoRetry=3,retryDelay=30,moveRetries=8}
local C,FILE,args=cfg.mine,"/toast_mining_state",{...}
local H,L,G=C.height,C.length,C.gap
assert(C.side==nil or C.side=="right" or C.side=="left","mine.side: right oder left.")
local MIRROR=C.side=="left"
local width=(C.tunnels-1)*(G+1)+1
-- Schichten zu je 3 Bloecken: Turtle faehrt in der Mitte und baut oben/unten mit ab.
-- Schicht p deckt Reihen 3p..3p+2 ab (Reihe r = y -r). Letzte Schicht ggf. 1-2 hoch.
local P=math.ceil(H/3)
local PASS={}
for p=0,P-1 do
    local r0=3*p;local rem=math.min(3,H-r0)
    if rem==3 then PASS[p]={y=-(r0+1),up=true,down=true}
    else PASS[p]={y=-r0,up=rem==2,down=false} end
end
local WALK=PASS[0].y                    -- Laufebene zur Basis (unterste Schicht)
local area=P*L                          -- Schritte je Gang
local cells=area*C.tunnels
local tag=H<=3 and "strip2:" or "strip3:"   -- bis Hoehe 3 identisch zu 2.2
local layout=tag..L..":"..H..":"..C.tunnels..":"..G..(MIRROR and ":L" or "")
-- Schritt i -> Position (x,y,z) und ob oben/unten mit abgebaut wird.
-- Schlangenlinie in z UND in der Hoehe: Gang 1 Schichten unten->oben,
-- Gang 2 oben->unten usw.; jede Schicht startet dort, wo die vorige endete.
-- ===== Seitlich mitabbauen (nur Abstand 0) =====
-- Fahrspuren im Plus-Muster: jede Spur raeumt pro Schritt Mitte, oben, unten,
-- links, rechts (Drehen kostet kein Fuel). Spuren bei (x+2r) mod 5 = c fuellen
-- die Flaeche lueckenlos; Luecken am Rand bekommen Zusatzspuren.
assert(C.sideDig==nil or type(C.sideDig)=="boolean","mine.sideDig: true oder false.")
local SIDE=C.sideDig==true and G==0
local W=C.tunnels
local LANES,COVERMIN
local function buildLanes()
    local bestList
    for c=0,4 do
        local lanes,cov={},{}
        local function key(x,r) return x*H+r end
        local function add(x,r)
            lanes[#lanes+1]={x=x,r=r}
            for _,d in ipairs({{0,0},{1,0},{-1,0},{0,1},{0,-1}}) do
                local ax,ar=x+d[1],r+d[2]
                if ax>=0 and ax<W and ar>=0 and ar<H then cov[key(ax,ar)]=true end
            end
        end
        for x=0,W-1 do for r=0,H-1 do if (x+2*r)%5==c then add(x,r) end end end
        for x=0,W-1 do for r=0,H-1 do
            if not cov[key(x,r)] then
                -- Zusatzspur dort, wo sie die meisten offenen Felder abdeckt
                local bx,br,bn=x,r,-1
                for _,d in ipairs({{0,0},{1,0},{-1,0},{0,1},{0,-1}}) do
                    local lx,lr=x+d[1],r+d[2]
                    if lx>=0 and lx<W and lr>=0 and lr<H then
                        local n=0
                        for _,e in ipairs({{0,0},{1,0},{-1,0},{0,1},{0,-1}}) do
                            local ax,ar=lx+e[1],lr+e[2]
                            if ax>=0 and ax<W and ar>=0 and ar<H and not cov[key(ax,ar)] then n=n+1 end
                        end
                        if n>bn then bx,br,bn=lx,lr,n end
                    end
                end
                add(bx,br)
            end
        end end
        if not bestList or #lanes<#bestList then bestList=lanes end
    end
    -- Reihenfolge: Start an der Spur, die die Ecke an der Basis abdeckt,
    -- dann immer zur naechstgelegenen offenen Spur (kurze Wechsel am Ende).
    local left={}
    for i,l in ipairs(bestList) do left[i]=l end
    local order={}
    local cx,cr=0,0
    while #left>0 do
        local bi,bd
        for i,l in ipairs(left) do
            local d=math.abs(l.x-cx)+math.abs(l.r-cr)
            if not bd or d<bd or (d==bd and (l.r<left[bi].r or (l.r==left[bi].r and l.x<left[bi].x))) then bi,bd=i,d end
        end
        local l=table.remove(left,bi);order[#order+1]=l;cx,cr=l.x,l.r
    end
    return order
end
local sideNote
if SIDE then
    LANES=buildLanes()
    if #LANES>=W*P then
        SIDE=false
        sideNote="Seitlich mitabbauen bringt bei diesen Massen nichts - normales Verfahren."
    else
        COVERMIN={}
        for li,l in ipairs(LANES) do
            for _,d in ipairs({{0,0},{1,0},{-1,0},{0,1},{0,-1}}) do
                local ax,ar=l.x+d[1],l.r+d[2]
                if ax>=0 and ax<W and ar>=0 and ar<H then
                    local k=ax*H+ar
                    if not COVERMIN[k] or li-1<COVERMIN[k] then COVERMIN[k]=li-1 end
                end
            end
        end
        area=L;cells=#LANES*L
        layout="block5:"..L..":"..H..":"..W..(MIRROR and ":L" or "")
        sideNote="Seitlich mitabbauen: "..#LANES.." Spuren statt "..(W*P)
    end
end
local function step(i)
    if SIDE then
        local li=math.floor((i-1)/L);local j=(i-1)%L
        local l=LANES[li+1]
        local z=li%2==0 and j+1 or L-j
        return l.x,-l.r,z,l.r+1<H,l.r-1>=0,l.x-1>=0,l.x+1<W
    end
    local t=math.floor((i-1)/area);local k=(i-1)%area;local x=t*(G+1)
    local pi=math.floor(k/L);local j=k%L
    local p=t%2==0 and pi or P-1-pi
    local g=t*P+pi
    local z=g%2==0 and j+1 or L-j
    local q=PASS[p]
    return x,q.y,z,q.up,q.down
end
local st={x=0,y=0,z=0,dir=0,next=1,total=0,harvested=0,commandSerial=0,layout=layout}
local oldLayout="strip:"..L..":"..H..":"..C.tunnels..":"..G
local oldLayout22="strip2:"..L..":"..H..":"..C.tunnels..":"..G..(MIRROR and ":L" or "")
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
local function clearPending() st.pending,st.after,st.pendingFuel,st.pendingDrain=nil,nil,nil,nil end
-- Unterbrochene Bewegung ueber den Fuelstand aufloesen:
-- Fuel unveraendert = Schritt nicht ausgefuehrt, Fuel -1 = Schritt ausgefuehrt.
local function resolvePending()
    if not st.pending then return true end
    local fuel=turtle.getFuelLevel()
    if st.pending~="turn" and type(fuel)=="number" and type(st.pendingFuel)=="number" and type(st.after)=="table" then
        if fuel==st.pendingFuel then clearPending();save();return true end
        -- Chunkloader zieht nebenbei Fuel ab: dann ist "1 weniger" nicht eindeutig.
        -- Pruefen: Vor dem Schritt war das Zielfeld frei geraeumt. Steht jetzt in
        -- Fahrtrichtung massiver Block, steht die Turtle sicher schon auf dem Zielfeld.
        if st.pendingDrain then
            if fuel<st.pendingFuel then
                local probe=({forward=turtle.inspect,up=turtle.inspectUp,down=turtle.inspectDown})[st.pending]
                local okp,b=false,nil
                if probe then okp,b=probe() end
                local solid=okp and type(b)=="table" and type(b.name)=="string"
                    and not b.name:find("water",1,true) and not b.name:find("lava",1,true)
                if solid then
                    local a=st.after;st.x,st.y,st.z,st.dir=a.x,a.y,a.z,a.dir;clearPending();save();return true
                end
            end
            return false
        end
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
-- Fortschritt aus der alten Version uebernehmen: angefangener Gang wird neu befahren.
if not SIDE and (st.layout==oldLayout or (st.layout==oldLayout22 and oldLayout22~=layout)) then
    local t=math.floor((st.next-1)/(st.layout==oldLayout and L or (H<=3 and L or 2*L)))
    st.next=math.min(cells+1,t*area+1);st.layout=layout;st.accessHigh=nil
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
-- Turtles nehmen keinen Schaden und fahren durch Wasser/Lava; abgebaut wird alles.
-- Nur andere Turtles werden nie abgebaut (sonst gehen deine eigenen kaputt).
local hard={['computercraft:turtle_normal']=true,['computercraft:turtle_advanced']=true}
local unbreakable={['minecraft:bedrock']=true,['minecraft:barrier']=true,['minecraft:end_portal_frame']=true,
    ['minecraft:end_portal']=true,['minecraft:nether_portal']=true,['minecraft:reinforced_deepslate']=true}
local liquid={['minecraft:water']=true,['minecraft:flowing_water']=true,['minecraft:lava']=true,['minecraft:flowing_lava']=true}
local function status(a,b) run.status,run.detail=a,b or "" end
local function retryable(fault)
    if type(fault)~="string" then return false end
    for _,w in ipairs({"Geschuetzt","Nicht abbaubar","Fuelbedarf","Position unklar"}) do
        if fault:find(w,1,true) then return false end
    end
    return true
end
local function fail(why)
    run.mode,run.fault,run.retryAt="off",why,nil
end
local function active()
    -- radioTimeout=0: auch ohne Zentrale weiterarbeiten (z.B. Zentrale in entladenem Chunk).
    if run.mode~="off" and C.radioTimeout>0 and os.clock()-run.lastContact>C.radioTimeout then fail("Funkverbindung verloren") end
    return run.mode~="off" and not run.recovery
end
local function action(kind,fn,update)
    local x,y,z,dir=st.x,st.y,st.z,st.dir
    update();st.after={x=st.x,y=st.y,z=st.z,dir=st.dir}
    st.x,st.y,st.z,st.dir=x,y,z,dir
    st.pending,st.pendingFuel=kind,turtle.getFuelLevel()
    st.pendingDrain=GEAR~=nil and GEAR.radius>0 or nil;save()
    local ok,why=fn();if ok then update() end
    clearPending();save();return ok,why
end
local function face(dir)
    while st.dir~=dir do
        local left=(st.dir-dir)%4==1
        -- side="left": Gaenge liegen links -> alle Drehungen gespiegelt.
        local ok,why=action("turn",(left~=MIRROR) and turtle.turnLeft or turtle.turnRight,
            function()st.dir=(st.dir+(left and 3 or 1))%4 end)
        if not ok then return false,"Drehen fehlgeschlagen: "..tostring(why) end
    end
    return true
end
-- Spitzhacke: liegt eine im Inventar, legt die Turtle sie selbst an
-- (auf der Seite OHNE Modem).
local TOOLS={['minecraft:diamond_pickaxe']=true,['minecraft:netherite_pickaxe']=true}
local function equipTool()
    if GEAR then return GEAR.tool() end
    for i=1,16 do
        local it=turtle.getItemDetail(i)
        if it and TOOLS[it.name] then
            turtle.select(i)
            for _,side in ipairs({"left","right"}) do
                if peripheral.getType(side)~="modem" then
                    local fn=side=="left" and turtle.equipLeft or turtle.equipRight
                    if fn() then return true end
                end
            end
        end
    end
    return false
end
local NO_TOOL="Keine Spitzhacke: Diamant-Spitzhacke in die Turtle legen"
local FUELS={['minecraft:coal']=80,['minecraft:charcoal']=80,['minecraft:coal_block']=800}
-- mine.useCoal: abgebaute Kohle sofort verbrennen, solange der Tank Platz hat.
-- Spart Fahrten zur Brennstoffkiste. Nur zwischen zwei Bewegungen (kein
-- offener Schritt), damit die Positions-Pruefung ueber den Fuelstand stimmt.
local function burnCoal()
    if not C.useCoal or st.pending then return end
    local limit=turtle.getFuelLimit()
    if limit=="unlimited" or turtle.getFuelLevel()=="unlimited" then return end
    local burned=0
    for i=1,16 do
        local item=turtle.getItemDetail(i)
        local value=item and FUELS[item.name]
        if value then
            turtle.select(i)
            while turtle.getItemCount(i)>0 and turtle.getFuelLevel()+value<=limit do
                if not turtle.refuel(1) then break end
                burned=burned+1
            end
        end
    end
    if burned>0 then st.coal=(st.coal or 0)+burned;save() end
    turtle.select(1)
end
local function freeSlots()
    local n=0;for i=1,16 do if turtle.getItemCount(i)==0 then n=n+1 end end;return n
end
local function blockReason(b)
    if unbreakable[b.name] then return "Nicht abbaubar: "..b.name end
    if protected[b.name] or hard[b.name] then return "Geschuetzter Block: "..b.name end
end
local function clear(inspect,dig,interruptible)
    -- Rueckweg (nicht unterbrechbar): immer freiraeumen, auch mit vollem Inventar
    -- (Block faellt dann als Item auf den Boden) und laenger auf Kies/Sand warten.
    local tries=interruptible and C.digRetries or math.max(64,C.digRetries)
    for _=1,tries do
        if interruptible and not active() then return false,"stopped" end
        local exists,b=inspect()
        if not exists or liquid[b.name] then return true end
        local reason=blockReason(b)
        if reason and hard[b.name] and not interruptible then
            sleep(2)                    -- andere Turtle im Weg: abwarten, sie faehrt weiter
        elseif reason then return false,reason
        elseif interruptible and freeSlots()==0 then return false,"resupply"
        else
            local ok,why=dig()
            if not ok and tostring(why):find("No tool",1,true) then
                if not equipTool() then return false,NO_TOOL end
                ok,why=dig()
            end
            if not ok then
                if tostring(why):find("No tool",1,true) then return false,NO_TOOL end
                return false,"Nicht abbaubar: "..b.name.." / "..tostring(why)
            end
            st.harvested=(st.harvested or 0)+1;save()
            if C.useCoal and b.name:find("coal_ore",1,true) then sleep(0.1);burnCoal() end
            sleep(0.1)
        end
    end
    local exists,b=inspect();if not exists or liquid[b.name] then return true end
    return false,blockReason(b) or "Zu viel nachrutschender Kies/Sand"
end
local DX,DZ={[0]=0,1,0,-1},{[0]=1,0,-1,0}
-- ===== Wegplanung =====
-- Die Turtle weiss, welche Felder schon frei sind: fertige Schritte (aus st.next),
-- Querwege zwischen den Gaengen und alle selbst gefahrenen Strecken (st.segs).
-- Fuer Hin- und Rueckweg werden mehrere Wege bewertet und der beste genommen.
st.segs=type(st.segs)=="table" and st.segs or {}
local SEGMAX=48
local function tunnelX(k) return k*(G+1) end
local function firstY(k) return PASS[k%2==0 and 0 or P-1].y end
local function lastY(k) return PASS[k%2==0 and P-1 or 0].y end
local function zStart(k) return (k*P)%2==0 and 1 or L end
local function zEnd(k) return (k*P+P-1)%2==0 and L or 1 end
local function onSeg(x,y,z)
    for _,g in ipairs(st.segs) do
        if g.a=="x" then if y==g.y and z==g.z and x>=g.lo and x<=g.hi then return true end
        elseif g.a=="y" then if x==g.x and z==g.z and y>=g.lo and y<=g.hi then return true end
        elseif x==g.x and y==g.y and z>=g.lo and z<=g.hi then return true end
    end
    return false
end
local function addSeg(a,x,y,z,from,to)
    if from==to then return end
    local lo,hi=math.min(from,to),math.max(from,to)
    for i=#st.segs,1,-1 do
        local g=st.segs[i]
        local same=g.a==a and (a=="x" and g.y==y and g.z==z or a=="y" and g.x==x and g.z==z or a=="z" and g.x==x and g.y==y)
        if same and g.hi>=lo-1 and g.lo<=hi+1 then lo,hi=math.min(lo,g.lo),math.max(hi,g.hi);table.remove(st.segs,i) end
    end
    st.segs[#st.segs+1]={a=a,x=x,y=y,z=z,lo=lo,hi=hi}
    while #st.segs>SEGMAX do table.remove(st.segs,1) end
end
local function cellDug(x,y,z)
    if z==0 then return x==0 and y==0 end
    if y>0 or y<-(H-1) or z<1 or z>L or x<0 or x>=width then return onSeg(x,y,z) end
    local k=math.floor(x/(G+1))
    if x==tunnelX(k) and k<C.tunnels then
        local b=math.floor(-y/3);local pi=k%2==0 and b or P-1-b
        local g=k*P+pi;local j=g%2==0 and z-1 or L-z
        if k*area+pi*L+j+1<st.next then return true end
    elseif k+1<C.tunnels and z==zEnd(k) and y==lastY(k) and st.next>(k+1)*area+1 then
        return true                     -- Querweg von Gang k nach k+1
    end
    return onSeg(x,y,z)
end
-- Bewertung: Zuege + Gewicht * noch abzubauende Felder
local function partialTunnel() if st.next>cells then return C.tunnels end return math.floor((st.next-1)/area) end
local function score(legs,w)
    local x,y,z=st.x,st.y,st.z;local moves,digs=0,0
    local pt=partialTunnel()
    for _,lg in ipairs(legs) do
        local a,v=lg[1],lg[2]
        local cur=a=="x" and x or (a=="y" and y or z)
        local d=v>cur and 1 or -1
        -- Schnell: Strecke komplett in einem fertigen Gang (innerhalb der Gangmasse) ist frei.
        local k=math.floor(x/(G+1))
        if a~="x" and x==tunnelX(k) and k<pt and z>=1 and (a=="y" or v>=1) then
            moves=moves+math.abs(v-cur);cur=v
        end
        while cur~=v do
            cur=cur+d;moves=moves+1
            if not cellDug(a=="x" and cur or x,a=="y" and cur or y,a=="z" and cur or z) then digs=digs+1 end
        end
        if a=="x" then x=v elseif a=="y" then y=v else z=v end
    end
    return moves+w*digs,moves,digs
end
-- Wie weit ist der vordere Querweg (z=1, Laufebene) schon frei? -> Gangnummer
local function frontReach()
    local reach=0
    for x=1,width-1 do
        if not cellDug(x,WALK,1) then break end
        if x%(G+1)==0 then reach=x/(G+1) end
    end
    return reach
end
-- Nur sinnvolle Umstiegs-Gaenge pruefen: ganz durch die Gaenge, bis zum Ende des
-- freien Querwegs, oder direkt vorne (ggf. mit Freiraeumen).
local function viaList(k)
    local list,seen={},{}
    for _,j in ipairs({0,math.min(k,frontReach()),k}) do
        if not seen[j] then seen[j]=true;list[#list+1]=j end
    end
    return list
end
-- Rueckweg-Kandidaten: durch die Gaenge zurueck bis Gang j, dann vorne (z=1) am Querweg zur Basis.
local function homeCandidates()
    if st.z==0 then return {{}} end
    local k=math.max(0,math.min(C.tunnels-1,math.floor(st.x/(G+1))))
    local pre={}
    if st.x~=tunnelX(k) then pre[1]={"x",tunnelX(k)} end
    local out={}
    for _,j in ipairs(viaList(k)) do
        local legs={}
        for _,l in ipairs(pre) do legs[#legs+1]=l end
        for m=k,j+1,-1 do
            legs[#legs+1]={"y",firstY(m)};legs[#legs+1]={"z",zStart(m)};legs[#legs+1]={"x",tunnelX(m-1)}
        end
        legs[#legs+1]={"y",WALK};legs[#legs+1]={"z",1};legs[#legs+1]={"x",0}
        legs[#legs+1]={"y",0};legs[#legs+1]={"z",0}
        out[#out+1]=legs
    end
    return out
end
local function best(cands,w)
    local bl,bs,bm=nil,math.huge,0
    for _,legs in ipairs(cands) do
        local sc,m=score(legs,w)
        if sc<bs then bl,bs,bm=legs,sc,m end
    end
    return bl or {},bm
end
-- Vom Gangstart (Basis) zum Ziel: vorne am Querweg bis Gang j, dann durch die Gaenge.
local function workCandidates(x,y,z)
    local tw=math.floor(x/(G+1))
    local out={}
    for _,j in ipairs(viaList(tw)) do
        local legs={{"z",1},{"y",WALK},{"x",tunnelX(j)}}
        for m=j,tw-1 do
            legs[#legs+1]={"y",lastY(m)};legs[#legs+1]={"z",zEnd(m)};legs[#legs+1]={"x",tunnelX(m+1)}
        end
        legs[#legs+1]={"y",firstY(tw)};legs[#legs+1]={"z",z};legs[#legs+1]={"y",y}
        out[#out+1]=legs
    end
    return out
end
-- Gewicht fuers Freiraeumen: kostet kein Fuel, nur Zeit -> fast egal (0.1).
-- Mit (fast) vollem Inventar wuerde Abgebautes aber auf den Boden fallen ->
-- dann eher freie Wege nehmen (0.5).
local function digWeight() return freeSlots()<=1 and 0.5 or 0.1 end
-- ----- Wegplanung im Spurmodus: Wegsuche (Dijkstra) im Querschnitt -----
local function blockDug(x,y,z)
    if z==0 then return x==0 and y==0 end
    local r=-y
    if x<0 or x>=W or r<0 or r>=H or z<1 or z>L then return onSeg(x,y,z) end
    local li=math.floor((st.next-1)/L)
    local m=COVERMIN[x*H+r]
    if m and m<li then return true end
    local l=LANES[li+1]
    if l and math.abs(l.x-x)+math.abs(l.r-r)<=1 then
        local j=(st.next-1)%L
        if li%2==0 then if z<=j then return true end elseif z>=L-j+1 then return true end
    end
    return onSeg(x,y,z)
end
-- Kosten pro Feld: 1 Zug + Gewicht, falls dort noch abzubauen ist.
local function dijkstra(z,sx,sr,w)
    local N=W*H;local dist,prev={},{}
    local heap={}
    local function push(c,d) heap[#heap+1]={c,d};local i=#heap
        while i>1 do local p=math.floor(i/2);if heap[p][2]<=heap[i][2] then break end;heap[p],heap[i]=heap[i],heap[p];i=p end end
    local function pop() local top=heap[1];heap[1]=heap[#heap];heap[#heap]=nil;local i=1
        while true do local a,b=2*i,2*i+1;local m=i
            if heap[a] and heap[a][2]<heap[m][2] then m=a end
            if heap[b] and heap[b][2]<heap[m][2] then m=b end
            if m==i then break end;heap[m],heap[i]=heap[i],heap[m];i=m end
        return top end
    local s0=sx*H+sr;dist[s0]=0;push(s0,0)
    while #heap>0 do
        local t=pop();local c,d=t[1],t[2]
        if d<=dist[c] then
            local cx,cr=math.floor(c/H),c%H
            for _,e in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
                local nx,nr=cx+e[1],cr+e[2]
                if nx>=0 and nx<W and nr>=0 and nr<H then
                    local n=nx*H+nr
                    local nd=d+1+(blockDug(nx,-nr,z) and 0 or w)
                    if not dist[n] or nd<dist[n] then dist[n]=nd;prev[n]=c;push(n,nd) end
                end
            end
        end
    end
    return dist,prev
end
-- Weg im Querschnitt als Legs (zusammengefasst je Achse)
local function crossLegs(prev,from,to,reverse)
    local cells={}
    local c=to
    while c and c~=from do cells[#cells+1]=c;c=prev[c] end
    if c~=from then return nil end
    cells[#cells+1]=from
    local seq={}
    if reverse then for i=1,#cells do seq[#seq+1]=cells[i] end      -- to -> from
    else for i=#cells,1,-1 do seq[#seq+1]=cells[i] end end          -- from -> to
    local legs={}
    for i=2,#seq do
        local ax,ar=math.floor(seq[i-1]/H),seq[i-1]%H
        local bx,br=math.floor(seq[i]/H),seq[i]%H
        local a=bx~=ax and "x" or "y";local v=a=="x" and bx or -br
        if legs[#legs] and legs[#legs][1]==a then legs[#legs][2]=v else legs[#legs+1]={a,v} end
    end
    return legs
end
local function concat(...)
    local out={}
    for _,t in ipairs({...}) do for _,l in ipairs(t) do out[#out+1]=l end end
    return out
end
-- Spalten, die ueber die ganze Laenge frei sind (fertige Spurmitten)
local function freeColumns(extra)
    local cols={}
    local li=math.floor((st.next-1)/L)
    for i=1,math.min(li,#LANES) do cols[#cols+1]=LANES[i] end
    if extra then cols[#cols+1]=extra end
    return cols
end
-- Rueckweg: im Querschnitt zu einer freien Spalte, darin nach vorne (z=1),
-- vorne im Querschnitt zur Ecke an der Basis, hinein.
local function blockHome(w)
    if st.z==0 then return {},0 end
    local sx,sr=st.x,-st.y
    local dz,pz=dijkstra(st.z,sx,sr,w)
    local d1,p1=dijkstra(1,0,0,w)
    local li=math.floor((st.next-1)/L)
    local cur=LANES[li+1]
    local cols=freeColumns()
    -- eigene Spur zaehlt mit, wenn sie vorne begonnen hat und die Turtle darauf steht
    if cur and li%2==0 and sx==cur.x and sr==cur.r then cols[#cols+1]=cur end
    local bestC,bestCost
    for _,c in ipairs(cols) do
        local k=c.x*H+c.r
        if dz[k] and d1[k] then
            local cost=dz[k]+(st.z-1)+d1[k]
            if not bestCost or cost<bestCost then bestC,bestCost=c,cost end
        end
    end
    local s0,o=sx*H+sr,0
    if not bestC then
        -- Notfall: direkt nach vorne (raeumt frei, was im Weg ist)
        local legs=concat({{"z",1}},crossLegs(p1,o,s0,true) or {{"y",0},{"x",0}},{{"z",0}})
        return legs,st.z+sx+sr
    end
    local k=bestC.x*H+bestC.r
    local legs=concat(crossLegs(pz,s0,k) or {},{{"z",1}},crossLegs(p1,o,k,true) or {},{{"z",0}})
    return legs,bestCost+1
end
-- Hinweg von der Basis zu Spur-Ziel (x,y,z)
local function blockWork(x,y,z,w)
    local tr=-y
    local d1,p1=dijkstra(1,0,0,w)
    local dt,pt=dijkstra(z,x,tr,w)
    local li=math.floor((st.next-1)/L)
    local cur=LANES[li+1]
    local cols=freeColumns()
    local bestC,bestCost
    for _,c in ipairs(cols) do
        local k=c.x*H+c.r
        if d1[k] and dt[k] then
            local cost=d1[k]+(z-1)+dt[k]
            if not bestCost or cost<bestCost then bestC,bestCost=c,cost end
        end
    end
    local o,t=0,x*H+tr
    -- Ziel liegt auf der eigenen, vorne begonnenen Spur: vorne hin, dann geradeaus
    if cur and li%2==0 and cur.x==x and cur.r==tr then
        local cost=d1[t]+(z-1)
        if not bestCost or cost<=bestCost then
            return concat({{"z",1}},crossLegs(p1,o,t) or {},{{"z",z}})
        end
    end
    if not bestC then
        return concat({{"z",1}},crossLegs(p1,o,t) or {{"x",x},{"y",y}},{{"z",z}})
    end
    local k=bestC.x*H+bestC.r
    return concat({{"z",1}},crossLegs(p1,o,k) or {},{{"z",z}},crossLegs(pt,t,k,true) or {})
end
local hc={next=-1,n=0}
local function homeDistance()
    if st.z==0 then return 0 end
    if hc.next~=st.next or hc.n>=40 then
        local m
        if SIDE then _,m=blockHome(digWeight()) else _,m=best(homeCandidates(),digWeight()) end
        hc={next=st.next,x=st.x,y=st.y,z=st.z,m=m,n=0}
    end
    hc.n=hc.n+1
    return hc.m+math.abs(st.x-hc.x)+math.abs(st.y-hc.y)+math.abs(st.z-hc.z)
end
-- Chunks nur laden, solange die Turtle unterwegs ist / arbeitet / auf neuen Versuch wartet.
local function chunkTick()
    if not GEAR then return end
    local need=run.mode~="off" or not homePosition() or (run.fault~=nil and run.retryAt~=nil) or CL.idle
    GEAR.set(need and CL.radius or 0)
end
local function reserve()
    local drain=GEAR and GEAR.perSecond() or 0
    return homeDistance()*(1+drain*0.6)+12+math.ceil(drain*90)
end
local function move(kind,interruptible)
    chunkTick()
    if interruptible and not active() then return false,"stopped" end
    local fuel=turtle.getFuelLevel()
    if interruptible and (freeSlots()<C.freeSlots or (fuel~="unlimited" and fuel<reserve())) then return false,"resupply" end
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
local function lineX(x,i)
    while st.x~=x do
        local ok,why=face(st.x<x and 1 or 3);if not ok then return false,why end
        ok,why=move("forward",i);if not ok then return false,why end
    end
    return true
end
local function lineZ(z,i)
    while st.z~=z do
        local ok,why=face(st.z<z and 0 or 2);if not ok then return false,why end
        ok,why=move("forward",i);if not ok then return false,why end
    end
    return true
end
local function vertical(y,i)
    while st.y~=y do local ok,why=move(st.y<y and "down" or "up",i);if not ok then return false,why end end
    return true
end
local function chain(...)
    for _,f in ipairs({...}) do local ok,why=f();if not ok then return false,why end end
    return true
end
-- Legs ausfuehren; gefahrene Strecken merken (auch teilweise), damit spaetere
-- Wege sie als frei kennen.
local function runLegs(legs,i)
    if #legs==0 then return true end
    for _,lg in ipairs(legs) do
        local a,v=lg[1],lg[2]
        local sx,sy,sz=st.x,st.y,st.z
        local ok,why
        if a=="x" then ok,why=lineX(v,i) elseif a=="y" then ok,why=vertical(v,i) else ok,why=lineZ(v,i) end
        if a=="x" then addSeg("x",nil,sy,sz,sx,st.x) elseif a=="y" then addSeg("y",sx,nil,sz,sy,st.y)
        else addSeg("z",sx,sy,nil,sz,st.z) end
        if not ok then save();return false,why end
    end
    save();return true
end
local function routeTo(x,y,z,i)
    if SIDE then
        -- Auf der eigenen Spur hinter dem Ziel: geradeaus weiter
        if st.x==x and st.y==y and st.z>0 then return runLegs({{"z",z}},i) end
        if st.z~=0 then
            local h=blockHome(digWeight())
            local ok,why=runLegs(h,i);if not ok then return false,why end
        end
        return runLegs(blockWork(x,y,z,0.1),i)
    end
    local cands={}
    if st.z==0 then cands=workCandidates(x,y,z)
    else
        -- Schon im Zielgang: direkt ueber die erste Schicht zum Ziel.
        if st.x==tunnelX(math.floor(x/(G+1))) and x==st.x then
            cands[#cands+1]={{"y",firstY(math.floor(x/(G+1)))},{"z",z},{"y",y}}
        end
        -- Sonst (oder falls kuerzer): erst zur Basis-Einfahrt, dann wie von der Basis.
        local h=best(homeCandidates(),digWeight())
        for _,w in ipairs(workCandidates(x,y,z)) do
            local legs={}
            for n=1,#h-1 do legs[#legs+1]=h[n] end     -- ohne den letzten Schritt in die Basis
            for n=2,#w do legs[#legs+1]=w[n] end
            cands[#cands+1]=legs
        end
    end
    local legs=best(cands,0.1)
    return runLegs(legs,i)
end
-- Naechster Schritt direkt (auch Querweg am Gangende): Hoehe, dann x, dann z.
local function direct(x,y,z,i)
    return chain(function()return vertical(y,i)end,function()return lineX(x,i)end,function()return lineZ(z,i)end)
end
local function home()
    if homePosition() and st.dir==0 then return true end
    status("Rueckkehr",run.fault or "Fahre ueber freigelegte Wege zur Basis.")
    local legs
    if SIDE then legs=blockHome(digWeight()) else legs=best(homeCandidates(),digWeight()) end
    local ok,why=runLegs(legs,false)
    if ok then ok,why=face(0) end
    hc.next=-1
    return ok,why
end
local containers={['minecraft:chest']=true,['minecraft:trapped_chest']=true,['minecraft:barrel']=true}
local function container(fn)local ok,b=fn();return ok and containers[b.name] end
local function unload()
    if not container(turtle.inspectDown) then return false,"Ausgabekiste fehlt" end
    burnCoal()      -- uebrige Kohle zuerst in den Tank (falls eingeschaltet)
    for i=1,16 do
        local item=turtle.getItemDetail(i)
        if item and not TOOLS[item.name] and not TC.MODEM_ITEMS[item.name] then
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
        if GEAR then GEAR.radio() end
        sleep(1)
    end
    return false,"stopped"
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
            local contact=C.radioTimeout==0 or now-run.lastContact<C.radioTimeout
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
    if GEAR then GEAR.radio() end
    chunkTick()
end
local sendStatus
local lastRadio=os.clock()
-- Mit Chunkloader: alle reportEvery Sekunden kurz Modem anlegen und funken.
-- Die Spitzhacke kommt beim naechsten Abbau automatisch zurueck.
local function radioWindow()
    if not GEAR or os.clock()-lastRadio<CL.report then return end
    if GEAR.radio() then sendStatus();sleep(1.5) end
    lastRadio=os.clock()
end
local function work()
    while true do
        chunkTick()
        if not run.recovery then
            if active() then
                radioWindow()
                if st.next>cells then finish();status("Fertig","Neuer Auftrag: toast.lua --new")
                else
                    local ok,why=true
                    local fuel=turtle.getFuelLevel()
                    if homePosition() or freeSlots()<C.freeSlots or (fuel~="unlimited" and fuel<reserve()) then
                        ok,why=supplies()
                    end
                    if ok and active() then
                        status("Abbau",SIDE and ("Spur "..(math.floor((st.next-1)/L)+1).." / "..#LANES)
                            or ("Gang "..(math.floor((st.next-1)/area)+1).." / "..C.tunnels))
                        local x,y,z,up,down,left,right=step(st.next)
                        local px,py,pz
                        if st.next>1 then px,py,pz=step(st.next-1) end
                        if px and st.x==px and st.y==py and st.z==pz then ok,why=direct(x,y,z,true)
                        else ok,why=routeTo(x,y,z,true) end
                        if ok and up then ok,why=clear(turtle.inspectUp,turtle.digUp,true) end
                        if ok and down then ok,why=clear(turtle.inspectDown,turtle.digDown,true) end
                        -- Spurmodus: links/rechts durch Drehen mitabbauen (kostet kein Fuel).
                        -- Schon freie Seiten werden uebersprungen (spart Zeit).
                        if SIDE and ok then
                            local sides={}
                            if right and not blockDug(x+1,y,z) then sides[#sides+1]=1 end
                            if left and not blockDug(x-1,y,z) then sides[#sides+1]=3 end
                            for _,d in ipairs(sides) do
                                if ok and active() then
                                    ok,why=face(d)
                                    if ok then ok,why=clear(turtle.inspect,turtle.dig,true) end
                                end
                            end
                        end
                    end
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
        chunks=GEAR and (GEAR.radius>0 and CL.chunks or 0) or nil,chunkFuel=GEAR and math.floor(GEAR.perSecond()*3600+0.5) or nil,
        x=st.x,y=st.y,z=st.z,total=st.total or 0,harvested=st.harvested or 0,coal=st.coal or 0,useCoal=C.useCoal==true,
        rounds=math.floor((st.next-1)/area),scanned=st.next-1,cells=cells}
end
sendStatus=function()pcall(rednet.send,cfg.controllerId,snapshot(),common.protocol)end
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
if not GEAR then pcall(equipTool) end
term.clear();term.setCursorPos(1,1)
print("TOAST MINING 2.6 / Turtle #"..os.getComputerID())
print(C.tunnels.." Gaenge / "..C.length.." lang / "..C.height.." hoch / Abstand "..C.gap)
if sideNote then print(sideNote) end
print("Zentrale #"..cfg.controllerId)
if GEAR then print("Chunkloader: "..CL.chunks.." Chunk(s), ca. "..TC.chunkFuelPerHour(CL.chunks).." Fuel/h beim Arbeiten") end
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
    assert(integer(f.length,1,1024) and integer(f.height,1,64) and integer(f.tunnels,1,64) and integer(f.gap,0,16), "Strip: length 1-1024, height 1-64, tunnels 1-64, gap 0-16.")
    assert(integer(f.fuelTarget,100,20000), "fuelTarget: 100 bis 20000.")
    assert(f.sideDig==nil or type(f.sideDig)=="boolean", "sideDig: true oder false.")
    assert(f.useCoal==nil or type(f.useCoal)=="boolean", "useCoal: true oder false.")
    assert(f.radioTimeout==0 or integer(f.radioTimeout,10,300), "radioTimeout: 0 (aus) oder 10 bis 300 Sekunden.")
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
    local label=os.getComputerLabel and os.getComputerLabel()
    line(1,"TOAST / WIRELESS REPEATER"..(label and (" / "..label) or ""))
    line(3,"Computer-ID: "..os.getComputerID())
    line(4,"Funkmodems: "..count..(count==0 and " - BITTE ANBRINGEN" or " / AKTIV"))
    line(6,"Weitergeleitet: "..repeated)
    line(7,"Doppelte ignoriert: "..duplicates)
    line(8,"Cache voll: "..dropped)
    line(10,"Rednet: Farm, Mining, Pocket")
    line(12,"Endermodem: Reichweite unbegrenzt")
    line(11,"IDs bleiben unveraendert.")
    line(14,"Q / Ctrl+T: beenden")
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
-- TOAST CONTROL 2.9 – Ein-Datei-Installer (alle Programme sind hier eingebaut).
-- Start: wget run <link>            -> Update oder Komplett neu
--        wget run <link> clean      -> Komplett neu
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
local ui=assert(load(code["toast_setup.lua"],"@toast_setup.lua"))().new(common)
local color=term.isColor and term.isColor()
local function fg(c) if color then term.setTextColor(c) end end
local function warn(s) fg(colors.orange);print(s);fg(colors.white) end
ui.header("Installation auf Geraet #"..os.getComputerID())
print("")
if clean==nil then
    fg(colors.yellow);write("1 ");fg(colors.white);print("Update")
    ui.hint("  Einstellungen + Fortschritt bleiben")
    fg(colors.yellow);write("2 ");fg(colors.white);print("Komplett neu")
    ui.hint("  ALLES auf dem Geraet loeschen")
    print("")
    write("Auswahl [1]: ")
    clean=read()=="2"
end
if clean then
    ui.header("Komplett neu")
    warn("Alle Dateien auf diesem Geraet werden")
    warn("geloescht, auch eigene Programme.")
    if turtle then warn("Turtle vorher an ihre Basis stellen!") end
    print("")
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
    if not fn then warn("Config defekt, wird ersetzt: "..path);return nil end
    local ok,result=pcall(fn)
    if not ok or type(result)~="table" then warn("Config defekt, wird ersetzt: "..path);return nil end
    return result
end
local oldFarm,oldMine=config("/farm.config.lua"),config("/mine.config.lua")
local existing=config("/toast.config.lua")
if existing and not pcall(function()
    local copy=common.copy(existing);copy.role=((copy.role=="repeater" or copy.role=="info") and not turtle and not pocket) and copy.role or nil;common.load(copy) end) then
    -- Kaputte/inkompatible Config nicht uebernehmen, sondern neu anlegen.
    warn("Vorhandene Config ungueltig, wird neu erstellt.")
    existing=nil
end
local c=common.withDefaults(existing or {})
-- Alte Standard-Schutzliste (Kisten, Oefen, Spawner...) ersetzen: jetzt wird alles abgebaut.
local OLD_PROTECT={["minecraft:bedrock"]=1,["minecraft:chest"]=1,["minecraft:trapped_chest"]=1,["minecraft:barrel"]=1,
    ["minecraft:ender_chest"]=1,["minecraft:hopper"]=1,["minecraft:spawner"]=1,["minecraft:furnace"]=1,
    ["minecraft:blast_furnace"]=1,["minecraft:smoker"]=1}
local configChanged=false
local function resetProtection(cfgTable)
    local list=type(cfgTable)=="table" and type(cfgTable.mine)=="table" and cfgTable.mine.protectedBlocks
    if type(list)~="table" or #list==0 then return end
    for _,name in ipairs(list)do if not OLD_PROTECT[name] then return end end
    cfgTable.mine.protectedBlocks={};return true
end
if resetProtection(c) then configChanged=existing~=nil;print("Mining: alte Schutzliste entfernt, alles wird abgebaut.") end
if oldMine then resetProtection(oldMine) end
local role=turtle and "turtle" or (pocket and "pocket" or "controller")
if requested=="repeater" or (not turtle and not pocket and c.role=="repeater") then role="repeater" end
if not turtle and not pocket and c.role=="info" and not requested then role="info" end
-- Neuer stationaerer Computer: Zentrale oder Repeater? Ohne Monitor ist Repeater vorgewaehlt.
if role=="controller" and not requested and (clean or not existing) then
    local monitor=peripheral.find("monitor")~=nil
    ui.header("Computer"..(monitor and " mit Monitor" or " ohne Monitor"))
    print("")
    fg(colors.yellow);write("1 ");fg(colors.white);print("Zentrale  (steuert alle Turtles)")
    fg(colors.yellow);write("2 ");fg(colors.white);print("Repeater  (leitet Funk weiter)")
    fg(colors.yellow);write("3 ");fg(colors.white);print("Infoscreen  (zeigt nur Infos/Stats)")
    print("")
    while true do
        write("Auswahl ["..(monitor and "1" or "2").."]: ")
        local v=read()
        if v=="" then v=monitor and "1" or "2" end
        if v=="1" then break end
        if v=="2" then role="repeater";break end
        if v=="3" then role="info";break end
    end
end
assert(role~="repeater" or (not turtle and not pocket),"Repeater auf stationaerem Computer installieren.")
assert(not requested or requested=="repeater" or role=="turtle","farm/mining nur fuer Turtles.")
if existing and not requested and not (c.role==nil or c.role=="auto" or c.role==role) then
    printError("Gespeicherte Rolle passt nicht zum Geraet, wird neu erkannt.")
    existing=nil;c=common.withDefaults({})
end
local function chooseJob()
    ui.header("Turtle #"..os.getComputerID())
    print("")
    fg(colors.yellow);write("1 ");fg(colors.white);print("Farm")
    fg(colors.yellow);write("2 ");fg(colors.white);print("Mining")
    print("")
    while true do
        write("Aufgabe: ")
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
            ui.header("Suche Zentrale ...")
            found={rednet.lookup(common.protocol)}
            if #found==1 and common.id(found[1]) and found[1]~=os.getComputerID() then
                c.controllerId=found[1];print("Zentrale gefunden: #"..found[1])
            else found={} end
        end
        if #found==0 then
            while true do
                ui.header("Zentrale nicht gefunden")
                ui.hint("ID steht oben auf der Zentrale.")
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
if (c.name or "")=="" and type(c.label)=="string" and c.label~="" then c.name=common.label(c.label) end
if c.name=="" and os.getComputerLabel and os.getComputerLabel() then c.name=common.label(os.getComputerLabel()) end
c.label=c.name
-- Einstellungen: Uebersicht mit Nummern (bei Update auf Wunsch).
local before=ui.layoutKey(c,job)
local show=clean or not existing or requested
if not show then
    ui.header("Update")
    print("")
    show=ui.yesno("Einstellungen ansehen/aendern?",false)
end
while true do
    if show then ui.run(c,{role=role,job=job,installer=true}) end
    local ok,why=pcall(function() common.load(common.copy(c)) end)
    if ok then break end
    ui.header("Einstellung ungueltig");warn(tostring(why));sleep(2);show=true
end
local resetProgress=not clean and before~=ui.layoutKey(c,job) and ui.confirmReset(job)
common.load(c)
local names={"toast.lua","toast_common.lua","toast_setup.lua"}
if role=="controller" then
    for _,name in ipairs({"toast_control.lua","toast_model.lua","toast_ui.lua"})do names[#names+1]=name end
elseif role=="pocket" then names[#names+1]="toast_pocket.lua";names[#names+1]="toast_ui.lua"
elseif role=="info" then names[#names+1]="toast_info.lua";names[#names+1]="toast_ui.lua"
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
-- Config immer sauber neu schreiben (Werte bleiben erhalten).
c.label=nil
local f=assert(fs.open("/toast.config.lua","w"));f.write(common.configText(c));f.close()
ui.header("Fertig")
print("")
fg(colors.lime);print("Toast Control "..common.version.." installiert");fg(colors.white)
print((role=="turtle" and ("Turtle / "..(job=="farm" and "Farm" or "Mining"))
    or ({controller="Zentrale",pocket="Pocket",repeater="Repeater",info="Infoscreen"})[role])..(c.name~="" and (" / "..c.name) or ""))
if role~="controller" and role~="repeater" then print("Zentrale #"..c.controllerId) end
print(clean and "Komplett neu installiert." or "Update: Einstellungen behalten.")
if resetProgress then print("Neuer Auftrag mit den neuen Massen.") end
ui.hint("Spaeter aendern: toast.lua config")
local checked=common.load()
assert(checked.role==role,"role passt nicht zum erkannten Geraet.")
if role=="turtle" then
    local prefix=checked.job=="farm" and "farm" or "mine"
    dofile("/toast/"..prefix.."_common.lua").load(common.workerConfig(checked))
end
print("")
if ui.yesno("Autostart einrichten?",true) then
    local f=assert(fs.open("/startup.lua","w"));f.write('shell.run("/toast.lua")\n');f.close()
end
if ui.yesno("Jetzt starten?",true) then shell.run("/toast.lua") end
