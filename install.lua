-- TOAST CONTROL 3.17.5 – Ein-Datei-Installer (alle Programme sind hier eingebaut).
local FILES={}
FILES["toast.lua"]=[======[
-- Ein Startprogramm fuer Zentrale, Pocket, Farm, Mining, Holz, Mobs, Repeater und Infoscreen.
-- Neu: Waechter startet das Programm nach einem Absturz automatisch neu.
local common=dofile("/toast/toast_common.lua")
local args={...}

local function runOnce()
    local cfg=common.load()
    -- Name auch im Spiel setzen (steht dann an Turtle/Computer und in der Item-Info).
    if cfg.label~="" and os.setComputerLabel and os.getComputerLabel()~=cfg.label then
        pcall(os.setComputerLabel,cfg.label)
    end
    if cfg.role=="turtle" and (cfg.job=="tree" or cfg.job=="mob" or cfg.job=="dig" or cfg.job=="build") then
        -- Holzfarm / Mobs: eigenes Grundgeruest (toast_worker.lua), liest die Config selbst.
        local nativeRednet=rednet
        local radio={}
        for k,v in pairs(nativeRednet) do radio[k]=v end
        radio.send=function(id,msg,protocol)
            if type(msg)=="table" and msg.kind=="status" then
                msg.label=cfg.label;msg.job=cfg.job;msg.controllerId=cfg.controllerId;msg.toast=common.version
            end
            return nativeRednet.send(id,msg,protocol)
        end
        local env=setmetatable({rednet=radio},{__index=_ENV})
        return assert(loadfile("/toast/"..cfg.job.."_turtle.lua","t",env))(table.unpack(args))
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
                pcall(common.addPosition,msg,cfg,cfg.job)
                -- Abladekisten der Mine: Weltkoordinaten fuer Zentrale/Pocket/Infoscreen
                if type(msg.chestSpots)=="table" then
                    local list={}
                    for i,k in ipairs(msg.chestSpots) do
                        if i>40 then break end
                        local ok,pos,rel=pcall(common.worldPos,cfg,cfg.job,k.x,k.y or 1,k.z)
                        list[#list+1]={n=k.n or i,pos=ok and pos or nil,rel=ok and rel or nil}
                    end
                    msg.chestList=list;msg.chestSpots=nil
                end
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
    local program=({controller="toast_control.lua",pocket="toast_pocket.lua",repeater="repeater.lua",info="toast_info.lua",gps="toast_gps.lua",storage="toast_storage.lua"})[cfg.role]
    return assert(loadfile("/toast/"..program,"t",_ENV))(table.unpack(args))
end

-- Einstellungsmenue: "toast.lua config". "toast.lua neu": neuer Auftrag
-- (Werte eingeben, alter Fortschritt wird geloescht, dann direkt los).
local NEW_JOB="TOAST_NEUER_AUFTRAG"
local function configure(newJob)
    local ui=dofile("/toast/toast_setup.lua").new(common)
    local okc,raw=pcall(dofile,"/toast.config.lua")
    local c=common.withDefaults(okc and type(raw)=="table" and raw or {})
    local role=c.role~="auto" and c.role or (turtle and "turtle" or (pocket and "pocket" or "controller"))
    local job=role=="turtle" and c.job or nil
    if newJob and role~="turtle" then newJob=false end
    local before=ui.layoutKey(c,job)
    while true do
        if not ui.run(c,{role=role,job=job,newJob=newJob}) then print("Abgebrochen, nichts geaendert.");return false end
        local ok,why=pcall(function() common.load(common.copy(c)) end)
        if ok then break end
        printError(tostring(why));sleep(2)
    end
    if role=="turtle" and c.job~=job then
        -- Aufgabe gewechselt (z.B. Mine -> Mobs)
        if not ui.switchJob(job,c.job) then print("Aufgabe nicht gewechselt.");return false end
    elseif newJob then ui.newJob(job)
    elseif before~=ui.layoutKey(c,job) then ui.confirmReset(job) end
    c.role=role;c.label=nil
    local f=assert(fs.open("/toast.config.lua","w"));f.write(common.configText(c));f.close()
    term.clear();term.setCursorPos(1,1)
    print(newJob and "Neuer Auftrag gespeichert. Starte ..." or "Gespeichert. Starte Toast ...")
    return true
end
if args[1]=="config" or args[1]=="--config" or args[1]=="neu" or args[1]=="new" then
    if not configure(args[1]=="neu" or args[1]=="new") then return end
    args={}
end
-- Startargumente wie --dock/--new nur beim ersten Start verwenden.
local restarts,windowStart=0,os.clock()
-- Nach Absturz: true = neu starten, false = aufhoeren
local function afterCrash(why)
    if why=="Terminated" then print("Toast beendet.");return false end
    common.log("Absturz: "..why)
    local okCfg,cfg=pcall(common.load)
    local r=okCfg and cfg.recovery or common.recovery(nil)
    if os.clock()-windowStart>600 then restarts,windowStart=0,os.clock() end
    restarts=restarts+1
    printError(why)
    if not r.autoRestart or restarts>r.maxRestarts then
        print("Kein automatischer Neustart mehr ("..(restarts-1).." in 10 min).")
        print("Fehler steht in /toast/fehler.log. Neustart: toast.lua")
        return false
    end
    print("Automatischer Neustart in "..r.restartDelay.."s ("..restarts.."/"..r.maxRestarts..")")
    print("Beliebige Taste: abbrechen")
    local timer=os.startTimer(r.restartDelay)
    while true do
        local e,a=os.pullEventRaw()
        if e=="timer" and a==timer then return true end
        if e=="key" or e=="terminate" then print("Neustart abgebrochen.");return false end
    end
end
while true do
    local ok,why=pcall(runOnce)
    if ok then return end
    why=tostring(why)
    args={}
    if why:find("TOAST_UPDATE",1,true) then
        -- Neue Version installiert: neues toast.lua laden und weitermachen
        print("Update fertig, starte neu ...")
        local f=loadfile("/toast.lua")
        if f then return f() end
        os.reboot()
    elseif why:find(NEW_JOB,1,true) then
        -- An der Turtle "N" gedrueckt: neuer Auftrag -> Menue, dann neu starten
        configure(true);restarts=0
    elseif not afterCrash(why) then return end
end
]======]
FILES["toast_common.lua"]=[======[
local M={
    version="3.17.5",
    protocol="toast.control.v1", remoteProtocol="toast.control.remote.v1",
    workerProtocols={farm="toast.farm.v2",mining="toast.mine.v1",tree="toast.tree.v1",mob="toast.mob.v1",dig="toast.dig.v1",build="toast.build.v1"},
    legacyRemote={farm="toast.farm.remote.v2",mining="toast.mine.remote.v1"},
    actions={start=true,stop=true,once=true,reset=true,update=true},
    updateUrl="https://raw.githubusercontent.com/dasToast97/toast-control/main/install.lua",
    versionUrl="https://raw.githubusercontent.com/dasToast97/toast-control/main/version.txt",
    shaUrl="https://api.github.com/repos/dasToast97/toast-control/commits/main",
    rawBase="https://raw.githubusercontent.com/dasToast97/toast-control/",
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
-- Aufgaben einer Turtle. JOBS: Reihenfolge in Menues und Anzeigen.
M.JOBS={"farm","mining","tree","mob","dig","build"}
M.JOB_NAMES={farm="Farm",mining="Mine",tree="Holz",mob="Mobs",dig="Aushub",build="Mobfarm-Bau"}
-- Config-Abschnitt und Programmdatei je Aufgabe
M.JOB_SECTION={farm="farm",mining="mine",tree="tree",mob="mob",dig="dig",build="build"}
function M.job(j) return M.JOB_NAMES[j]~=nil end
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
    autoDiscover=true,autoPairPockets=true,devices={},pocketIds={},autoUpdate=true,updateEvery=5,
    display={monitor="auto",size="3x4",textScale=0.5,pageSize=0},
    show="all",
    network={pollInterval=1,staleAfter=15,commandTimeout=10,maxDevices=256},
    recovery={autoRestart=true,restartDelay=5,maxRestarts=5,autoRetry=3,retryDelay=30,moveRetries=8},
    chunkload={enabled=false,chunks=1,idle=false,wakeOnWorldLoad=true,reportEvery=10},
    base={set=false,x=0,y=64,z=0,facing="north",dimension="auto"},
    gps={auto=true,x=0,y=64,z=0,host=true,set=false},
    farm={length=9,width=9,side="right",crop="wheat",interval=60,maxInterval=1200,seedReserve=0,radioTimeout=60,water={}},
    mine={length=100,height=3,tunnels=5,gap=2,side="right",sideDig=false,useCoal=true,placeChests=false,torches=0,drain=false,seal="off",keepOres="",radioTimeout=60,
        fuelTarget=2000,freeSlots=2,digRetries=16,protectedBlocks={}},
    tree={length=24,width=24,side="right",climb=8,maxHeight=32,replant=true,keepSaplings=32,interval=300,
        fuelTarget=2000,radioTimeout=60},
    mob={mode="farm",attack="front",nightOnly=false,length=16,width=16,side="right",climb=8,interval=10,fuelTarget=2000,radioTimeout=0},
    storage={interval=10,warnAt=90,names={}},
    dig={shape="room",direction="down",width=5,length=5,height=8,side="right",seal="liquids",drain=false,keepOres="",
        wallBlock="",lineWalls=true,lineFloor=true,lineCeiling=true,wallStock=256,
        useCoal=true,fuelTarget=2000,freeSlots=2,radioTimeout=60,protectedBlocks={}},
    build={floors=2,drop=22,creeperOnly=true,inTerrain=false,becomeMob=true,fuelTarget=2000,radioTimeout=0},
}
local function copy(v)
    if type(v)~="table" then return v end
    local t={};for k,x in pairs(v) do t[k]=copy(x) end;return t
end
M.copy=copy
local SECTIONS={display=true,network=true,recovery=true,chunkload=true,farm=true,mine=true,tree=true,mob=true,dig=true,build=true,storage=true,base=true,gps=true}
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
local CROP_NAMES={wheat="Weizen",carrots="Karotten",potatoes="Kartoffeln",beetroot="Rote Bete",sugarcane="Zuckerrohr"}
M.CROP_NAMES=CROP_NAMES
function M.configText(c,cap)
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
        if cap then cap[#cap+1]={name=name,title=title,fields=fields} end
        out[#out+1]=""
        out[#out+1]="    -- "..title
        out[#out+1]="    "..name.." = {"
        for _,f in ipairs(fields) do line(8,f[1],q(t[f[1]]),f[2]) end
        out[#out+1]="    },"
    end
    local role,job=c.role,c.job
    local what=role=="turtle" and ("Turtle / "..(M.JOB_NAMES[job] or tostring(job))) or
        ({controller="Zentrale",pocket="Pocket",repeater="Repeater",info="Infoscreen",gps="GPS-Sender",storage="Lager"})[role] or tostring(role)
    out[#out+1]="-- Toast Control "..M.version.." - Einstellungen"
    out[#out+1]="-- Geraet #"..os.getComputerID().." / "..what
    out[#out+1]="-- Aendern im Spiel:  toast.lua config     (oder: edit /toast.config.lua)"
    out[#out+1]="return {"
    line(4,"role",q(role))
    if role=="turtle" then line(4,"job",q(job),"farm, mining, tree, mob oder dig") end
    line(4,"name",q(c.name or ""),"Anzeigename")
    if role=="controller" then line(4,"controllerId",q(c.controllerId),"= ID dieser Zentrale")
    elseif role~="repeater" and role~="gps" then line(4,"controllerId",q(c.controllerId),"ID der Zentrale") end
    if role=="storage" then
        section("storage","Lager: Kisten am Computer / per Netzwerkkabel",{
            {"interval","alle x Sekunden neu auslesen (2-600)"},{"warnAt","ab x % voll orange (50-100)"},
            {"names","eigene Namen: [\"minecraft:chest_3\"] = \"Erze\""}},c.storage)
        section("display","Bildschirm",{
            {"monitor","\"auto\" = alle Monitore, \"terminal\" oder Name"},{"size","Bloecke Hoehe x Breite, z.B. \"3x4\", oder \"auto\""},
            {"textScale","nur ohne size: Schrift 0.5 bis 5"}},c.display)
    end
    if role=="controller" or role=="info" or role=="repeater" or role=="storage" then
        section("gps","Nebenbei GPS-Sender (spart eigene GPS-Computer)",{
            {"host","true = GPS-Anfragen beantworten"},{"set","true = Koordinaten unten stimmen"},
            {"auto","true = beim Start selbst per GPS suchen"},
            {"x","X dieses Computers (F3)"},{"y","Y"},{"z","Z"}},c.gps)
    end
    if role=="gps" then
        section("gps","GPS-Sender: Koordinaten DIESES Computers (F3, Targeted Block)",{
            {"auto","true = beim Start selbst per GPS suchen (wenn schon 4 andere laufen)"},
            {"x","X"},{"y","Y"},{"z","Z"}},c.gps)
    end
    if role=="info" then line(4,"show",q(c.show),"\"all\", \"farm\", \"mining\", \"tree\", \"mob\", \"dig\", \"storage\" (Lager) oder Turtle-ID") end
    if role=="turtle" and job=="mining" then
        section("mine","Mine: Turtle steht an der Basis und schaut in die Mine",{
            {"length","Ganglaenge nach vorne (1-1024)"},{"height","Ganghoehe 1-64 (3, 6, 9 ... sparsam)"},
            {"tunnels","Anzahl Gaenge (1-64)"},{"gap","Bloecke zwischen den Gaengen (0-16)"},
            {"side","Gaenge nach \"right\" oder \"left\""},{"sideDig","nur gap = 0: seitlich mitabbauen"},
            {"useCoal","true = gefundene Kohle direkt als Fuel"},
            {"placeChests","true = Kisten mitnehmen, unterwegs abladen"},
            {"torches","Fackel alle x Bloecke (0 = aus, ab Hoehe 3)"},
            {"drain","true = Wasser/Lava im Gang entfernen"},
            {"seal","\"off\", \"liquids\" Wasser/Lava an der Wand zubauen, \"all\" auch Loecher"},
            {"keepOres","Erze stehen lassen: \"\", \"all\" oder \"diamond,emerald\""},
            {"radioTimeout","s ohne Zentrale bis Stopp (0 = weiter)"},{"fuelTarget","an der Basis bis hierhin tanken"},
            {"freeSlots","so wenige Slots frei -> abladen"},{"digRetries","Versuche bei Kies/Sand"},
            {"protectedBlocks","diese Bloecke nie abbauen"}},c.mine)
    elseif role=="turtle" and job=="tree" then
        section("tree","Holzfaeller: Gebiet vor der Basis, Baeume stehen beliebig",{
            {"length","Gebiet nach vorne (1-128)"},{"width","Gebiet zur Seite (1-128)"},
            {"side","Gebiet \"right\" oder \"left\""},{"climb","max. Hoehe hoch/runter im Gelaende"},
            {"maxHeight","Baeume hoechstens so hoch faellen"},{"replant","true = Setzling nachpflanzen"},
            {"interval","Pause zwischen Runden in s"},
            {"keepSaplings","so viele Setzlinge behalten"},{"fuelTarget","an der Basis bis hierhin tanken"},
            {"radioTimeout","s ohne Zentrale bis Stopp (0 = weiter)"}},c.tree)
    elseif role=="turtle" and job=="mob" then
        section("mob","Mobs: Schwert-Turtle",{
            {"mode","\"farm\" Mobfarm, \"guard\" Wache, \"patrol\" Waechter"},
            {"attack","\"front\", \"up\" (nur oben, Mobfarm-Schacht) oder \"all\""},
            {"nightOnly","true = nur nachts aktiv (18:30-5:30)"},
            {"length","Waechter: Gebiet nach vorne"},{"width","Waechter: Gebiet zur Seite"},
            {"side","Waechter: Gebiet \"right\" oder \"left\""},{"climb","Waechter: max. Hoehe hoch/runter"},
            {"interval","Waechter: Pause an der Basis in s"},
            {"fuelTarget","Waechter: so voll tanken (= so lange unterwegs)"},{"radioTimeout","s ohne Zentrale bis Stopp (0 = weiter)"}},c.mob)
    elseif role=="turtle" and job=="build" then
        section("build","Mobfarm-Bau: Schacht + dunkle Etagen UEBER der Turtle",{
            {"floors","Spawn-Etagen (1-6, je 17x17 innen)"},{"drop","Schachthoehe bis zur Turtle (22 = Mobs fast tot)"},
            {"creeperOnly","true = Falltueren an die Decke: nur Creeper"},
            {"inTerrain","true = im Berg/Gelaende (alles freiraeumen), false = 3D-Drucker"},
            {"becomeMob","true = danach selbst Mob-Turtle (Schwert ins Inventar)"},
            {"fuelTarget","an der Basis mindestens bis hierhin tanken"},
            {"radioTimeout","s ohne Zentrale bis Stopp (0 = weiter)"}},c.build)
    elseif role=="turtle" and job=="dig" then
        section("dig","Aushub: Form direkt VOR der Basis ausheben",{
            {"shape","\"room\" Quader/Schacht, \"cylinder\", \"sphere\" Kugel, \"dome\" Halbkugel"},
            {"direction","\"down\" nach unten oder \"up\" nach oben"},
            {"width","Breite bzw. Durchmesser (1-1024)"},{"length","nur Quader: Laenge nach vorne (1-1024)"},
            {"height","Quader/Zylinder: Hoehe bzw. Tiefe (1-1024)"},
            {"side","Quader: \"right\" oder \"left\" der Basis"},
            {"seal","\"off\", \"liquids\" (Wasser/Lava zubauen), \"all\" (auch Loecher)"},
            {"drain","true = Wasser/Lava im Raum entfernen (unter Wasser/Lava)"},
            {"keepOres","Erze stehen lassen: \"\" keine, \"all\" alle, \"diamond,emerald\""},
            {"wallBlock","Verkleidung, z.B. \"minecraft:stone_bricks\" (Kiste OBEN), \"\" = aus"},
            {"lineWalls","true = Waende verkleiden"},{"lineFloor","true = Boden verkleiden"},
            {"lineCeiling","true = Decke verkleiden"},{"wallStock","so viele Wandbloecke mitnehmen (64-1024)"},
            {"useCoal","true = gefundene Kohle als Fuel"},{"fuelTarget","an der Basis bis hierhin tanken"},
            {"freeSlots","so wenige Slots frei -> abladen"},
            {"radioTimeout","s ohne Zentrale bis Stopp (0 = weiter)"},{"protectedBlocks","diese Bloecke nie abbauen"}},c.dig)
    elseif role=="turtle" then
        section("farm","Feld: Turtle steht an der Basis und schaut aufs Feld",{
            {"length","Feldlaenge nach vorne (1-32)"},{"width","Feldbreite zur Seite (1-32)"},
            {"side","Feld nach \"right\" oder \"left\""},{"crop","wheat, carrots, potatoes, beetroot, sugarcane"},
            {"interval","kuerzeste Pause zwischen Runden in s"},
            {"maxInterval","Spar-Pause: laengste Pause in s (0 = immer interval)"},{"seedReserve","Saatgut behalten (0 = so viel wie das Feld braucht)"},
            {"radioTimeout","s ohne Zentrale bis Stopp (0 = weiter)"},{"water","leer lassen: wird erkannt"}},c.farm)
    end
    if role=="turtle" then
        section("base","Basis-Koordinaten (F3) fuer die Positionsanzeige",{
            {"set","true = Koordinaten unten sind eingetragen"},{"x","X der Turtle an der Basis"},
            {"y","Y der Turtle an der Basis"},{"z","Z der Turtle an der Basis"},
            {"facing","Blick an der Basis: north/east/south/west"},
            {"dimension","\"auto\", \"overworld\", \"nether\" oder \"end\""}},c.base)
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
        line(4,"autoUpdate",q(c.autoUpdate),"neue Version selbst fuer alle installieren")
        line(4,"updateEvery",q(c.updateEvery),"alle x Minuten nachsehen (1-1440)")
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
    assert(({controller=true,turtle=true,pocket=true,repeater=true,info=true,gps=true,storage=true})[c.role],"role: auto/controller/turtle/pocket/repeater/info/gps/storage")
    if c.role=="storage" then
        local s=c.storage
        assert(not turtle and not pocket,"Lager auf einem stationaeren Computer installieren.")
        assert(type(s)=="table" and M.integer(s.interval,2,600) and M.integer(s.warnAt,50,100) and type(s.names)=="table",
            "storage: interval 2-600, warnAt 50-100, names = Tabelle.")
    end
    if c.role=="gps" then
        local g=c.gps
        assert(not turtle and not pocket,"GPS-Sender auf einem stationaeren Computer installieren.")
        assert(type(g)=="table" and type(g.auto)=="boolean","gps.auto: true oder false.")
        assert(M.integer(g.x,-30000000,30000000) and M.integer(g.y,-2048,4096) and M.integer(g.z,-30000000,30000000),"gps: x/y/z ganze Zahlen.")
    end
    if c.role~="gps" and type(c.gps)=="table" and c.gps.set then
        local g=c.gps
        assert(M.integer(g.x,-30000000,30000000) and M.integer(g.y,-2048,4096) and M.integer(g.z,-30000000,30000000),"gps: x/y/z ganze Zahlen.")
    end
    assert(M.id(c.controllerId),"controllerId: ganze ID 0 bis 65500.")
    assert(type(c.autoUpdate)=="boolean" and M.integer(c.updateEvery,1,1440),"autoUpdate true/false, updateEvery 1 bis 1440 Minuten.")
    if c.role=="controller" then assert(os.getComputerID()==c.controllerId,"controllerId stimmt nicht mit Zentralen-ID ueberein.") end
    if c.role=="turtle" then
        assert(turtle and M.job(c.job),"Turtle: job=farm, mining, tree, mob, dig oder build einstellen.")
        if c.job=="tree" then M.checkTree(c.tree) elseif c.job=="mob" then M.checkMob(c.mob) elseif c.job=="dig" then M.checkDig(c.dig) elseif c.job=="build" then M.checkBuild(c.build) end
        assert(os.getComputerID()~=c.controllerId,"Turtle und Zentrale duerfen nicht dieselbe ID haben.")
    end
    if c.role=="pocket" then assert(pocket and os.getComputerID()~=c.controllerId,"Pocket/Zentralen-ID ungueltig.") end
    if c.role=="info" then
        assert(not turtle and not pocket and os.getComputerID()~=c.controllerId,"Infoscreen: eigener Computer, nicht die Zentrale.")
        assert(c.show=="all" or c.show=="storage" or M.job(c.show) or M.id(c.show),"show: \"all\", \"farm\", \"mining\", \"tree\", \"mob\", \"dig\", \"storage\" oder Turtle-ID (Zahl).")
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
    if type(c.base)=="table" then
        c.base.dimension=c.base.dimension or "auto"
        assert(M.DIM_NAMES[c.base.dimension] or c.base.dimension=="auto","base.dimension: auto, overworld, nether oder end.")
    end
    if type(c.base)=="table" and c.base.set then
        local b=c.base
        assert(M.integer(b.x,-30000000,30000000) and M.integer(b.y,-2048,4096) and M.integer(b.z,-30000000,30000000),"base: x/y/z ganze Zahlen.")
        assert(M.FACING[b.facing],"base.facing: north, east, south oder west.")
    end
    -- "name" ist der neue, gut sichtbare Eintrag; "label" bleibt fuer alte Configs gueltig.
    if c.name~=nil then
        assert(type(c.name)=="string","name: Text in Anfuehrungszeichen, z.B. name = \"Mine Nord\"")
        c.label=c.name
    end
    c.label=M.label(c.label);c.name=c.label
    return c
end
-- ===== Position einer Turtle =====
-- Jede Aufgabe zaehlt ab ihrer Basis anders; hier wird daraus "vor/rechts/hoch"
-- und - wenn die Basis-Koordinaten eingetragen sind - echte Weltkoordinaten.
M.FACING={north={0,-1},east={1,0},south={0,1},west={-1,0}}
local RIGHT={north="east",east="south",south="west",west="north"}
function M.position(c,job,x,y,z)
    x,y,z=M.number(x),M.number(y),M.number(z)
    local sec=c[M.JOB_SECTION[job] or "mine"] or {}
    local sign=sec.side=="left" and -1 or 1
    local rel={fwd=z,right=x*sign,up=job=="mining" and -y or (job=="farm" and 0 or y)}
    local abs
    local b=c.base
    if type(b)=="table" and b.set and M.FACING[b.facing] then
        local f,r=M.FACING[b.facing],M.FACING[RIGHT[b.facing]]
        abs={x=b.x+f[1]*rel.fwd+r[1]*rel.right,y=b.y+rel.up,z=b.z+f[2]*rel.fwd+r[2]*rel.right}
    end
    return rel,abs
end
-- ===== GPS =====
-- Echte GPS-Abfrage kostet Zeit (Funk). Darum: zwei GPS-Messungen an verschiedenen
-- Stellen reichen, um Basis und Blickrichtung auszurechnen ("kalibriert"). Danach
-- werden die Koordinaten bei JEDER Statusmeldung (jede Sekunde) aus der eigenen
-- Bewegung berechnet, und GPS prueft nur noch alle 10 s nach.
local gpsAt,gpsMiss=-1e9,0
local anchors={}
local cal=nil                 -- {x,y,z,facing}
M.FACES={"north","east","south","west"}
local function rot(facing,rel)
    local f,r=M.FACING[facing],M.FACING[RIGHT[facing]]
    return f[1]*rel.fwd+r[1]*rel.right,rel.up,f[2]*rel.fwd+r[2]*rel.right
end
local function calibrate(a,b)
    if a.rel.fwd==b.rel.fwd and a.rel.right==b.rel.right then return end
    for _,face in ipairs(M.FACES) do
        local ax,ay,az=rot(face,a.rel);local bx,by,bz=rot(face,b.rel)
        local okx=math.abs((b.fix.x-a.fix.x)-(bx-ax))<=1
        local okz=math.abs((b.fix.z-a.fix.z)-(bz-az))<=1
        local oky=math.abs((b.fix.y-a.fix.y)-(by-ay))<=1
        if okx and oky and okz then
            cal={x=b.fix.x-bx,y=b.fix.y-by,z=b.fix.z-bz,facing=face}
            return
        end
    end
end
function M.gpsCalibration() return cal end
function M.gpsReset() cal=nil;anchors={};gpsAt=-1e9;gpsMiss=0 end
local function locate()
    if not gps or not gps.locate then return nil end
    local wait=cal and 10 or (gpsMiss>=3 and 60 or 3)
    if os.clock()-gpsAt<wait then return nil end
    gpsAt=os.clock()
    local ok,x,y,z=pcall(gps.locate,0.3)
    if not ok or not x then gpsMiss=gpsMiss+1;return nil end
    gpsMiss=0
    return {x=math.floor(x+0.5),y=math.floor(y+0.5),z=math.floor(z+0.5)}
end
-- Liefert aktuelle Koordinaten (live) oder nil
function M.gpsPosition(rel)
    local fix=locate()
    if fix and rel then
        local a={fix=fix,rel={fwd=rel.fwd,right=rel.right,up=rel.up}}
        if cal then
            -- Kontrolle: passt die Rechnung noch? Sonst neu kalibrieren.
            local x,y,z=rot(cal.facing,rel)
            if math.abs(cal.x+x-fix.x)>1 or math.abs(cal.y+y-fix.y)>1 or math.abs(cal.z+z-fix.z)>1 then cal=nil;anchors={} end
        end
        if not cal then
            for _,o in ipairs(anchors) do calibrate(o,a);if cal then break end end
            anchors[#anchors+1]=a;while #anchors>6 do table.remove(anchors,1) end
        end
    end
    if cal and rel then
        local x,y,z=rot(cal.facing,rel)
        return {x=cal.x+x,y=cal.y+y,z=cal.z+z,live=true}
    end
    -- noch nicht kalibriert: letzte Messung gilt, solange sie sich nicht bewegt hat
    local last=anchors[#anchors]
    if last and rel and last.rel.fwd==rel.fwd and last.rel.right==rel.right and last.rel.up==rel.up then return last.fix end
    return nil
end
-- ===== Nebenbei GPS-Sender (Zentrale, Infoscreens, Repeater) =====
-- Stationaere Toast-Computer beantworten GPS-Anfragen mit, so braucht man
-- weniger eigene GPS-Computer. Koordinaten aus der Config (gps.set) oder
-- beim Start selbst per GPS (wenn schon 4 andere Sender laufen).
local GPS_CH=65534
function M.gpsHost(c,quiet)
    local g=c.gps
    if type(g)~="table" or g.host==false or turtle or pocket then return nil,"aus" end
    if not g.set and g.auto and gps and gps.locate then
        if not quiet then print("GPS: suche eigene Position ...") end
        local ok,x,y,z=pcall(gps.locate,2)
        if not (ok and x) and not quiet then
            if term.isColor and term.isColor() then term.setTextColor(colors.orange) end
            print("GPS: keine Position gefunden (normal,")
            print("solange es keine 4 GPS-Sender gibt).")
            print("Laeuft trotzdem, nur ohne GPS-Senden.")
            print("Eintragen: Strg+T halten, dann")
            print("  toast.lua config  -> GPS")
            print("Koordinaten: F3 auf diesen Computer")
            print("schauen ('Targeted Block').")
            if term.isColor and term.isColor() then term.setTextColor(colors.white) end
        end
        if ok and x then
            g.x,g.y,g.z,g.set=math.floor(x+0.5),math.floor(y+0.5),math.floor(z+0.5),true
            pcall(function()
                local raw=dofile("/toast.config.lua");local cc=M.withDefaults(raw)
                cc.gps.x,cc.gps.y,cc.gps.z,cc.gps.set=g.x,g.y,g.z,true;cc.label=nil
                local f=fs.open("/toast.config.lua","w");f.write(M.configText(cc));f.close()
            end)
        end
    end
    if not g.set then return nil,"Koordinaten fehlen (toast.lua config -> GPS)" end
    local h={x=g.x,y=g.y,z=g.z,served=0}
    local function open()
        for _,name in ipairs(peripheral.getNames()) do
            if peripheral.getType(name)=="modem" then
                local m=peripheral.wrap(name)
                if m and m.isWireless and m.isWireless() then pcall(m.open,GPS_CH) end
            end
        end
    end
    open()
    -- Mit jedem Ereignis des Programms aufrufen; true = war eine GPS-Anfrage
    function h.event(e,side,ch,reply,msg,dist)
        if e=="modem_message" and ch==GPS_CH and msg=="PING" and dist then
            local m=peripheral.wrap(side)
            if m then pcall(m.transmit,reply,GPS_CH,{h.x,h.y,h.z});h.served=h.served+1 end
            return true
        elseif e=="peripheral" then open() end
        return false
    end
    return h
end
-- ===== Netzgeraete (Repeater, GPS-Sender, Infoscreens, Pockets) =====
-- Melden sich bei der Zentrale mit Name, Version und Position.
local myPosAt,myPos=-1e9,nil
function M.myPos(c)
    if type(c.gps)=="table" and c.gps.set then return {x=c.gps.x,y=c.gps.y,z=c.gps.z,src="Config"} end
    if os.clock()-myPosAt<60 then return myPos end
    myPosAt=os.clock()
    if gps and gps.locate then
        local ok,x,y,z=pcall(gps.locate,0.3)
        myPos=(ok and x) and {x=math.floor(x+0.5),y=math.floor(y+0.5),z=math.floor(z+0.5),src="GPS"} or nil
    end
    return myPos
end
function M.nodeInfo(c,role,stats)
    return {name=c.label or c.name or "",role=role,toast=M.version,pos=M.myPos(c),stats=stats}
end
-- Repeater/GPS-Sender: Status an die Zentrale(n) funken (alle 10 s)
function M.nodeBeacon(c,role,stats)
    pcall(rednet.broadcast,{kind="node",version=1,controllerId=c.controllerId or 0,info=M.nodeInfo(c,role,stats)},M.remoteProtocol)
end
-- Update-Befehl fuer Netzgeraete pruefen
function M.isUpdateFor(c,sender,b)
    return type(b)=="table" and b.kind=="update" and ((c.controllerId or 0)==0 or b.controllerId==c.controllerId or sender==c.controllerId)
end
-- ===== Dimension =====
-- CC kennt keine Dimension; erkannt wird sie an den Bloecken um die Turtle
-- (Netherrack = Nether, Endstein = End, Stein/Erde = Oberwelt). Eingetragene
-- Dimension (base.dimension) gilt, solange nichts Eindeutiges zu sehen ist.
M.DIM_NAMES={overworld="Oberwelt",nether="Nether",["end"]="End"}
local NETHER={"netherrack","basalt","blackstone","soul_sand","soul_soil","nether_","crimson_","warped_",
    "magma_block","glowstone","ancient_debris","quartz_ore","shroomlight","nylium"}
local END={"end_stone","purpur","chorus"}
local OVER={"minecraft:stone","deepslate","minecraft:dirt","grass_block","minecraft:sand","gravel","granite","diorite",
    "andesite","tuff","calcite","sandstone","clay","_log","leaves","coal_ore","iron_ore","copper_ore","gold_ore",
    "diamond_ore","redstone_ore","lapis_ore","emerald_ore","minecraft:water","snow","moss","podzol","mud"}
local function has(list,name) for _,p in ipairs(list) do if name:find(p,1,true) then return true end end;return false end
function M.dimensionOf(name)
    if type(name)~="string" then return nil end
    if has(NETHER,name) then return "nether" end
    if has(END,name) then return "end" end
    if name=="minecraft:bedrock" or name:find("lava",1,true) then return nil end
    if has(OVER,name) then return "overworld" end
    return nil
end
local dimSeen,dimAt,dimCheck=nil,-1e9,-1e9
-- Hoechstens alle 20 s kurz oben/unten/vorne nachsehen (kostet kein Fuel)
function M.senseDimension()
    if not turtle or os.clock()-dimCheck<20 then return dimSeen end
    dimCheck=os.clock()
    local votes={}
    for _,fn in ipairs({turtle.inspectDown,turtle.inspectUp,turtle.inspect}) do
        local ok,e,b=pcall(fn)
        if ok and e and type(b)=="table" then
            local d=M.dimensionOf(b.name);if d then votes[d]=(votes[d] or 0)+1 end
        end
    end
    local best,n=nil,0
    for d,v in pairs(votes) do if v>n then best,n=d,v end end
    if best then dimSeen,dimAt=best,os.clock() end
    return dimSeen
end
-- Status einer Turtle um Positionsangaben ergaenzen
-- Weltkoordinaten einer Stelle (Turtle-Koordinaten x,y,z): per GPS-Kalibrierung,
-- sonst aus den eingetragenen Basis-Koordinaten. nil = unbekannt.
function M.worldPos(c,job,x,y,z)
    local rel,abs=M.position(c,job,x,y,z)
    if cal then
        local dx,dy,dz=rot(cal.facing,rel)
        return {x=cal.x+dx,y=cal.y+dy,z=cal.z+dz,src="GPS"},rel
    end
    if abs then abs.src="Basis" end
    return abs,rel
end
function M.addPosition(msg,c,job)
    if type(msg)~="table" or msg.x==nil then return msg end
    local rel,abs=M.position(c,job,msg.x,msg.y,msg.z)
    msg.rel=rel;msg.pos=abs
    local g=M.gpsPosition(rel);if g then msg.gps=g end
    local seen=M.senseDimension()
    local set=type(c.base)=="table" and M.DIM_NAMES[c.base.dimension] and c.base.dimension or nil
    msg.dim=seen or set
    msg.dimSeen=seen~=nil
    msg.dimSet=set
    return msg
end
-- ===== Selbst-Update (Update-Knopf an der Zentrale) =====
-- Laedt den Installer von GitHub und fuehrt ihn ohne Fragen aus ("auto"):
-- Config, Fortschritt und Autostart bleiben. Danach Neustart des Programms
-- (error "TOAST_UPDATE" -> toast.lua laedt sich neu). Turtles machen dank
-- gespeicherter Position und Auftrag dort weiter, wo sie waren.
-- Versionen vergleichen ("3.2.1" > "3.2")
function M.newer(a,b)
    local function parts(v) local t={};for n in tostring(v):gmatch("%d+") do t[#t+1]=tonumber(n) end;return t end
    local x,y=parts(a),parts(b)
    for i=1,math.max(#x,#y) do
        local p,q=x[i] or 0,y[i] or 0
        if p~=q then return p>q end
    end
    return false
end
-- Neueste Version auf GitHub (kleine Datei, schnell)
function M.remoteVersion()
    if not http then return nil,"HTTP aus" end
    local ok,h=pcall(http.get,M.versionUrl.."?t="..math.floor((os.epoch and os.epoch("utc") or 0)/1000))
    if not ok or not h then return nil,"nicht erreichbar" end
    local v=h.readAll();h.close()
    v=tostring(v or ""):match("[%d%.]+")
    return v
end
-- Versionen vergleichen: "3.2.1" > "3.2"
function M.newer(a,b)
    local function parts(v) local t={};for n in tostring(v):gmatch("%d+") do t[#t+1]=tonumber(n) end;return t end
    local x,y=parts(a),parts(b)
    for i=1,math.max(#x,#y) do
        local p,q=x[i] or 0,y[i] or 0
        if p~=q then return p>q end
    end
    return false
end
-- Aktuelle Datei ohne GitHub-Zwischenspeicher: Commit-Kennung (SHA) holen
-- und die Datei genau dieses Stands laden. Klappt das nicht: normaler Link.
function M.freshUrl(file,try)
    local ok,h=pcall(http.get,M.shaUrl,{["Accept"]="application/vnd.github.sha",["User-Agent"]="toast-control"})
    if ok and h then
        local sha=tostring(h.readAll() or ""):match("^%s*(%x+)%s*$");h.close()
        if sha and #sha==40 then return M.rawBase..sha.."/"..file end
    end
    return M.rawBase.."main/"..file.."?t="..math.floor((os.epoch and os.epoch("utc") or 0)/1000)..(try or "")
end
-- want = Version, die die Zentrale erwartet. GitHub liefert nach einem neuen
-- Stand manchmal noch ein paar Minuten die alte Datei aus dem Zwischenspeicher:
-- dann bis zu 3x nachladen, sonst NICHT die alte Version installieren
-- (die Zentrale schickt das Update spaeter nochmal).
function M.selfUpdate(statusFn,want)
    local say=statusFn or function() end
    if not http then return false,"HTTP im Spiel/Server aus" end
    want=type(want)=="string" and want:match("^[%d%.]+$") or nil
    local code
    for try=1,3 do
        say("Update","Lade neue Version ..."..(try>1 and (" (Versuch "..try..")") or ""))
        local ok,h=pcall(http.get,M.freshUrl("install.lua",try))
        if not ok or not h then return false,"Download fehlgeschlagen" end
        code=h.readAll();h.close()
        if type(code)~="string" or #code<1000 then return false,"Download leer" end
        local got=code:match("^%-%- TOAST CONTROL ([%d%.]+)")
        -- nie auf eine aeltere Version zurueck (alte Datei aus GitHubs Zwischenspeicher)
        if got and M.newer(M.version,got) then
            if try==3 then return false,"GitHub liefert alte v"..got..", diese hat v"..M.version end
        elseif not want or not got or not M.newer(want,got) then break end
        if try==3 then return false,"GitHub liefert noch v"..got.." statt v"..want..", spaeter nochmal" end
        sleep(10)
    end
    local fn,why=load(code,"@install","t",_ENV)
    if not fn then return false,"Installer defekt: "..tostring(why) end
    say("Update","Installiere ...")
    local okRun,res=pcall(fn,"auto","intern")
    if not okRun then return false,"Update: "..tostring(res) end
    M.log("Update installiert, Neustart")
    error("TOAST_UPDATE",0)
end
function M.checkTree(t)
    assert(type(t)=="table","tree fehlt.")
    assert(M.integer(t.length,1,128) and M.integer(t.width,1,128),"tree.length/width: 1 bis 128.")
    if t.side=="both" then t.side="right" end
    assert(t.side=="right" or t.side=="left","tree.side: right oder left.")
    assert(M.integer(t.climb,1,32),"tree.climb: 1 bis 32.")
    assert(type(t.replant)=="boolean","tree.replant: true oder false.")
    assert(M.integer(t.interval,0,86400),"tree.interval: 0 bis 86400 s.")
    assert(M.integer(t.maxHeight,4,64),"tree.maxHeight: 4 bis 64.")
    assert(M.integer(t.keepSaplings,1,256),"tree.keepSaplings: 1 bis 256.")
    assert(M.integer(t.fuelTarget,100,100000),"tree.fuelTarget: 100 bis 100000.")
    assert(t.radioTimeout==0 or M.integer(t.radioTimeout,10,300),"tree.radioTimeout: 0 oder 10 bis 300.")
    return t
end
function M.checkMob(m)
    assert(type(m)=="table","mob fehlt.")
    assert(m.mode=="farm" or m.mode=="guard" or m.mode=="patrol","mob.mode: farm, guard oder patrol.")
    assert(m.attack=="front" or m.attack=="all" or m.attack=="up","mob.attack: front, up oder all.")
    assert(M.integer(m.length,2,64) and M.integer(m.width,1,64),"mob.length 2-64, mob.width 1-64.")
    assert(M.integer(m.climb,1,32),"mob.climb: 1 bis 32.")
    assert(type(m.nightOnly)=="boolean","mob.nightOnly: true oder false.")
    assert(m.side=="right" or m.side=="left","mob.side: right oder left.")
    assert(M.integer(m.interval,0,86400),"mob.interval: 0 bis 86400 s.")
    assert(M.integer(m.fuelTarget,100,100000),"mob.fuelTarget: 100 bis 100000.")
    assert(m.radioTimeout==0 or M.integer(m.radioTimeout,10,300),"mob.radioTimeout: 0 oder 10 bis 300.")
    return m
end
function M.checkBuild(b)
    assert(type(b)=="table","build fehlt.")
    assert(M.integer(b.floors,1,6),"build.floors: 1 bis 6 Etagen.")
    assert(M.integer(b.drop,4,60),"build.drop: Schachthoehe 4 bis 60.")
    assert(type(b.creeperOnly)=="boolean" and type(b.becomeMob)=="boolean" and type(b.inTerrain)=="boolean","build.creeperOnly/inTerrain/becomeMob: true oder false.")
    assert(M.integer(b.fuelTarget,100,100000),"build.fuelTarget: 100 bis 100000.")
    assert(b.radioTimeout==0 or M.integer(b.radioTimeout,10,300),"build.radioTimeout: 0 oder 10 bis 300.")
    return b
end
M.DIG_SHAPES={room="Quader",cylinder="Zylinder",sphere="Kugel",dome="Halbkugel"}
function M.checkDig(d)
    assert(type(d)=="table","dig fehlt.")
    assert(M.DIG_SHAPES[d.shape],"dig.shape: room, cylinder, sphere oder dome.")
    assert(d.direction=="down" or d.direction=="up","dig.direction: down oder up.")
    assert(M.integer(d.width,1,1024) and M.integer(d.length,1,1024) and M.integer(d.height,1,1024),"dig: width/length/height 1-1024.")
    assert(d.side=="right" or d.side=="left","dig.side: right oder left.")
    assert(d.seal=="off" or d.seal=="liquids" or d.seal=="all","dig.seal: off, liquids oder all.")
    assert(type(d.drain)=="boolean" and type(d.useCoal)=="boolean","dig.drain/useCoal: true oder false.")
    assert(type(d.wallBlock)=="string" and (d.wallBlock=="" or d.wallBlock:match("^[%w_%.%-]+:[%w_%./%-]+$")),
        "dig.wallBlock: \"\" oder Blockname wie \"minecraft:stone_bricks\".")
    assert(type(d.lineWalls)=="boolean" and type(d.lineFloor)=="boolean" and type(d.lineCeiling)=="boolean",
        "dig.lineWalls/lineFloor/lineCeiling: true oder false.")
    assert(M.integer(d.wallStock,64,1024),"dig.wallStock: 64 bis 1024.")
    assert(type(d.keepOres)=="string","dig.keepOres: Text, z.B. \"\", \"all\" oder \"diamond,emerald\".")
    assert(M.integer(d.fuelTarget,100,100000),"dig.fuelTarget: 100 bis 100000.")
    assert(M.integer(d.freeSlots,1,8),"dig.freeSlots: 1 bis 8.")
    assert(d.radioTimeout==0 or M.integer(d.radioTimeout,10,300),"dig.radioTimeout: 0 oder 10 bis 300.")
    assert(type(d.protectedBlocks)=="table","dig.protectedBlocks muss eine Liste sein.")
    return d
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
-- ===== Live-Funk der Turtles =====
-- Laeuft nebenher (eigener Ablauf neben der Arbeit): sendet den Status SOFORT,
-- wenn sich etwas aendert (hoechstens alle 0,3 s), sonst alle 2 s als Lebenszeichen.
-- Mit Chunkloader (Werkzeug und Modem teilen sich eine Seite) wird das Modem nur
-- an sicheren Stellen im Arbeitsablauf kurz angelegt (L.point): Senden, auf die
-- sofortige Antwort der Zentrale warten (meist < 0,2 s), weiter.
-- o = {snapshot=fn, transmit=fn(snap), gear=G|nil, every=s, contact=fn()->Zeit,
--      onWindow=fn(ok)|nil, tick=fn|nil}
local SKIP={contactAge=true,wait=true,pollToken=true,window=true}
function M.signature(s)
    local keys={}
    for k,v in pairs(s) do if not SKIP[k] and type(v)~="table" and type(v)~="function" then keys[#keys+1]=k end end
    table.sort(keys)
    local out={}
    for i,k in ipairs(keys) do out[i]=k.."="..tostring(s[k]) end
    -- Listen (z.B. Abladekisten) nur ueber ihre Laenge
    for k,v in pairs(s) do if type(v)=="table" and not SKIP[k] then out[#out+1]=k.."#"..#v end end
    return table.concat(out,";")
end
function M.live(o)
    local L={due=false,lastWindow=os.clock(),every=math.max(1,o.every or 3),lastSent=-1e9}
    local lastSig
    local function snapshot()
        local snap=o.snapshot()
        if o.run then
            if o.run.mode~="off" and o.run.manual then o.run.manual=nil;o.run.manualMsg=nil end
            M.manualInfo(o.run,snap)
        end
        return snap
    end
    function L.send(window)
        local snap=snapshot()
        if window then snap.window=true end
        L.lastSent=os.clock();lastSig=M.signature(snap)
        pcall(o.transmit,snap)
    end
    local function modemOn() return not o.gear or peripheral.getType(o.gear.other)=="modem" end
    -- im Arbeitsablauf aufrufen (vor Bewegungen): kurzes Funkfenster, wenn faellig
    function L.point()
        if not o.gear or not L.due then return end
        L.due=false;L.lastWindow=os.clock()
        if not modemOn() and not o.gear.radio() then return end
        local t0=os.clock()
        L.send(true)
        while os.clock()-t0<1 and (o.contact() or 0)<t0 do sleep(0.05) end
        if o.onWindow then o.onWindow((o.contact() or 0)>=t0) end
    end
    function L.loop()
        local lastRefresh=-1e9
        while true do
            local now=os.clock()
            if now-lastRefresh>=2 then
                lastRefresh=now
                if o.tick then pcall(o.tick) end
                pcall(M.refreshModems)
            end
            if modemOn() then
                local snap=snapshot();local sig=M.signature(snap)
                if (sig~=lastSig and now-L.lastSent>=0.3) or now-L.lastSent>=2 then
                    L.lastSent=now;lastSig=sig;pcall(o.transmit,snap)
                end
            elseif now-L.lastWindow>=L.every then L.due=true end
            sleep(TOAST_LIVE_STEP or 0.2)
        end
    end
    return L
end
-- ===== Fernsteuerung der Turtles (von Zentrale / Pocket) =====
-- Auswahlwerte fuer Texteinstellungen (Rest: Zahl, ja/nein oder freier Text)
M.FIELD_OPTIONS={side={"right","left"},crop={"wheat","carrots","potatoes","beetroot","sugarcane"},
    mode={"farm","guard","patrol"},attack={"front","up","all"},shape={"room","cylinder","sphere","dome"},
    direction={"down","up"},seal={"off","liquids","all"},facing={"north","east","south","west"},
    dimension={"auto","overworld","nether","end"}}
-- Felder, die die Form/den Auftrag aendern (dann nur an der Basis + Fortschritt neu)
M.LAYOUT_FIELDS={mining={"length","height","tunnels","gap","side","sideDig"},farm={"length","width","side","crop"},
    tree={"length","width","side"},mob={"mode","length","width","side"},dig={"shape","width","length","height","side","direction"},
    build={"floors","drop","creeperOnly","inTerrain"}}
M.STATE_FILES={farm="/toast_farm_state",mining="/toast_mining_state",tree="/toast_tree_state",mob="/toast_mob_state",
    dig="/toast_dig_state",build="/toast_build_state"}
-- Einstellungen einer Turtle fuer die Anzeige: Abschnitte mit Feld, Text, Wert, Auswahl
function M.remoteConfig(c)
    local cap={}
    c=M.copy(c);if c.role==nil or c.role=="auto" then c.role="turtle" end
    pcall(M.configText,c,cap)
    local secs={}
    for _,sec in ipairs(cap) do
        if sec.name==M.JOB_SECTION[c.job] or sec.name=="chunkload" or sec.name=="base" then
            local t=c[sec.name] or {}
            local fields={}
            for _,f in ipairs(sec.fields) do
                local v=t[f[1]]
                if type(v)=="number" or type(v)=="boolean" or type(v)=="string" then
                    fields[#fields+1]={k=f[1],d=f[2],v=v,o=type(v)=="string" and M.FIELD_OPTIONS[f[1]] or nil}
                end
            end
            secs[#secs+1]={name=sec.name,title=sec.title,fields=fields}
        end
    end
    return {job=c.job,name=c.name or "",jobs=M.JOBS,sections=secs}
end
-- Turtle-Config pruefen wie der Installer (inkl. Farm/Mine-Pruefung)
function M.validateTurtle(c)
    M.load(M.copy(c))
    if c.job=="farm" or c.job=="mining" then
        local prefix=c.job=="farm" and "farm" or "mine"
        dofile("/toast/"..prefix.."_common.lua").load(M.workerConfig(M.copy(c)))
    end
end
-- Neue Werte uebernehmen. o.atHome(): steht an der Basis; o.stopped(): steht still.
function M.applyRemoteConfig(p,o)
    if not o.stopped() then return false,"Erst stoppen, dann speichern." end
    local okr,raw=pcall(dofile,"/toast.config.lua")
    if not okr or type(raw)~="table" then return false,"Config nicht lesbar" end
    local c=M.withDefaults(raw)
    if c.role==nil or c.role=="auto" then c.role="turtle" end      -- sonst fehlen beim Schreiben die Abschnitte
    local oldJob=c.job
    local before=M.copy(c)
    if type(p.name)=="string" then c.name=M.label(p.name) end
    if type(p.job)=="string" and M.job(p.job) then c.job=p.job end
    if type(p.values)=="table" then
        for sn,vals in pairs(p.values) do
            local sec=c[sn]
            if type(sec)=="table" and type(vals)=="table" and (sn==M.JOB_SECTION[c.job] or sn=="chunkload" or sn=="base") then
                for k,v in pairs(vals) do
                    if sec[k]~=nil and type(sec[k])==type(v) and type(v)~="table" then sec[k]=v end
                end
            end
        end
    end
    -- Form/Auftrag geaendert?
    local layout=c.job~=oldJob
    local sec=M.JOB_SECTION[c.job]
    for _,k in ipairs(M.LAYOUT_FIELDS[c.job] or {}) do
        if c.job==oldJob and tostring(before[sec][k])~=tostring(c[sec][k]) then layout=true end
    end
    if layout and not o.atHome() then return false,"Masse/Aufgabe nur an der Basis aendern: erst stoppen und heimfahren lassen." end
    c.label=nil
    local ok,why=pcall(M.validateTurtle,c)
    if not ok then return false,tostring(why):gsub("^[^:]*:%d+: ","") end
    local f=fs.open("/toast.config.lua","w");if not f then return false,"Config nicht schreibbar" end
    f.write(M.configText(c));f.close()
    if layout then
        for _,j in ipairs({oldJob,c.job}) do
            local file=M.STATE_FILES[j]
            if file then for _,pp in ipairs({file,file..".tmp"}) do if fs.exists(pp) then fs.delete(pp) end end end
        end
    end
    M.log("Einstellungen per Funk geaendert"..(layout and " (neuer Auftrag)" or ""))
    return true,layout and "Gespeichert - neuer Auftrag, Turtle startet neu" or "Gespeichert - Turtle startet neu"
end
-- Werkzeuge, Modems, Chunkloader, Brennstoff: nicht zum Bauen verwenden
function M.isGearItem(n)
    n=tostring(n)
    for _,p in ipairs({"_pickaxe","_sword","_axe","_shovel","_hoe","modem","chunkloader","minecraft:coal","charcoal","bucket"}) do
        if n:find(p,1,true) then return true end
    end
    return false
end
-- Werkzeug-Namen (links/rechts) fuer die Fernsteuerung
local function equipped(side)
    local fn=turtle and (side=="left" and turtle.getEquippedLeft or turtle.getEquippedRight)
    if fn then local ok,it=pcall(fn);if ok and type(it)=="table" and it.name then return it.name end end
    local t=peripheral.getType(side)
    return t
end
-- Zusatzwerte im Status, solange ferngesteuert wird
function M.manualInfo(run,snap)
    if not (run.manual or run.manualMsg or run.parked) then return end
    snap.manual=run.manual==true;snap.mMsg=run.manualMsg;snap.parked=run.parked==true
    if run.manual and turtle then
        local function look(fn) local ok,e,b=pcall(fn);if ok and e and type(b)=="table" then return b.name end;return "Luft" end
        snap.mFront=look(turtle.inspect);snap.mUp=look(turtle.inspectUp);snap.mDown=look(turtle.inspectDown)
        snap.mLeft=equipped("left");snap.mRight=equipped("right")
        if run.blockInfo then local ok,n,c=pcall(run.blockInfo);if ok then snap.mBlock,snap.mBlockN=n,c end end
    end
end
-- Empfang + Ausfuehrung. o = {cfg,job,st,run,save,transmit(msg),ops={op=fn},atHome,stopped}
-- handle(b) im Funk-Ablauf aufrufen; loop() als eigenen Ablauf mitlaufen lassen
-- (fuehrt die Schritte aus, damit der Funk dabei nicht blockiert).
function M.remoteControl(o)
    local R={queue={}}
    local NAMES={forward="Vor",back="Zurueck",up="Hoch",down="Runter",left="Links drehen",right="Rechts drehen",
        dig="Abbauen vorne",digUp="Abbauen oben",digDown="Abbauen unten",attack="Angriff vorne",attackUp="Angriff oben",
        attackDown="Angriff unten",place="Setzen vorne",placeUp="Setzen oben",placeDown="Setzen unten",
        use="Abbau/Angriff vorne",useUp="Abbau/Angriff oben",useDown="Abbau/Angriff unten",nextblock="Naechster Block"}
    local function sendConfig(ok,msg)
        local okc,raw=pcall(dofile,"/toast.config.lua")
        local c=okc and type(raw)=="table" and M.withDefaults(raw) or o.cfg
        local cf=M.remoteConfig(c)
        pcall(o.transmit,{kind="config",version=1,id=os.getComputerID(),config=cf,ok=ok,msg=msg})
    end
    o.run.parked=o.st.parked==true or nil      -- geparkt (Fernsteuerung) - auch nach Neustart
    function R.handle(b)
        if type(b)~="table" or b.kind~="remote" or not M.serial(b.serial) or type(b.payload)~="table" then return false end
        o.run.lastContact=os.clock()
        if b.serial<=(o.st.commandSerial or 0) then return true end
        o.st.commandSerial=b.serial;pcall(o.save)
        R.queue[#R.queue+1]=b.payload
        os.queueEvent("toast_remote")
        return true
    end
    local function run1(p)
        local run=o.run
        local op=p.op
        if op=="getconfig" then sendConfig(nil,nil)
        elseif op=="setconfig" then
            local ok,msg=M.applyRemoteConfig(p,o)
            sendConfig(ok,msg)
            if ok then sleep(0.5);error("TOAST_UPDATE",0) end
        elseif op=="manual_on" then
            if run.mode~="off" then run.manualMsg="Erst stoppen, dann steuern"
            elseif run.recovery then run.manualMsg="Position unklar: erst an die Basis setzen"
            else run.manual=true;run.manualMsg="Fernsteuerung an";o.st.parked=nil;run.parked=nil;pcall(o.save) end
        elseif op=="manual_off" or op=="gohome" then
            -- zurueck zur Basis (idle faehrt heim)
            run.manual=nil;o.st.parked=nil;run.parked=nil;pcall(o.save)
            run.manualMsg="Faehrt zur Basis"
        elseif op=="manual_park" then
            -- Steuerung aus, aber hier stehen bleiben (auch nach Neustart)
            run.manual=nil;o.st.parked=true;run.parked=true;pcall(o.save)
            run.manualMsg="Bleibt hier stehen"
        elseif o.ops[op] then
            if not run.manual then run.manualMsg="Erst 'Steuern' einschalten"
            else
                local ok,why=o.ops[op]()
                run.manualMsg=(ok and "" or "Geht nicht: ")..(NAMES[op] or op)..((not ok and why) and (" - "..tostring(why)) or "")
            end
        end
    end
    function R.loop()
        while true do
            if #R.queue==0 then os.pullEvent("toast_remote") end
            local p=table.remove(R.queue,1)
            if p then
                local ok,why=pcall(run1,p)
                if not ok then
                    if tostring(why):find("TOAST_UPDATE",1,true) then error(why,0) end
                    o.run.manualMsg="Fehler: "..tostring(why)
                end
                -- Chunkloader: Werkzeug und Modem teilen sich eine Seite -> Modem
                -- gleich wieder anlegen, sonst kommt der naechste Befehl nicht an
                if o.gear and o.gear() then pcall(o.gear().radio) end
                if o.send then pcall(o.send) end
            end
        end
    end
    return R
end
-- Standard-Schritte fuer die Fernsteuerung. m = {move(kind) -> ok,why (mitgezaehlt),
-- turn(left) -> ok,why, tool=fn|nil (Werkzeug wieder anlegen), noVertical=true}
function M.manualOps(m)
    local function withTool(fn)
        return function()
            local ok,why=fn()
            if not ok and tostring(why):find("No tool",1,true) and m.tool and m.tool() then ok,why=fn() end
            if not ok and why==nil then why="nichts da" end
            return ok,why
        end
    end
    local ops={
        forward=function() return m.move("forward") end,
        back=function() return m.move("back") end,
        left=function() return m.turn(true) end,
        right=function() return m.turn(false) end,
        dig=withTool(turtle.dig),digUp=withTool(turtle.digUp),digDown=withTool(turtle.digDown),
        attack=withTool(turtle.attack),attackUp=withTool(turtle.attackUp),attackDown=withTool(turtle.attackDown),
    }
    -- Leertaste & Co.: je nach Werkzeug abbauen oder angreifen
    -- (Schwert -> erst angreifen; sonst Block da -> abbauen, kein Block -> angreifen)
    local function sword() return tostring(equipped("left")):find("sword",1,true) or tostring(equipped("right")):find("sword",1,true) end
    local function smart(detect,dig,attack)
        return function()
            if sword() then
                local ok,why=ops[attack]();if ok then return true end
                if detect() then return ops[dig]() end
                return false,"kein Mob da"
            end
            if detect() then return ops[dig]() end
            local ok=ops[attack]();if ok then return true end
            return false,"nichts da"
        end
    end
    -- Bauen: Block aus dem gewaehlten Slot setzen (Werkzeuge/Modem/Kohle werden uebersprungen)
    local run=m.run or {}
    local function blockSlot()
        local s=run.placeSlot
        local it=s and turtle.getItemDetail(s)
        if it and not M.isGearItem(it.name) then return s,it end
        for i=1,16 do local it2=turtle.getItemDetail(i);if it2 and not M.isGearItem(it2.name) then run.placeSlot=i;return i,it2 end end
    end
    local function placer(fn)
        return function()
            local slot=blockSlot();if not slot then return false,"kein Block im Inventar" end
            local prev=turtle.getSelectedSlot and turtle.getSelectedSlot()
            turtle.select(slot);local ok,why=fn();if prev then turtle.select(prev) end
            if not ok and why==nil then why="da ist schon etwas" end
            return ok,why
        end
    end
    ops.place=placer(turtle.place);ops.placeUp=placer(turtle.placeUp);ops.placeDown=placer(turtle.placeDown)
    ops.nextblock=function()
        local start=run.placeSlot or 0
        for k=1,16 do
            local i=(start+k-1)%16+1
            local it=turtle.getItemDetail(i)
            if it and not M.isGearItem(it.name) then run.placeSlot=i;return true end
        end
        return false,"kein Block im Inventar"
    end
    run.blockInfo=function() local s,it=blockSlot();if it then return it.name,it.count end end
    ops.use=smart(turtle.detect,"dig","attack")
    ops.useUp=smart(turtle.detectUp,"digUp","attackUp")
    ops.useDown=smart(turtle.detectDown,"digDown","attackDown")
    if not m.noVertical then
        ops.up=function() return m.move("up") end
        ops.down=function() return m.move("down") end
    else
        ops.up=function() return false,"diese Turtle faehrt nur waagrecht" end
        ops.down=ops.up
    end
    return ops
end
-- Pocket/Infoscreen: geaenderte Turtles (kind="fleetdelta") in die Flotte uebernehmen
function M.mergeDelta(fleet,b,max)
    if type(fleet)~="table" or type(fleet.ids)~="table" or type(fleet.entries)~="table" or type(b.entries)~="table" then return false end
    local added=false
    for id,e in pairs(b.entries) do
        if M.id(id) and type(e)=="table" and (e.data==nil or type(e.data)=="table") and (M.job(e.job) or e.job=="auto")
            and type(e.online)=="boolean" then
            e.label=M.label(e.label)
            if not fleet.entries[id] then
                if #fleet.ids>=(max or 256) then break end
                fleet.ids[#fleet.ids+1]=id;added=true
            end
            fleet.entries[id]=e
        end
    end
    if added then table.sort(fleet.ids) end
    return true
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
            ..(m.placeChests and " +Kisten" or "")..(m.drain and " +trocken" or "")..((m.seal or "off")~="off" and " +dicht" or "")..((m.keepOres or "")~="" and " +Erze bleiben" or "")..((m.torches or 0)>0 and (" +Fackel/"..m.torches) or "")
    end
    local function farmText(f)
        return f.length.."x"..f.width.." "..sideName(f.side).." "..(common.CROP_NAMES[f.crop] or f.crop)
    end
    local function bothName(s) return s=="both" and "beidseitig" or sideName(s) end
    local function treeText(t)
        return "Gebiet "..t.length.."x"..t.width.." "..sideName(t.side)..(t.replant and " +pflanzen" or "")
    end
    local MOB_MODES={farm="Mobfarm",guard="Wache",patrol="Waechter"}
    local function mobText(m)
        local s=MOB_MODES[m.mode] or m.mode
        if m.mode=="patrol" then s=s.." "..m.length.."x"..m.width.." "..sideName(m.side) end
        return s..(m.attack=="all" and " +oben/unten" or m.attack=="up" and " nur oben" or "")..(m.nightOnly and " nachts" or "")
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
        hint("Kisten ins Turtle-Inventar legen: bei")
        hint("vollem Inventar setzt sie eine in den")
        hint("Boden und laedt ab (kein Heimweg).")
        m.placeChests=yesno("Kisten unterwegs setzen?",m.placeChests==true)
        if m.height>=3 then
            hint("Fackeln ins Inventar: auf den Boden")
            hint("der untersten Reihe. 0 = aus")
            m.torches=ask("Fackel alle x Bloecke (0-64)",m.torches or 0,0,64)
        else
            hint("Fackeln: erst ab Ganghoehe 3.");m.torches=0
        end
        header("Mine: Wasser, Lava, Erze")
        hint("Wasser/Lava im Gang entfernen (Block")
        hint("rein, wieder abbauen) - z.B. unter Wasser")
        m.drain=yesno("Gang trockenlegen?",m.drain==true)
        hint("Waende an der Fahrspur zubauen:")
        hint("1 aus  2 Wasser/Lava  3 alles (auch Loecher)")
        local cs=({off=1,liquids=2,all=3})[m.seal or "off"] or 1
        m.seal=({"off","liquids","all"})[ask("Waende",cs,1,3)]
        hint("Erze stehen lassen (oben/unten/seitlich;")
        hint("in der Fahrspur muss sie durch).")
        hint("leer = alle abbauen, all = alle Erze,")
        hint("oder z.B. diamond,emerald")
        write(cut("Erze ["..((m.keepOres or "")=="" and "-" or m.keepOres).."]: "))
        local v=read()
        if v=="-" then m.keepOres="" elseif v~="" then m.keepOres=v:lower():gsub("%s","") end
    end
    local function editFarm(c)
        local f=c.farm
        header("Feld (von der Basis aus nach vorne)")
        hint("Enter = behalten. Wasser wird erkannt.")
        f.length=ask("Laenge (1-32)",f.length,1,32)
        f.width=ask("Breite (1-32)",f.width,1,32)
        if f.width>1 then f.side=askSide("Feld nach",f.side) end
        local crops={"wheat","carrots","potatoes","beetroot","sugarcane"}
        local cur=1;for i,v in ipairs(crops) do if v==f.crop then cur=i end end
        hint("1 Weizen 2 Karotten 3 Kartoffeln 4 Rote Bete")
        hint("5 Zuckerrohr (Turtle 1 hoeher: auf Hoehe")
        hint("  des 3. Blocks, unterster bleibt stehen)")
        f.crop=crops[ask("Pflanze",cur,1,5)]
        f.interval=ask("Kuerzeste Pause zwischen Runden (s)",f.interval,1,86400)
        hint("Spar-Pause: sind wenige Pflanzen reif,")
        hint("wartet sie laenger (spart viel Fuel).")
        hint("0 = immer die kuerzeste Pause")
        f.maxInterval=ask("Laengste Pause (s, 1200 = 20 min)",f.maxInterval or 1200,0,86400)
        hint("Saatgut aus der Ernte wird behalten.")
        hint("0 = automatisch passend zum Feld")
        f.seedReserve=ask("Saatgut behalten (0-256)",f.seedReserve or 0,0,256)
        f.water={}
    end
    local function editTree(c)
        local t=c.tree
        header("Holzfaeller (Gebiet vor der Basis)")
        hint("Sucht im Gebiet nach Baeumen (egal wo),")
        hint("folgt dem Gelaende, faellt ganze Staemme.")
        hint("Unten Kiste=Holz, oben=Kohle, hinten=")
        hint("Setzlinge (optional).")
        t.length=ask("Gebiet nach vorne (1-128)",t.length,1,128)
        t.width=ask("Gebiet zur Seite (1-128)",t.width,1,128)
        if t.width>1 then t.side=askSide("Gebiet nach",t.side=="left" and "left" or "right") end
        t.climb=ask("Max. Hoehe hoch/runter (1-32)",t.climb or 8,1,32)
        t.maxHeight=ask("Max. Baumhoehe (4-64)",t.maxHeight,4,64)
        t.replant=yesno("Setzlinge nachpflanzen?",t.replant~=false)
        t.interval=ask("Pause zwischen Runden (s)",t.interval,0,86400)
    end
    local function editMob(c)
        local m=c.mob
        header("Mobs (Schwert-Turtle)")
        hint("1 Mobfarm: steht an der Toetungsstelle,")
        hint("  Drops in die Kiste unter ihr")
        hint("2 Wache: steht an einer Stelle")
        hint("3 Waechter: faehrt im Gebiet umher")
        local cur=m.mode=="guard" and 2 or m.mode=="patrol" and 3 or 1
        m.mode=({"farm","guard","patrol"})[ask("Art",cur,1,3)]
        hint("Angriff: 1 nur vorne  2 nur oben")
        hint("(Mobfarm-Schacht ueber der Turtle)  3 alle")
        local ca=m.attack=="up" and 2 or m.attack=="all" and 3 or 1
        m.attack=({"front","up","all"})[ask("Angriff",ca,1,3)]
        hint("Tagsueber Pause, nur nachts aktiv")
        hint("(Spielzeit 18:30 bis 5:30)?")
        m.nightOnly=yesno("Nur nachts?",m.nightOnly==true)
        if m.mode=="patrol" then
            hint("Gebiet ab der Basis: nach vorne Laenge,")
            hint("zur Seite Breite. Faehrt zufaellig umher,")
            hint("klettert ueber Gelaende, baut nichts ab.")
            m.length=ask("Laenge (2-64)",m.length,2,64)
            m.width=ask("Breite (1-64)",m.width,1,64)
            if m.width>1 then m.side=askSide("Gebiet nach",m.side) end
            m.climb=ask("Max. Hoehe hoch/runter (1-32)",m.climb or 8,1,32)
            hint("Faehrt bis das Fuel knapp ist, dann")
            hint("zur Basis tanken. Mehr Fuel = laenger.")
            m.fuelTarget=ask("Tanken bis (100-100000)",m.fuelTarget,100,100000)
            m.interval=ask("Pause an der Basis (s)",m.interval,0,86400)
        end
        fg(colors.orange)
        print(cut("Achtung: greift alles direkt vor"))
        print(cut("sich an, auch Spieler."))
        fg(colors.white);sleep(1.5)
    end
    local function buildText(b)
        return b.floors.." Etage(n), Schacht "..b.drop..(b.creeperOnly and " +nur Creeper" or "")..(b.inTerrain and " +im Berg" or " +frei")..(b.becomeMob and " +danach Mobs" or "")
    end
    local function editBuild(c)
        local b=c.build
        header("Mobfarm bauen (ueber der Turtle)")
        hint("Turtle steht dort, wo spaeter die Mobs")
        hint("ankommen. Kiste UNTER ihr = Drops,")
        hint("Kiste HINTER ihr = Material + Kohle.")
        b.floors=ask("Spawn-Etagen (1-6)",b.floors,1,6)
        hint("Schacht 22: Mobs fallen fast tot an,")
        hint("die Turtle gibt den Rest.")
        b.drop=ask("Schachthoehe (4-60)",b.drop,4,60)
        hint("Falltueren an der Decke: nur Creeper")
        hint("passen (viel Schwarzpulver).")
        b.creeperOnly=yesno("Nur Creeper?",b.creeperOnly~=false)
        hint("Im Berg/Gelaende: raeumt alles frei.")
        hint("Im Freien: nur Bahnen mit Bloecken")
        hint("(wie ein 3D-Drucker, spart viel Fuel).")
        b.inTerrain=yesno("Im Berg/Gelaende bauen?",b.inTerrain==true)
        b.becomeMob=yesno("Danach selbst Mob-Turtle?",b.becomeMob~=false)
        local n=b.floors
        hint("Material ca.: "..(n*832+361+4*(b.drop-1)).." Bruchstein,")
        hint(n*64 .." Bruchsteinstufen, "..n*4 .." Wassereimer"..(b.creeperOnly and (", "..n*192 .." Falltueren") or ""))
        sleep(2)
    end
    local SHAPES={"room","cylinder","sphere","dome"}
    local SHAPE_TEXT={room="Quader/Schacht",cylinder="Zylinder",sphere="Kugel",dome="Halbkugel"}
    local SEALS={"off","liquids","all"}
    local function digText(d)
        local size=d.shape=="room" and (d.width.."x"..d.length.."x"..d.height) or d.shape=="cylinder" and ("D"..d.width.."x"..d.height) or ("D"..d.width)
        return (SHAPE_TEXT[d.shape] or d.shape).." "..size.." "..(d.direction=="up" and "hoch" or "runter")
            ..(d.seal=="all" and " +dicht" or d.seal=="liquids" and " +Fluess." or "")..(d.drain and " +trocken" or "")
            ..(d.keepOres~="" and " +Erze bleiben" or "")..(d.wallBlock~="" and (" +"..d.wallBlock:gsub("^minecraft:","")) or "")
    end
    local function editDig(c)
        local d=c.dig
        header("Aushub (Form vor der Basis)")
        hint("Die Form beginnt direkt VOR der Turtle.")
        hint("Unten Kiste=Ausgabe, oben Kiste=Kohle.")
        for i,v in ipairs(SHAPES) do hint(i.." "..SHAPE_TEXT[v]) end
        local cur=1;for i,v in ipairs(SHAPES) do if d.shape==v then cur=i end end
        d.shape=SHAPES[ask("Form",cur,1,4)]
        d.direction=yesno("Nach unten graben? (n = nach oben)",d.direction~="up") and "down" or "up"
        if d.shape=="room" then
            hint("Schacht = z.B. 3 x 3 x 60")
            d.width=ask("Breite zur Seite (1-1024)",d.width,1,1024)
            d.length=ask("Laenge nach vorne (1-1024)",d.length,1,1024)
            d.height=ask(d.direction=="up" and "Hoehe (1-1024)" or "Tiefe (1-1024)",d.height,1,1024)
            if d.width>1 then d.side=askSide("Zur Seite nach",d.side) end
        else
            d.width=ask("Durchmesser (1-1024)",d.width,1,1024)
            if d.shape=="cylinder" then d.height=ask(d.direction=="up" and "Hoehe (1-1024)" or "Tiefe (1-1024)",d.height,1,1024) end
        end
        header("Aushub: Waende und Fluessigkeiten")
        hint("1 Waende nicht zubauen")
        hint("2 Wasser/Lava an den Waenden zubauen")
        hint("3 Alles dicht (auch Hoehlen/Loecher)")
        hint("Braucht Bruchstein o.ae. (wird behalten).")
        local cs=1;for i,v in ipairs(SEALS) do if d.seal==v then cs=i end end
        d.seal=SEALS[ask("Waende",cs,1,3)]
        hint("Unter Wasser / in Lava graben:")
        hint("Wasser/Lava im Raum wird entfernt.")
        d.drain=yesno("Raum trockenlegen?",d.drain==true)
        header("Aushub: Waende verkleiden")
        hint("Waende/Boden/Decke aus einem Block bauen")
        hint("(z.B. stone_bricks, glass, deepslate_tiles).")
        hint("Den Block in die Kiste OBEN legen (zur")
        hint("Kohle). Leer = keine Verkleidung, - = aus")
        write(cut("Block ["..(d.wallBlock=="" and "-" or d.wallBlock).."]: "))
        local vb=read():lower():gsub("%s","")
        if vb=="-" then d.wallBlock="" elseif vb~="" then
            if not vb:find(":",1,true) then vb="minecraft:"..vb end
            d.wallBlock=vb
        end
        if d.wallBlock~="" then
            d.lineWalls=yesno("Waende verkleiden?",d.lineWalls~=false)
            d.lineFloor=yesno("Boden verkleiden?",d.lineFloor~=false)
            d.lineCeiling=yesno("Decke verkleiden?",d.lineCeiling~=false)
        end
        header("Aushub: Erze schonen")
        hint("Erze stehen lassen und drumherum graben")
        hint("(spaeter von Hand abbauen, z.B. Gluck).")
        hint("leer = alles abbauen, all = alle Erze")
        hint("oder z.B.: diamond,emerald,ancient")
        write(cut("Erze ["..(d.keepOres=="" and "-" or d.keepOres).."]: "))
        local v=read()
        if v=="-" then d.keepOres="" elseif v~="" then d.keepOres=v:lower():gsub("%s","") end
        d.useCoal=yesno("Gefundene Kohle als Fuel?",d.useCoal~=false)
        local ok,why=pcall(common.checkDig,d)
        if not ok then fg(colors.orange);print(cut(tostring(why)));fg(colors.white);sleep(2) end
    end
    local function editStorage(c)
        local s=c.storage
        header("Lager (Kistenueberwachung)")
        hint("Kisten direkt am Computer oder per")
        hint("Netzwerkkabel + Kabelmodem (rechts-")
        hint("klick aufs Modem = rot = verbunden).")
        s.interval=ask("Neu auslesen alle x s (2-600)",s.interval,2,600)
        s.warnAt=ask("Orange ab x % voll (50-100)",s.warnAt,50,100)
        local found={}
        for _,n in ipairs(peripheral.getNames()) do
            local t=tostring(peripheral.getType(n) or "")
            local m=peripheral.wrap(n)
            if not t:find("turtle",1,true) and t~="monitor" and t~="modem" and m and type(m.list)=="function" then found[#found+1]=n end
        end
        table.sort(found)
        if #found==0 then fg(colors.orange);print(cut("Keine Kisten gefunden."));fg(colors.white);sleep(1.5);return end
        if not yesno(#found.." Kisten gefunden. Namen geben?",false) then return end
        hint("Enter = behalten, - = Standardname")
        for _,n in ipairs(found) do
            write(cut(n.." ["..(s.names[n] or "-").."]: "))
            local v=read()
            if v=="-" then s.names[n]=nil elseif v~="" then s.names[n]=common.label(v) end
        end
    end
    local FACE_NAMES={north="Norden",east="Osten",south="Sueden",west="Westen"}
    local DIMS={"auto","overworld","nether","end"}
    local DIM_TEXT={auto="Dim. auto",overworld="Oberwelt",nether="Nether",["end"]="End"}
    local function baseText(b)
        local d=DIM_TEXT[b.dimension or "auto"] or ""
        if not b.set then return "Koord. aus, "..d end
        return b.x.." "..b.y.." "..b.z.." "..(FACE_NAMES[b.facing] or b.facing):sub(1,1)..", "..d
    end
    local function editBase(c)
        local b=c.base
        header("Basis-Koordinaten")
        hint("Damit Zentrale/Pocket die echten")
        hint("Koordinaten der Turtle zeigen.")
        hint("F3 an der Basis: Block der Turtle,")
        hint("Blickrichtung = wohin sie schaut.")
        hint("Dimension: 1 automatisch erkennen")
        hint("2 Oberwelt  3 Nether  4 End")
        local cd=1;for i,v in ipairs(DIMS) do if v==(b.dimension or "auto") then cd=i end end
        b.dimension=DIMS[ask("Dimension",cd,1,4)]
        b.set=yesno("Koordinaten eintragen?",b.set==true)
        if not b.set then return end
        b.x=ask("X",b.x,-30000000,30000000)
        b.y=ask("Y",b.y,-2048,4096)
        b.z=ask("Z",b.z,-30000000,30000000)
        hint("1 Norden (-Z)  2 Osten (+X)")
        hint("3 Sueden (+Z)  4 Westen (-X)")
        local list={"north","east","south","west"}
        local cur=1;for i,v in ipairs(list) do if v==b.facing then cur=i end end
        b.facing=list[ask("Blickrichtung",cur,1,4)]
    end
    local function gpsText(g) return "X "..g.x.." Y "..g.y.." Z "..g.z..(g.auto and " (auto)" or "") end
    local function editGps(c)
        local g=c.gps
        header("GPS-Sender: eigene Koordinaten")
        hint("Laufen schon 4 andere GPS-Sender, kann")
        hint("er seine Position selbst finden.")
        if gps and gps.locate and common.refreshModems()>0 then
            print("Suche Position per GPS ...")
            local ok,x,y,z=pcall(gps.locate,2)
            if ok and x then
                x,y,z=math.floor(x+0.5),math.floor(y+0.5),math.floor(z+0.5)
                fg(colors.lime);print(cut("Gefunden: X "..x.." Y "..y.." Z "..z));fg(colors.white)
                if yesno("Uebernehmen?",true) then g.x,g.y,g.z,g.auto=x,y,z,true;return end
            else
                fg(colors.orange);print(cut("Kein GPS gefunden (normal fuer"));print(cut("die ersten 4 Sender)."));fg(colors.white)
            end
        end
        hint("F3 auf DIESEN Computer schauen:")
        hint("rechts 'Targeted Block' X Y Z")
        g.x=ask("X",g.x,-30000000,30000000)
        g.y=ask("Y",g.y,-2048,4096)
        g.z=ask("Z",g.z,-30000000,30000000)
        g.auto=yesno("Spaeter selbst per GPS pruefen?",g.auto~=false)
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
            hint("Anbau: Chunkloader + "..(({farm="Hacke",tree="Axt",mob="Schwert"})[job] or "Spitzhacke"))
            hint("Funkmodem ins Turtle-Inventar legen.")
            sleep(1.5)
        end
    end
    local function editRadio(c,job)
        local sec=c[common.JOB_SECTION[job] or "mine"]
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
        return ({all="Alle Turtles",farm="Alle Farmen",mining="Alle Minen",tree="Alle Holzfarmen",mob="Alle Mob-Turtles",dig="Alle Aushub-Turtles",build="Alle Mobfarm-Bauer",storage="Lager (Kisten)"})[v] or tostring(v)
    end
    function editShow(c)
        header("Was soll der Infoscreen zeigen?")
        print("")
        local opts={"all","farm","mining","tree","mob","dig","build","storage"}
        for i,v in ipairs(opts) do hint(i.." "..showText(v)) end
        local nT=#opts+1
        hint(nT.." Eine bestimmte Turtle")
        local cur=type(c.show)=="number" and nT or 1
        for i,v in ipairs(opts) do if c.show==v then cur=i end end
        local n=ask("Auswahl",cur,1,nT)
        if n<nT then c.show=opts[n]
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
        hint("Automatisch updaten: Zentrale sieht")
        hint("regelmaessig nach einer neuen Version")
        hint("und aktualisiert dann ALLE Geraete.")
        c.autoUpdate=yesno("Automatisch updaten?",c.autoUpdate~=false)
        if c.autoUpdate then c.updateEvery=ask("Alle x Minuten nachsehen",c.updateEvery or 5,1,1440) end
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
    -- Aufgabe wechseln (z.B. Mine -> Mobs). Alle Programme sind schon installiert.
    local function editJob(c,info)
        header("Aufgabe wechseln")
        hint("Jetzt: "..(common.JOB_NAMES[c.job] or "?"))
        local TOOL={farm="Hacke",mining="Spitzhacke",tree="Axt",mob="Schwert",dig="Spitzhacke",build="Spitzhacke"}
        for i,j in ipairs(common.JOBS) do
            fg(colors.yellow);write(i.." ");fg(colors.white);print(cut(string.format("%-7s",common.JOB_NAMES[j]).." ("..TOOL[j]..")"))
        end
        local cur=1;for i,j in ipairs(common.JOBS) do if j==c.job then cur=i end end
        local n=ask("Aufgabe",cur,1,#common.JOBS)
        local new=common.JOBS[n]
        if new~=c.job then
            c.job=new;info.job=new
            hint("Passendes Werkzeug ("..TOOL[new]..") in die")
            hint("Turtle legen. Jetzt die Werte unter")
            hint("'"..common.JOB_NAMES[new].."' pruefen.")
            sleep(1.5)
        end
    end
    local function items(c,info)
        local role,job=info.role,info.job
        local list={{"Name",function() return c.name~="" and c.name or "-" end,function()
            header("Name");hint("Leer lassen = behalten, - = loeschen")
            c.name=askText("Name",c.name);c.label=c.name end}}
        if role=="gps" then
            list[#list+1]={"Position",function() return gpsText(c.gps) end,function() editGps(c) end}
            return list
        end
        if role~="controller" and role~="repeater" then
            list[#list+1]={"Zentrale",function() return "#"..c.controllerId end,function() editController(c) end}
        end
        if role=="turtle" and job=="mining" then
            list[#list+1]={"Mine",function() return mineText(c.mine) end,function() editMine(c) end}
        elseif role=="turtle" and job=="tree" then
            list[#list+1]={"Baeume",function() return treeText(c.tree) end,function() editTree(c) end}
        elseif role=="turtle" and job=="mob" then
            list[#list+1]={"Mobs",function() return mobText(c.mob) end,function() editMob(c) end}
        elseif role=="turtle" and job=="build" then
            list[#list+1]={"Mobfarm",function() return buildText(c.build) end,function() editBuild(c) end}
        elseif role=="turtle" and job=="dig" then
            list[#list+1]={"Aushub",function() return digText(c.dig) end,function() editDig(c) end}
        elseif role=="turtle" then
            list[#list+1]={"Feld",function() return farmText(c.farm) end,function() editFarm(c) end}
        end
        if role=="turtle" then
            list[#list+1]={"Chunks",function() return chunkText(c.chunkload) end,function() editChunks(c,job) end}
        end
        if role=="turtle" then
            list[#list+1]={"Basis",function() return baseText(c.base) end,function() editBase(c) end}
            list[#list+1]={"Funk",function() return radioText(c[common.JOB_SECTION[job] or "mine"].radioTimeout) end,
                function() editRadio(c,job) end}
            -- am Ende, damit die Nummern der anderen Punkte gleich bleiben
            if not info.installer then
                list[#list+1]={"Aufgabe",function() return common.JOB_NAMES[c.job] or "?" end,function() editJob(c,info) end}
            end
        end
        if role=="storage" then
            list[#list+1]={"Lager",function() local s=c.storage
                local n=0;for _ in pairs(s.names) do n=n+1 end
                return "alle "..s.interval.." s, orange ab "..s.warnAt.."%"..(n>0 and (", "..n.." Namen") or "") end,
                function() editStorage(c) end}
        end
        if role=="controller" or role=="info" or role=="storage" then
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
                ..(c.autoPairPockets and "Pockets auto" or "Pockets fest")..(c.autoUpdate and ", Update auto" or "") end,function() editDevices(c) end}
        end
        if role=="controller" or role=="info" or role=="repeater" or role=="storage" then
            list[#list+1]={"GPS",function()
                local g=c.gps
                if g.host==false then return "aus" end
                return g.set and ("Sender "..gpsText(g)) or "Sender, Position fehlt" end,
                function()
                    header("Nebenbei GPS-Sender")
                    hint("Dieser Computer beantwortet GPS-")
                    hint("Anfragen mit (spart GPS-Computer).")
                    hint("Mind. 4 Sender insgesamt, nicht alle")
                    hint("auf derselben Hoehe.")
                    c.gps.host=yesno("Als GPS-Sender mitlaufen?",c.gps.host~=false)
                    if c.gps.host then editGps(c);c.gps.set=true end
                end}
        end
        return list
    end
    -- Uebersicht; true = uebernehmen, false = abbrechen
    function M.run(c,info)
        while true do
            local what=info.role=="turtle" and ((info.newJob and "NEUER AUFTRAG: " or "").."Turtle #"..os.getComputerID().." / "..(common.JOB_NAMES[info.job] or "?"))
                or (({controller="Zentrale",pocket="Pocket",repeater="Repeater",info="Infoscreen",gps="GPS-Sender",storage="Lager"})[info.role].." #"..os.getComputerID())
            local list=items(c,info)
            header(what)
            print("")
            for i,it in ipairs(list) do
                fg(colors.yellow);write(i.." ");fg(colors.white)
                write(string.format("%-9s",it[1]))
                fg(colors.lightGray);print(tostring(it[2]()):sub(1,math.max(1,W-12)));fg(colors.white)
            end
            print("")
            hint("Nummer = aendern, Enter = "..(info.newJob and "Auftrag starten" or info.installer and "weiter" or "speichern")
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
        if job=="tree" then local t=c.tree return table.concat({t.length,t.width,t.side},":") end
        if job=="mob" then local m=c.mob return table.concat({m.mode,m.length,m.width,m.side},":") end
        if job=="dig" then local d=c.dig return table.concat({d.shape,d.width,d.length,d.height,d.side,d.direction},":") end
        if job=="build" then local b=c.build return table.concat({b.floors,b.drop,tostring(b.creeperOnly),tostring(b.inTerrain==true)},":") end
        return ""
    end
    -- Neuer Auftrag: Fortschritt der Aufgabe loeschen (Turtle muss an der Basis stehen)
    M.STATE_FILES={farm="/toast_farm_state",mining="/toast_mining_state",tree="/toast_tree_state",mob="/toast_mob_state",dig="/toast_dig_state",build="/toast_build_state"}
    function M.newJob(job)
        local file=M.STATE_FILES[job];if not file then return false end
        header("Neuer Auftrag")
        print("Fortschritt/Zaehler des alten Auftrags")
        print("werden geloescht.")
        print("Die Turtle muss an ihrer Basis stehen")
        print(job=="mining" and "(Blick in die Mine)." or "(Blick nach vorne).")
        if yesno("Steht sie an der Basis?",true) then
            for _,p in ipairs({file,file..".tmp"}) do if fs.exists(p) then fs.delete(p) end end
            return true
        end
        printError("Erst an die Basis stellen, dann: toast.lua neu")
        sleep(2)
        return false
    end
    -- Aufgabe gewechselt: Fortschritt beider Aufgaben loeschen (Turtle an der Basis)
    function M.switchJob(old,new)
        header("Aufgabe wechseln")
        print((common.JOB_NAMES[old] or "?").." -> "..(common.JOB_NAMES[new] or "?"))
        print("Die Turtle muss an ihrer Basis stehen")
        print("(Kisten unten/oben, Blick nach vorne).")
        if yesno("Steht sie an der Basis?",true) then
            for _,j in ipairs({old,new}) do
                local file=M.STATE_FILES[j]
                if file then for _,p in ipairs({file,file..".tmp"}) do if fs.exists(p) then fs.delete(p) end end end
            end
            return true
        end
        printError("Erst an die Basis stellen, dann nochmal.")
        sleep(2)
        return false
    end
    function M.confirmReset(job)
        if job~="mining" and job~="tree" and job~="mob" and job~="dig" and job~="build" then return end
        local file="/toast_"..job.."_state"
        if not (fs.exists(file) or fs.exists(file..".tmp")) then return end
        header(job=="mining" and "Neue Minenmasse" or "Neue Masse")
        print("Neue Masse = neuer Auftrag.")
        print("Die Turtle muss an ihrer Basis stehen")
        print(job=="mining" and "(Blick in die Mine)." or "(Blick nach vorne).")
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
-- Nebenbei GPS-Sender (wenn Koordinaten bekannt)
local gpsHost=common.gpsHost(cfg)
local ui=UI.new(screen,cfg)
local model=dofile("/toast/toast_model.lua").new(cfg)
-- Automatisches Update: alle 5 min version.txt auf GitHub pruefen (ohne zu blockieren)
local AUTO={next=os.clock()+30,url=nil,every=(cfg.updateEvery or 5)*60}
local function checkVersion()
    if model.updateRun and not model.updateRun.target and not model.updateRun.asked and http and http.request and not AUTO.url then
        -- Zielversion fuer die Fertig-Meldungen holen
        model.updateRun.asked=true
        AUTO.url=common.versionUrl.."?t="..math.floor(os.epoch("utc")/1000)
        if not pcall(http.request,AUTO.url) then AUTO.url=nil end
        return
    end
    if cfg.autoUpdate==false or not http or not http.request or AUTO.url or os.clock()<AUTO.next or model.updateRun then return end
    AUTO.next=os.clock()+AUTO.every
    AUTO.url=common.versionUrl.."?t="..math.floor(os.epoch("utc")/1000)
    if not pcall(http.request,AUTO.url) then AUTO.url=nil end
end
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
    local cmd=ui.action(a)
    if type(cmd)=="table" then model.remoteCmd(cmd.id,cmd.payload)
    elseif cmd then model.command(cmd,ui.target()) end
    draw()
end
local quit=false
local function loop()
    rednet.host(common.protocol,"toast-"..cfg.controllerId)
    model.tick();draw()
    local timer=os.startTimer(cfg.network.pollInterval)
    local frame=os.startTimer(0.2)
    local lastFrame,lastTick=os.clock(),os.clock()
    while true do
        local e,a,b,c,d,f=os.pullEvent()
        if gpsHost and gpsHost.event(e,a,b,c,d,f) then
            -- GPS-Anfrage beantwortet
        elseif e=="rednet_message" then
            if model.ingest(a,b,c) or model.turtleConfig(a,b,c) or model.remote(a,b,c) then dirty=true end
        elseif e=="timer" and a==timer then lastTick=os.clock();model.tick();model.heal();checkVersion();dirty=true;timer=os.startTimer(cfg.network.pollInterval)
        elseif e=="http_success" and AUTO.url and a==AUTO.url then
            AUTO.url=nil
            local remote=b and b.readAll and b.readAll() or "";pcall(b.close)
            remote=remote:match("[%d%.]+")
            if remote and model.updateRun and not model.updateRun.target then
                model.updateRun.target=remote
            elseif remote and common.newer(remote,common.version) then
                common.log("Neue Version "..remote.." gefunden, Update fuer alle")
                model.startUpdate(nil,remote)
                model.notice="Neue Version "..remote..": Update fuer alle gestartet"
                dirty=true
            end
        elseif e=="http_failure" and AUTO.url and a==AUTO.url then AUTO.url=nil
        elseif e=="timer" and a==frame and model.updateRun then
            -- Fortschritt anzeigen; wenn alle fertig (oder 3 min um): Zentrale selbst
            local run=model.updateRun
            local done,total=model.updateStatus()
            local age=os.clock()-run.at
            model.notice="Update: "..done.."/"..total.." fertig"..(run.target and (" (v"..run.target..")") or "")
            dirty=true
            if (done>=total and (run.target or age>=10)) or age>=180 then
                model.updateRun=nil
                if run.target and not common.newer(run.target,common.version) then
                    model.notice="Update fertig: alle "..done.."/"..total.." auf v"..run.target
                else
                    model.notice="Alle fertig ("..done.."/"..total.."), Zentrale installiert ...";draw()
                    local ok,why=common.selfUpdate(nil,run.target)
                    if not ok then model.notice="Update fehlgeschlagen: "..tostring(why);common.log("Update: "..tostring(why)) end
                end
            end
            model.flush();lastFrame=os.clock()
            if dirty then draw() end
            frame=os.startTimer(0.2)
        elseif e=="timer" and a==frame then
            -- 5x pro Sekunde: Aenderungen an Pockets weiterreichen + neu zeichnen
            model.flush();lastFrame=os.clock()
            if dirty then draw() end
            frame=os.startTimer(0.2)
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
            if (a=="q" or a=="Q") and not ui.help and not ui.textInput() then quit=true;return end
            action(ui.char(a))
        elseif e=="key" then action(ui.key(keys.getName(a)))
        elseif e=="mouse_scroll" then action(a>0 and "down" or "up") end
        -- Zeitgeber verloren (Peripherie-Aufruf hat ihn verschluckt)? Trotzdem weiter.
        if os.clock()-lastFrame>1 then lastFrame=os.clock();model.flush();if dirty then draw() end;frame=os.startTimer(0.2) end
        if os.clock()-lastTick>cfg.network.pollInterval*3 then lastTick=os.clock();model.tick();dirty=true;timer=os.startTimer(cfg.network.pollInterval) end
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
    local m={entries={},pending={},notice="Warte auf Geraete...",config=cfg,changedIds={},configs={}}
    local PATH="/toast_control_state"
    local s=common.readState(PATH)
    local serial=common.serial(s.serial) and s.serial or 0
    local devices,pockets,remote={}, {}, {}
    m.nodes={}           -- Netzgeraete: [id]={role,label,data,seen}
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
    function m.fleet(scope,lite)
        local ids,entries={},{}
        for id,d in pairs(devices) do if scope==nil or scope=="all" or d.job==scope then ids[#ids+1]=id end end
        table.sort(ids)
        for _,id in ipairs(ids)do
            local e=m.entries[id];local d=devices[id]
            entries[id]={job=d.job,label=d.label,online=m.online(id),data=e and e.data or nil,pending=m.pending[id]~=nil}
        end
        local nids,nentries={},{}
        for id,n in pairs(m.nodes) do nids[#nids+1]=id end
        table.sort(nids)
        for _,id in ipairs(nids) do local n=m.nodes[id]
            local data=n.data
            if lite and data and data.stats and n.role=="storage" then
                -- nur die Kurzwerte; Kisten/Inhalt kommen alle 10 s als "nodestats"
                local s=data.stats
                data={toast=data.toast,pos=data.pos,stats={pct=s.pct,count=s.count,types=s.types,full=s.full,warn=s.warn,size=s.size,used=s.used,lite=true}}
            end
            nentries[id]={role=n.role,label=n.label,online=os.clock()-n.seen<30,data=data} end
        return {ids=ids,entries=entries,nodes={ids=nids,entries=nentries},configs=not lite and m.configs or nil}
    end
    local function node(id,info)
        if type(info)~="table" then return end
        local role=info.role
        if not ({repeater=true,gps=true,info=true,pocket=true,storage=true})[role] then return end
        local n=0;for _ in pairs(m.nodes) do n=n+1 end
        if not m.nodes[id] and n>=128 then return end
        m.nodes[id]={role=role,label=common.label(info.name),seen=os.clock(),
            data={toast=tostring(info.toast or "?"),pos=type(info.pos)=="table" and info.pos or nil,stats=type(info.stats)=="table" and info.stats or nil}}
    end
    local nextRemote          -- (unten definiert) naechsten Fernsteuer-Befehl senden
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
        if pending and common.number(b.ack)>=pending.message.serial then m.pending[id]=nil;pending=nil;nextRemote(id) end
        -- Befehl offen: sofort nachschicken (Turtle hoert gerade zu, z.B. im Funkfenster)
        if pending and os.clock()-(pending.sentAt or 0)>=0.3 then pending.sentAt=os.clock();dispatch(id,pending.message,pending.job) end
        -- Funkfenster (Chunkloader-Turtle): sofort antworten, dann kann sie gleich weiterarbeiten
        if b.window then send(id,{kind="poll"},p) end
        m.changedIds[id]=true
        if changed then save() end
        return true
    end
    -- Fernsteuerung: Einstellungen abrufen/aendern, von Hand fahren (an EINE Turtle)
    -- Schnelle Tastendruecke: hinten anstellen (hoechstens 6), damit keiner verloren geht
    m.remoteQueue={}
    local function sendRemote(id,payload)
        local d=devices[id]
        local e=m.entries[id]
        serial=math.max(serial+1,os.epoch("utc"),e and common.number(e.data.ack)+1 or 0)
        m.pending[id]={message={kind="remote",serial=serial,payload=payload},at=os.clock(),job=d.job,ttl=15,sentAt=os.clock()}
        dispatch(id,m.pending[id].message,d.job)
        m.changedIds[id]=true
    end
    function m.remoteCmd(id,payload)
        local d=devices[id]
        if not d or type(payload)~="table" or type(payload.op)~="string" then return false end
        local p=m.pending[id]
        if p and p.message.kind=="remote" then
            local q=m.remoteQueue[id] or {};m.remoteQueue[id]=q
            if #q<6 then q[#q+1]=payload end
            return true
        end
        sendRemote(id,payload)
        return true
    end
    nextRemote=function(id)
        local q=m.remoteQueue[id]
        if q and #q>0 and not m.pending[id] then sendRemote(id,table.remove(q,1)) end
    end
    -- Antwort einer Turtle mit ihren Einstellungen
    function m.turtleConfig(id,b,p)
        local job
        for j,protocol in pairs(common.workerProtocols)do if protocol==p then job=j end end
        if not job or not devices[id] or type(b)~="table" or b.kind~="config" or b.id~=id or type(b.config)~="table" then return false end
        m.configs[id]={config=b.config,ok=b.ok,msg=b.msg,at=os.clock()}
        if b.msg then m.notice=tostring(b.msg) end
        for pid in pairs(pockets) do
            send(pid,{kind="turtleconfig",version=1,controllerId=cfg.controllerId,id=id,config=b.config,ok=b.ok,msg=b.msg},common.remoteProtocol)
        end
        return true
    end
    local function matches(id,d,target)
        return target=="all" or target==id or target==d.job
    end
    function m.command(action,target)
        if not common.actions[action] then return false end
        if target~="all" and not common.job(target) and not (common.id(target) and devices[target]) then return false end
        if action=="update" then return m.startUpdate(common.id(target) and target or nil) end
        local changed={}
        local always=action=="stop" or action=="reset"
        for id,d in pairs(devices) do
            local e=m.entries[id]
            if matches(id,d,target) and (always or (m.online(id) and not e.data.recovery)) then
                serial=math.max(serial+1,os.epoch("utc"),e and common.number(e.data.ack)+1 or 0)
                m.pending[id]={message={kind="command",action=action,serial=serial},at=os.clock(),job=d.job,
                    ttl=action=="update" and 180 or nil}
                changed[#changed+1]=id
            end
        end
        if #changed==0 then m.notice="Kein erreichbares Ziel / Position unklar";return false end
        save()
        for _,id in ipairs(changed)do local p=m.pending[id];dispatch(id,p.message,p.job) end
        local names={start="Start",stop="Stopp",once="Einmal",reset="Reset"}
        m.notice=(names[action] or action).." an "..#changed.." Turtle"..(#changed>1 and "s" or "").." gesendet ..."
        return true
    end
    local function key(id,protocol)return protocol..":"..id end
    -- Live: geaenderte Turtles sofort (hoechstens alle 0,3 s) an Pockets/Infoscreens
    local lastDelta=-1e9
    function m.flush()
        if not next(m.changedIds) then return false end
        local now=os.clock()
        if now-lastDelta<0.3 then return false end
        lastDelta=now
        local ents,n={},0
        for id in pairs(m.changedIds) do
            local d,e=devices[id],m.entries[id]
            if d then ents[id]={job=d.job,label=d.label,online=m.online(id),data=e and e.data or nil,pending=m.pending[id]~=nil};n=n+1 end
        end
        m.changedIds={}
        if n==0 then return false end
        local msg={kind="fleetdelta",version=1,controllerId=cfg.controllerId,entries=ents,notice=m.notice}
        for pid in pairs(pockets) do send(pid,msg,common.remoteProtocol) end
        return true
    end
    -- Flotte fuer Pockets/Infoscreens: ohne die grossen Lagerdaten (kommen extra)
    function m.fleetMessage()
        local f=m.fleet("all",true);local labels={}
        for _,tid in ipairs(f.ids)do labels[tid]=f.entries[tid].label end
        return {kind="fleet",version=1,controllerId=cfg.controllerId,fleet=f,labels=labels,ack=0,notice=m.notice}
    end
    function m.reply(id,protocol)
        protocol=protocol or common.remoteProtocol
        local scope="all";for j,p in pairs(common.legacyRemote)do if p==protocol then scope=j end end
        local f=m.fleet(scope,protocol==common.remoteProtocol);local labels={}
        for _,tid in ipairs(f.ids)do labels[tid]=f.entries[tid].label end
        send(id,{kind="fleet",version=protocol==common.remoteProtocol and 1 or 2,
            controllerId=cfg.controllerId,fleet=f,labels=labels,ack=remote[key(id,protocol)] or 0,notice=m.notice},protocol)
    end
    function m.remote(id,b,protocol)
        local scope="all";local valid=protocol==common.remoteProtocol
        for j,p in pairs(common.legacyRemote)do if p==protocol then scope=j;valid=true end end
        if not valid or not common.id(id) or id==cfg.controllerId or devices[id] or type(b)~="table" then return false end
        -- Repeater / GPS-Sender melden sich per Rundfunk
        if b.kind=="node" and protocol==common.remoteProtocol and (b.controllerId==0 or b.controllerId==cfg.controllerId) then
            node(id,b.info);return true
        end
        if b.kind=="hello" and type(b.info)=="table" then node(id,b.info) end
        if not pockets[id] then
            if not (cfg.autoPairPockets and protocol==common.remoteProtocol and b.kind=="hello"
                and b.version==1 and (b.role=="pocket" or b.role=="info") and b.controllerId==cfg.controllerId) then return false end
            local n=0;for _ in pairs(pockets)do n=n+1 end
            if n>=64 then return false end
            pockets[id]=true;save()
        end
        if b.kind=="remote" and common.serial(b.serial) and common.id(b.target) and type(b.payload)=="table" then
            if b.serial>(remote[key(id,protocol)] or 0) then
                remote[key(id,protocol)]=b.serial
                m.remoteCmd(b.target,b.payload)
            end
            m.reply(id,protocol);m.markReply(id);return true
        end
        if b.kind=="command" and common.serial(b.serial) and b.serial>(remote[key(id,protocol)] or 0) then
            local target=b.target
            if scope~="all" then
                if target=="all" then target=scope
                elseif not devices[target] or devices[target].job~=scope then m.reply(id,protocol);return true end
            end
            if m.command(b.action,target) then remote[key(id,protocol)]=b.serial;save() end
            m.reply(id,protocol);m.markReply(id);return true
        end
        if m.wantsReply(id) then m.reply(id,protocol);m.markReply(id) end
        return true
    end
    local lastPoll,lastFleet,lastStats,lastReply=-1e9,-1e9,-1e9,{}
    function m.tick()
        local now=os.clock()
        if now-lastPoll>=2 then
            lastPoll=now
            common.refreshModems()
            -- ein Rundruf je Turtle-Art erreicht alle Turtles (statt jede einzeln)
            for _,p in pairs(common.workerProtocols)do pcall(rednet.broadcast,{kind="poll"},p)end
        end
        local waiting,expired=0,0
        for id,p in pairs(m.pending)do
            if os.clock()-p.at>=(p.ttl or cfg.network.commandTimeout) then m.pending[id]=nil;expired=expired+1;m.remoteQueue[id]=nil
            else waiting=waiting+1;dispatch(id,p.message,p.job) end
        end
        if expired>0 then m.notice="Keine Antwort von "..expired.." Turtle"..(expired>1 and "s" or "").." (Funk/Chunk?)"
        elseif waiting==0 and m.notice:find("gesendet ...",1,true) then m.notice="Befehl bestaetigt" end
        -- komplette Flotte nur noch alle 5 s (Aenderungen kommen sofort per m.flush)
        if now-lastFleet>=5 then
            lastFleet=now
            local msg
            for id in pairs(pockets)do
                msg=msg or m.fleetMessage()
                send(id,msg,common.remoteProtocol);lastReply[id]=now
            end
        end
        -- Lagerdaten (gross) nur alle 10 s extra
        if now-lastStats>=10 then
            lastStats=now
            local stats,any={},false
            for id,n in pairs(m.nodes) do if n.role=="storage" and n.data and n.data.stats then stats[id]=n.data.stats;any=true end end
            if any then for id in pairs(pockets)do send(id,{kind="nodestats",version=1,controllerId=cfg.controllerId,stats=stats},common.remoteProtocol) end end
        end
    end
    -- Hello eines Pockets/Infoscreens: nur antworten, wenn es laenger keine Daten bekam
    function m.wantsReply(id) return os.clock()-(lastReply[id] or -1e9)>=1.5 end
    function m.markReply(id) lastReply[id]=os.clock() end
    function m.waiting()local n=0;for _ in pairs(m.pending)do n=n+1 end;return n end
    -- ===== Update aller Geraete =====
    -- Rueckmeldung: jedes Geraet meldet nach dem Neustart seine Version (Status,
    -- Hello, Beacon). Fertig = Version ist die neue. Die Zentrale wartet nur,
    -- bis alle fertig sind (hoechstens 3 min), statt pauschal.
    local function versionOf(id)
        local e=m.entries[id];if e and e.data and e.data.toast then return tostring(e.data.toast) end
        local n=m.nodes[id];if n and n.data then return n.data.toast end
    end
    local function nodeOnline(id) local n=m.nodes[id];return n and os.clock()-n.seen<30 end
    function m.startUpdate(only,version)
        local run={at=os.clock(),ids={},before={},target=version}
        local count=0
        for id,d in pairs(devices) do
            if only==nil or only==id then
                local e=m.entries[id]
                serial=math.max(serial+1,os.epoch("utc"),e and common.number(e.data.ack)+1 or 0)
                m.pending[id]={message={kind="command",action="update",serial=serial,target=version},at=os.clock(),job=d.job,ttl=180}
                dispatch(id,m.pending[id].message,d.job)
                if m.online(id) then run.ids[#run.ids+1]=id;run.before[id]=versionOf(id) end
                count=count+1
            end
        end
        local targets={}
        for pid in pairs(pockets) do targets[pid]=true end
        for nid,nd in pairs(m.nodes) do if nd.role=="repeater" or nd.role=="gps" or nd.role=="storage" then targets[nid]=true end end
        for nid in pairs(targets) do
            if only==nil or only==nid then
                serial=serial+1;count=count+1
                send(nid,{kind="update",version=1,controllerId=cfg.controllerId,serial=serial,target=version},common.remoteProtocol)
                if nodeOnline(nid) then run.ids[#run.ids+1]=nid;run.before[nid]=versionOf(nid) end
            end
        end
        save()
        if only==nil then
            m.updateRun=run
            m.notice="Update an "..count.." Geraete gesendet ..."
        end
        return true
    end
    -- done, total, fertig?
    function m.updateStatus()
        local r=m.updateRun;if not r then return nil end
        local done=0
        for _,id in ipairs(r.ids) do
            local v=versionOf(id)
            if v and ((r.target and v==r.target) or (not r.target and v~=r.before[id])) then done=done+1 end
        end
        return done,#r.ids
    end
    -- Nachzuegler (waren offline oder neu): aeltere Version als die Zentrale -> einzeln updaten
    m.healAt={}
    function m.heal()
        if m.updateRun then return end
        local function check(id,online)
            local v=versionOf(id)
            if online and v and v~="?" and common.newer(common.version,v) and os.clock()-(m.healAt[id] or -1e9)>300 then
                m.healAt[id]=os.clock();m.startUpdate(id,common.version)
            end
        end
        for id in pairs(devices) do check(id,m.online(id)) end
        for id,n in pairs(m.nodes) do if n.role=="repeater" or n.role=="gps" or n.role=="storage" or pockets[id] then check(id,nodeOnline(id)) end end
    end
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
    ["Fortsetzen"]="Startet",["Neuer Versuch"]="Startet",["Faellt Baum"]="Faellt",["Baeume pruefen"]="Prueft",
    ["Kampf"]="Kaempft",["Patrouille"]="Laeuft",["Sucht Baeume"]="Sucht",["Graebt"]="Graebt",
    ["Update"]="Update",["Kiste setzen"]="Kiste"}
-- Nur echte Probleme orange; alles andere ist normale Arbeit
local WARN={"fehlt","voll","blockiert","fehlgeschlagen","unklar","Kein","beendet","Gelaende","Problem","nicht"}
-- Nachschub fehlt (Lager voll, Treibstoff, Saatgut ...): kein Fehler, nur Pause
local PAUSE={"voll","Treibstoff","Fuel","Kohle","Saatgut","Fuellmaterial","Wandblock","Ausgabekiste","Lager fehlt","Baumaterial","Stufen fehlen","Falltueren fehlen","Wassereimer","Materialkiste"}
local function isPause(t)
    t=tostring(t or "")
    for _,k in ipairs(PAUSE) do if t:find(k,1,true) then return true end end
    return false
end
M.isPause=isPause
function M.state(e,link)
    local d=e and e.data
    if not link or not e or not e.online or not d then return "Offline","off" end
    if d.recovery then return "Pos. ?","fault" end
    if d.fault and isPause(d.fault) then return "Pause","pause" end
    if d.fault or d.status=="Rueckweg blockiert" then return "Fehler","fault" end
    if isPause(d.status) then return "Pause","pause" end
    local s=tostring(d.status or "")
    if WORK[s] then return WORK[s],"work" end
    if s=="Rueckkehr" then return "Heimweg","move" end
    if s=="Warten" then return "Wartet","wait" end
    if s=="Wache" then return "Wacht","wait" end
    if s=="Tagpause" then return "Tagpause","wait" end
    if s=="Fertig" then return "Fertig","done" end
    if s=="Bereit" or s=="Reset" or s=="" then return "Bereit","idle" end
    for _,k in ipairs(WARN) do if s:find(k,1,true) then return "Problem","warn" end end
    return (s:match("^(%S+)") or s):sub(1,8),"work"
end
local COLOR={work=colors.lime,move=colors.lightBlue,wait=colors.cyan,done=colors.green,
    idle=colors.lightGray,warn=colors.orange,fault=colors.red,off=colors.gray,pause=colors.orange}
M.COLOR=COLOR
local function num(n) return common.number(n) end
local function short(n)
    n=num(n)
    if math.abs(n)>=1000000 then return string.format("%.1fM",n/1000000) end
    if math.abs(n)>=10000 then return string.format("%.1fk",n/1000) end
    return tostring(math.floor(n))
end
-- Spielzeit "11:08" (leer, wenn nicht verfuegbar)
local function clockText()
    if not (textutils and textutils.formatTime and os.time) then return "" end
    local ok,t=pcall(function() return textutils.formatTime(os.time(),true) end)
    t=ok and tostring(t) or ""
    if #t==4 then t="0"..t end
    return t
end
M.clockText=clockText
-- Rechte Kopfzeile: laengste Variante, die in "room" Zeichen passt
local function headRight(room,online,total,clock)
    local opts={online.."/"..total.." online  "..clock.." ",online.."/"..total.." online "..clock.." ",
        online.."/"..total.."  "..clock.." ",online.."/"..total.." "..clock.." ",clock.." ",online.."/"..total.." "}
    if clock=="" then opts={online.."/"..total.." online ",online.."/"..total.." "} end
    for _,o in ipairs(opts) do if #o<=room then return o end end
    return ""
end
M.headRight=headRight
-- ===== Aufgaben: Name, Hauptwert und Detailzeilen je Job =====
local MOB_MODES={farm="Mobfarm",guard="Wache",patrol="Waechter"}
local function wait(rows,d) if num(d.wait)>0 then rows[#rows+1]={"Naechste",num(d.wait).." s"} end end
local JOB={
    farm={name="Farm",plural="Farmen",metric="Ertrag",unit="Items",once="1 Runde",
        value=function(d) return num(d.total) end,aux={"Geerntet",function(d) return num(d.harvested) end," Pfl."},
        rows=function(d) local r={{"Runden",short(d.rounds)}}
            if num(d.roundYield)>0 then r[#r+1]={"Diese Runde",short(d.roundYield).." Items"} end
            r[#r+1]={"Geerntet",short(d.harvested).." Pflanzen"};r[#r+1]={"Ertrag",short(d.total).." Items"}
            if num(d.seedsGained)>0 then r[#r+1]={" davon Samen",short(d.seedsGained)} end
            if not d.cane then r[#r+1]={"Saatgut",short(d.seeds)} end
            if d.pause then r[#r+1]={"Pause",(num(d.pause)>=120 and (math.floor(num(d.pause)/60+0.5).." min") or (num(d.pause).." s"))}
                if d.lastRipe then r[#r+1]={"Zuletzt reif",d.lastRipe.."%"} end end
            wait(r,d);return r end},
    mining={name="Mine",plural="Minen",metric="Abgebaut",unit="Bl.",once="1 Gang",
        value=function(d) return num(d.harvested) end,aux={"Abgeladen",function(d) return num(d.total) end," Items"},
        rows=function(d)
            -- Seitlich mitabbauen: Spuren (alle Ebenen) statt Gaenge zaehlen
            local total=num(d.lanes)>0 and d.lanes or d.tunnels
            local pct=num(d.cells)>0 and (" ("..math.floor(math.min(1,num(d.scanned)/num(d.cells))*100).."%)") or ""
            local r={{num(d.lanes)>0 and "Spuren" or "Gaenge",short(math.min(num(d.rounds),num(total)>0 and num(total) or num(d.rounds)))..(total and (" / "..total) or "").." fertig"..pct},
            {"Abgebaut",short(d.harvested).." Bloecke"},{"Abgeladen",short(d.total).." Items"},{"Freie Slots",short(d.freeSlots)}}
            if d.useCoal then r[#r+1]={"Kohle",short(d.coal).." verbrannt"} end
            if d.placeChests then r[#r+1]={"Kisten",short(d.chestsPlaced).." gesetzt, "..short(d.chestsLeft).." dabei"} end

            if num(d.torches)>0 then r[#r+1]={"Fackeln",short(d.torchesPlaced).." gesetzt, "..short(d.torchesLeft).." dabei"} end
            if num(d.keptOres)>0 then r[#r+1]={"Erze stehen",short(d.keptOres)..(num(d.oresMined)>0 and (", "..short(d.oresMined).." am Rand abgebaut") or "")} end
            if num(d.sealed)>0 then r[#r+1]={"Zugebaut",short(d.sealed).." Stellen"} end
            if num(d.drained)>0 then r[#r+1]={"Trockengelegt",short(d.drained)} end
            if d.noFill then r[#r+1]={"Fuellmaterial","FEHLT (Bruchstein)"} end
            return r end},
    tree={name="Holz",plural="Holzfarmen",metric="Holz",unit="Staemme",once="1 Runde",
        value=function(d) return num(d.total) end,aux={"Gefaellt",function(d) return num(d.harvested) end," Baeume"},
        rows=function(d) local r={{"Runden",short(d.rounds)},{"Gefaellt",short(d.harvested).." Baeume"},
            {"Holz",short(d.total).." Staemme"},{"Setzlinge",short(d.saplings)},{"Freie Slots",short(d.freeSlots)}}
            wait(r,d);return r end},
    mob={name="Mobs",plural="Mob-Turtles",metric="Drops",unit="Items",once="EINMAL",
        value=function(d) return num(d.total) end,aux={"Treffer",function(d) return num(d.hits) end,""},
        rows=function(d) local r={{"Art",MOB_MODES[d.mobMode] or "-"},{"Treffer",short(d.hits)},{"Drops",short(d.total).." abgeliefert"}}
            if num(d.carried)>0 then r[#r+1]={"Dabei",short(d.carried).." Items"} end
            if num(d.looted)>0 then r[#r+1]={"Aufgesammelt",short(d.looted).."x"} end
            if d.lastHit and num(d.hits)>0 then r[#r+1]={"Letzter Mob","vor "..short(d.lastHit).." s"} end
            if d.mobMode=="patrol" then r[#r+1]={"Ziele",short(d.targets).." angefahren"};r[#r+1]={"Tankrunden",short(d.rounds)};wait(r,d) end
            r[#r+1]={"Freie Slots",short(d.freeSlots)};return r end},
    build={name="Mobfarm-Bau",plural="Mobfarm-Bauer",metric="Verbaut",unit="Bl.",once="Bauen",
        value=function(d) return num(d.placed) end,aux={"Fortschritt",function(d) return num(d.cells)>0 and math.floor(num(d.scanned)/num(d.cells)*100) or 0 end,"%"},
        rows=function(d) local r={{"Farm",short(d.floors).." Etage(n), Schacht "..short(d.drop)..(d.creeperOnly and ", Creeper" or "")},
            {"Abschnitt",(d.done and "FERTIG" or tostring(d.phase or "-"))},
            {"Fortschritt",short(d.scanned).." / "..short(d.cells)},{"Verbaut",short(d.placed).." Bloecke"},
            {"Dabei",short(d.fill).." Stein, "..short(d.slabs).." Stufen"}}
            if d.creeperOnly then r[#r+1]={"Falltueren",d.trapFail and "gehen nicht (ohne weiter)" or (short(d.traps).." dabei")} end
            r[#r+1]={"Wassereimer",short(d.buckets).." dabei"}
            if d.missing then r[#r+1]={"Fehlt",tostring(d.missing)} end
            r[#r+1]={"Gesamt",short(d.need).." Stein, "..short(d.needSlab).." Stufen"}
            return r end},
    dig={name="Aushub",plural="Aushub-Turtles",metric="Abgebaut",unit="Bl.",once="1 Auftrag",
        value=function(d) return num(d.harvested) end,aux={"Abgeladen",function(d) return num(d.total) end," Items"},
        rows=function(d) local r={{"Form",(common.DIG_SHAPES[d.shape] or "-")..(d.digDir=="up" and " hoch" or " runter")},
            {"Fortschritt",short(d.scanned).." / "..short(d.cells)..(d.done and " FERTIG" or "")},
            {"Abgebaut",short(d.harvested).." Bloecke"},{"Abgeladen",short(d.total).." Items"}}
            if num(d.kept)>0 then r[#r+1]={"Erze stehen",short(d.kept)} end
            if num(d.sealed)>0 then r[#r+1]={"Zugebaut",short(d.sealed).." Stellen"} end
            if num(d.drained)>0 then r[#r+1]={"Trockengelegt",short(d.drained)} end
            if d.wallBlock then
                r[#r+1]={"Wandblock",(d.noWall and "FEHLT " or short(d.wall).." ")..tostring(d.wallBlock):gsub("^minecraft:","")}
                if num(d.lined)>0 then r[#r+1]={"Verkleidet",short(d.lined).." Bloecke"} end
            end
            r[#r+1]={"Fuellmaterial",d.noFill and "FEHLT" or short(d.fill)}
            r[#r+1]={"Freie Slots",short(d.freeSlots)};return r end},
}
local ORDER={"farm","mining","tree","mob","dig","build"}
M.JOB=JOB
local function jobOf(e) return JOB[e and e.job] and e.job or "mining" end
local function hasProgress(d) return num(d.cells)>0 end
local function progress(d) return math.max(0,math.min(1,num(d.scanned)/math.max(1,num(d.cells)))) end
-- Position: "12 vor, 3 rechts, 5 hoch" ab Basis + Koordinaten (GPS oder aus Basis)
local function posText(d)
    local r=d.rel;if type(r)~="table" then return nil end
    local p={}
    local function part(v,plus,minus) v=num(v);if v~=0 then p[#p+1]=math.abs(v).." "..(v>0 and plus or minus) end end
    part(r.fwd,"vor","zur.");part(r.right,"re","li");part(r.up,"hoch","tief")
    return #p==0 and "an der Basis" or table.concat(p," ")
end
M.posText=posText
local function coordText(d)
    local c=type(d.gps)=="table" and d.gps or type(d.pos)=="table" and d.pos
    if not c then return nil end
    return "X"..num(c.x).." Y"..num(c.y).." Z"..num(c.z)..(type(d.gps)=="table" and " GPS" or "")
end
M.coordText=coordText
local function common_rows(rows,d)
    local pt=posText(d);if pt then rows[#rows+1]={"Position",pt} end
    local ct=coordText(d);if ct then rows[#rows+1]={"Koordinaten",ct} end
    if d.toast then rows[#rows+1]={"Version",tostring(d.toast)..(d.toast~=common.version and (" (Zentrale "..common.version..")") or "")} end
    if d.dim then
        local names={overworld="Oberwelt",nether="Nether",["end"]="End"}
        local t=names[d.dim] or tostring(d.dim)
        if d.dimSet and d.dimSet~=d.dim then t=t.." (Config: "..(names[d.dimSet] or d.dimSet)..")" end
        rows[#rows+1]={"Dimension",t}
    end
    rows[#rows+1]={"Fuel",d.fuel=="unlimited" and "unbegrenzt" or short(d.fuel)}
    if d.chunks then rows[#rows+1]={"Chunks",d.chunks>0 and (d.chunks..", -"..short(d.chunkFuel).." Fuel/h") or "aus"} end
    return rows
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
    local clock=clockText()
    local tag=(e and JOB[jobOf(e)].name or "").." #"..id
    local rt=tag.."  "..clock.." "
    if #name+#rt+2>w then rt=clock~="" and (clock.." ") or (tag.." ") end
    if #name+#rt+2>w then name=name:sub(1,math.max(1,w-#rt-2)) end
    P.text(2,1,name,colors.white,colors.blue)
    P.right(1,rt,colors.white,colors.blue)
    if not e then
        P.text(1,3,"Turtle #"..id.." ist der Zentrale",colors.orange)
        P.text(1,4,"(noch) nicht bekannt.",colors.orange)
        P.text(1,6,"ID in toast.lua config pruefen.",colors.lightGray)
        return
    end
    -- Zustand als grosses Band
    P.fill(3,COLOR[kind]);P.fill(4,COLOR[kind])
    P.text(2,3,label,colors.black,COLOR[kind])
    local why=(kind=="fault" or kind=="warn" or kind=="pause") and (d.fault or d.status) or nil
    if why then P.text(2,4,tostring(why),colors.black,COLOR[kind]) end
    local det=kind=="off" and "Keine Meldung: Chunk entladen? An der Turtle: toast.lua config -> Chunks -> An der Basis wach = j (oder /forceload)" or tostring(d.detail or "")
    local y=6
    while #det>0 and y<=7 do P.text(1,y,det:sub(1,w),colors.lightGray);det=det:sub(w+1);y=y+1 end
    -- Fortschritt (nicht bei Mobfarm/Wache: dort gibt es keine Runde)
    y=9
    if hasProgress(d) then
        local pc=progress(d)
        P.text(1,y,"Fortschritt",colors.lightGray);P.right(y,math.floor(pc*100+0.5).."%",colors.white)
        y=y+1;P.bar(1,y,w,pc,kind=="off" and colors.gray or COLOR[kind])
        if h>=20 then y=y+1;P.bar(1,y,w,pc,kind=="off" and colors.gray or COLOR[kind]) end
        y=y+2
    end
    -- pro Stunde fuer diese Turtle
    local spec=JOB[jobOf(e)]
    st.hist=st.hist or {}
    local now=os.clock();local key=spec.value(d)
    local last=st.hist[#st.hist]
    if not last or now-last.t>=30 then st.hist[#st.hist+1]={t=now,v=key};while #st.hist>31 do table.remove(st.hist,1) end end
    local first=st.hist[1]
    local perH=(first and now-first.t>=60) and short(math.max(0,(key-first.v)/(now-first.t)*3600)) or "-"
    local rows=spec.rows(d)
    -- "pro Stunde" direkt hinter dem Hauptwert
    local at=#rows+1
    for i,r in ipairs(rows) do if r[1]==spec.metric then at=i+1 end end
    table.insert(rows,math.min(at,#rows+1),{spec.metric.." / Stunde",perH})
    common_rows(rows,d)
    -- zweispaltig, wenn breit genug
    local cols=w>=56 and 2 or 1
    local cw=math.floor(w/cols)
    local per=math.ceil(#rows/cols)
    for i,r in ipairs(rows) do
        local c=math.floor((i-1)/per);local yy=y+(i-1)%per
        if yy<=h-1 then
            local x=1+c*cw
            P.text(x,yy,r[1],colors.lightGray)
            P.text(x+cw-1-#r[2]-(cols>1 and c==0 and 2 or 0),yy,r[2],colors.white)
        end
    end
    P.right(h,"Infoscreen v"..common.version,colors.gray)
end
-- show: "all", "farm", "mining" oder Turtle-ID (Zahl)
function M.drawInfo(screen,fleet,link,st,show)
    if type(show)=="number" then return drawTurtleInfo(screen,fleet,link,st,show) end
    local P=painter(screen);local w,h=P.w,P.h
    screen.setBackgroundColor(colors.black);screen.clear()
    local entries=fleet.entries or {}
    if common.job(show) then
        local ids={}
        for _,id in ipairs(fleet.ids or {}) do if (entries[id] or {}).job==show then ids[#ids+1]=id end end
        fleet={ids=ids,entries=entries}
    end
    -- Summen je Aufgabe
    local G={}
    for _,j in ipairs(ORDER) do G[j]={n=0,act=0,value=0,aux=0,progSum=0,progN=0} end
    local fuel,chunk=0,0
    local problems,list={},{}
    for _,id in ipairs(fleet.ids or {}) do
        local e=entries[id] or {};local d=e.data or {}
        local job=jobOf(e);local g=G[job];local spec=JOB[job]
        local label,kind=M.state(e,link)
        g.n=g.n+1
        if kind=="work" or kind=="move" or kind=="wait" then g.act=g.act+1 end
        g.value=g.value+spec.value(d);g.aux=g.aux+spec.aux[2](d)
        if hasProgress(d) then g.progSum=g.progSum+progress(d);g.progN=g.progN+1 end
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
        local p={t=now};for _,j in ipairs(ORDER) do p[j]=G[j].value end
        st.hist[#st.hist+1]=p
        while #st.hist>31 do table.remove(st.hist,1) end
    end
    local function rate(key,cur)
        local first=st.hist[1]
        if not first or not first[key] or now-first.t<60 then return "-" end
        return short(math.max(0,(cur-first[key])/(now-first.t)*3600))
    end
    -- Kopf
    P.fill(1,colors.blue)
    local online=0;for _,l in ipairs(list) do if l.kind~="off" then online=online+1 end end
    local clock=clockText()
    local rt=link and headRight(w-7,online,#list,clock) or "keine Verbindung "
    local title=JOB[show] and JOB[show].plural or "Uebersicht"
    P.text(2,1,(#rt+10+#title<=w) and ("TOAST  "..title) or "TOAST",colors.white,colors.blue)
    P.right(1,rt,link and colors.white or colors.orange,colors.blue)
    -- Kacheln je Aufgabe (zwei nebeneinander, wenn Platz)
    local y=3
    local function panel(x,y0,pw,title,a,n,rows)
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
    local present={};for _,j in ipairs(ORDER) do if G[j].n>0 then present[#present+1]=j end end
    local side=w>=50 and #present>1
    -- Kleiner Bildschirm: nur die wichtigsten Zeilen, damit die Liste Platz hat
    local compact=(not side and h<26 and #present>1) or (h<26 and #present>2)
    local function rowsFor(j)
        local g,spec=G[j],JOB[j]
        local rows
        if compact then rows={{spec.metric,short(g.value).."  ("..rate(j,g.value).."/h)"}}
        else rows={{spec.metric,short(g.value).." "..spec.unit},{"pro Stunde",rate(j,g.value)},
            {spec.aux[1],short(g.aux)..spec.aux[3]}} end
        if g.progN>0 and (j=="mining" or not compact) then
            local pc=g.progSum/g.progN
            rows[#rows+1]={"Fortschritt",math.floor(pc*100+0.5).."%",bar=pc}
        end
        return rows
    end
    if side then
        local pw=math.floor((w-3)/2)
        for i=1,#present,2 do
            local a,b=present[i],present[i+1]
            local y1=panel(1,y,pw,JOB[a].name:upper(),G[a].act,G[a].n,rowsFor(a))
            local y2=b and panel(pw+4,y,w-pw-3,JOB[b].name:upper(),G[b].act,G[b].n,rowsFor(b)) or y1
            y=math.max(y1,y2)+(compact and 0 or 1)
        end
        if compact then y=y+1 end
    else
        for i,j in ipairs(present) do
            y=panel(1,y,w,JOB[j].name:upper(),G[j].act,G[j].n,rowsFor(j))
            if not compact or i==#present then y=y+1 end
        end
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
            local name=l.e.label~="" and l.e.label or (JOB[l.job].name.." #"..l.id)
            P.text(1,y,l.kind=="pause" and "!" or "\7",COLOR[l.kind])
            local stx=w-8
            local val=""
            if l.kind~="off" then val=short(JOB[l.job].value(d)) end
            if barW>0 then
                -- [Zustand] [gruener Balken] [Prozent] [Wert]
                local valW=w>=40 and 6 or 0
                local bx=w-valW-5-barW+1
                stx=bx-9
                if l.kind~="off" and hasProgress(d) then
                    local pc=progress(d)
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
    local fl=("Fuel "..short(fuel)..(chunk>0 and ("  Chunks -"..short(chunk).."/h") or ""))
    local ver="v"..common.version
    P.text(1,footer,fl:sub(1,w),colors.lightGray)
    if #fl+#ver+2<=w then P.right(footer,ver,colors.gray) end
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
        -- Knopf; height>1 = groesserer Knopf (leichter zu treffen am Monitor).
        -- Zwischen nebeneinanderliegenden Knoepfen bleibt 1 Spalte Luft (gap).
        local function button(x,y,width,label,action,bg,enabled,height,gap)
            if width<1 then return end
            height=height or 1
            local bw=width-(gap and width>4 and 1 or 0)
            local b=enabled and bg or colors.gray
            local l=tostring(label):sub(1,bw)
            local pad=math.floor((bw-#l)/2)
            local mid=y+math.floor((height-1)/2)
            for yy=y,y+height-1 do
                text(x,yy,string.rep(" ",bw),colors.white,b)
                ui.buttons[#ui.buttons+1]={x=x,y=yy,w=bw,action=action,enabled=enabled}
            end
            text(x+pad,mid,l,enabled and colors.white or colors.lightGray,b)
        end
        -- Schlichter, eckiger Knopf (einfarbig, Text mittig).
        local color=screen.isColor and screen.isColor()
        local function pill(x,y,width,label,action,bg,enabled,fgc)
            if width<1 then return end
            local b=enabled and bg or TRACK
            local f=fgc or (enabled and colors.white or colors.gray)
            if not enabled then f=colors.gray end
            if false then   -- runde Enden sahen im Spiel ausgefranst aus: eckig ist sauberer
                text(x,y,"\145",colors.black,b)
                text(x+1,y,string.rep(" ",width-2),f,b)
                text(x+width-1,y,"\157",b,colors.black)
                local l=tostring(label):sub(1,width-2)
                text(x+1+math.floor((width-2-#l)/2),y,l,f,b)
            else
                local l=tostring(label):sub(1,width)
                text(x,y,string.rep(" ",width),f,b)
                text(x+math.floor((width-#l)/2),y,l,f,b)
            end
            ui.buttons[#ui.buttons+1]={x=x,y=y,w=width,action=action,enabled=enabled}
        end
        screen.setBackgroundColor(colors.black);screen.setTextColor(colors.white);screen.clear()
        if not confirming() then ui.confirm=nil end
        if ui.help then
            fill(1,colors.blue);text(2,1,"TOAST - Tasten",colors.white,colors.blue)
            local L={{"\24 \25","Turtle waehlen"},{"Enter","Details oeffnen"},{"\27 Back","zurueck"},
                {"\27 \26 Tab","Reiter wechseln"},{"S","Start"},{"X","Stop"},{"E","einmal (1 Runde)"},
                {"R",w>=30 and "Reset (2x druecken)" or "Reset (2x)"},{"U","Update alle (2x)"},{"Bild\24\25","Seite blaettern"},{"H / ?","diese Hilfe"},{"Q","beenden"}}
            local kw=w>=34 and 11 or 9
            for i,l in ipairs(L) do
                if i+2>h-1 then break end
                text(2,i+2,l[1],colors.yellow);text(2+kw,i+2,l[2],colors.white)
            end
            text(1,h,("Taste druecken = weiter"):sub(1,w),colors.lightGray)
            right(1,"v"..common.version.." ",colors.white,colors.blue)
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
        local ids,count={},{}
        local g={}
        for _,j in ipairs(ORDER) do count[j]=0;g[j]={on=0,act=0,value=0} end
        local online,faults,chunkFuel=0,0,0
        for _,id in ipairs(fleet.ids or {}) do
            local e=entries[id] or {};local d=e.data or {}
            local job=jobOf(e)
            count[job]=count[job]+1
            local _,kind=M.state(e,link)
            local gg=g[job]
            gg.value=gg.value+JOB[job].value(d)
            if kind~="off" then gg.on=gg.on+1 end
            if kind=="work" or kind=="move" or kind=="wait" then gg.act=gg.act+1 end
            if ui.filter=="all" or job==ui.filter then
                ids[#ids+1]=id
                if kind~="off" then online=online+1 end
                if kind=="fault" or kind=="warn" then faults=faults+1 end
                if kind~="off" and num(d.chunks)>0 then chunkFuel=chunkFuel+num(d.chunkFuel) end
            end
        end
        -- Probleme zuerst, dann aktive, dann der Rest (sonst stabile Reihenfolge)
        local rank,pos={fault=1,warn=2,pause=2,work=3,move=3,wait=3,done=4,idle=4,off=5},{}
        for i,id in ipairs(ids) do local _,k=M.state(entries[id] or {},link);pos[id]=(rank[k] or 4)*10000+i end
        table.sort(ids,function(a,b) return pos[a]<pos[b] end)
        if ui.filter~="net" and ui.filter~="store" then
            ui.ids=ids
            if ui.selected and not common.contains(ids,ui.selected) then ui.selected=nil end
            if ui.cursor and not common.contains(ids,ui.cursor) then ui.cursor=nil end
            if not ui.cursor then ui.cursor=ui.selected or ids[1] end
        end
        -- Kopfzeile
        fill(1,colors.blue)
        if ui.storeOnly then
            -- Lager-Computer: nur die Lageransicht, oben Fuellstand + Uhr
            local nd=fleet.nodes or {ids={},entries={}}
            local sz,fl=0,0
            for _,nid in ipairs(nd.ids) do local st1=nd.entries[nid].data and nd.entries[nid].data.stats or {}
                sz=sz+num(st1.size);fl=fl+num(st1.pct)*num(st1.size) end
            text(2,1,"TOAST LAGER",colors.white,colors.blue)
            local clock=clockText()
            local r=(sz>0 and (math.floor(fl/sz+0.5).."% voll") or "").."  "..clock.." "
            if #r+13>w then r=clock.." " end
            right(1,r,colors.white,colors.blue)
            return ui.drawStore(nd,true,text,right,fill,pill,w,h,notice,2)
        end
        text(2,1,"TOAST",colors.white,colors.blue)
        -- Update-Knopf: alle Geraete holen sich die neue Version und machen weiter
        if ui.canUpdate~=false then
            local up=confirming() and ui.confirm.action=="update"
            local lab=up and "Sicher?" or "Update"
            local x=8
            text(x,1," "..lab.." ",up and colors.white or colors.blue,up and colors.red or colors.lightBlue)
            ui.buttons[#ui.buttons+1]={x=x,y=1,w=#lab+2,action="update",enabled=link}
        end
        -- rechts: online + Uhr (auf kleinen Pockets gekuerzt: "7/8 11:08")
        local room=w-(ui.canUpdate~=false and 16 or 7)
        local clock=clockText()
        if link and ui.filter=="net" and fleet.nodes then
            local on=0;for _,id in ipairs(fleet.nodes.ids) do if fleet.nodes.entries[id].online then on=on+1 end end
            right(1,headRight(room,on,#fleet.nodes.ids,clock),colors.white,colors.blue)
        elseif link then right(1,headRight(room,online,#ids,clock),colors.white,colors.blue)
        else right(1,(#clock>0 and room>=#clock+18) and ("keine Verbindung  "..clock.." ") or "keine Verbindung ",colors.orange,colors.blue) end
        -- Reiter
        -- Reiter: Alle + jede Aufgabe, die es gibt (Farm und Mine immer)
        local total=0;for _,j in ipairs(ORDER) do total=total+count[j] end
        local tabs={{"Alle",total,"all"}}
        for _,j in ipairs(ORDER) do
            if count[j]>0 or j=="farm" or j=="mining" or ui.filter==j then tabs[#tabs+1]={JOB[j].name,count[j],j} end
        end
        -- Netz: Repeater, GPS-Sender, Infoscreens, Pockets
        local nodes=fleet.nodes or {ids={},entries={}}
        local nStore=0;for _,nid in ipairs(nodes.ids) do if nodes.entries[nid].role=="storage" then nStore=nStore+1 end end
        if nStore>0 or ui.filter=="store" then tabs[#tabs+1]={"Lager",nStore,"store"} end
        if #nodes.ids>0 or ui.filter=="net" then tabs[#tabs+1]={"Netz",#nodes.ids,"net"} end
        ui.tabs={};for i,t in ipairs(tabs) do ui.tabs[i]=t[3] end
        local tw=math.floor(w/#tabs)
        for i,t in ipairs(tabs) do
            local active=ui.filter==t[3]
            local width=i==#tabs and w-(#tabs-1)*tw or tw
            local lab=t[1].." "..t[2]
            if #lab>width-2 then
                -- schmaler Bildschirm (Pocket): Kurzname + Anzahl, z.B. "M3"
                local SH={Alle="*",Farm="F",Mine="M",Holz="H",Mobs="Mo",Aushub="A",["Mobfarm-Bau"]="B",Lager="L",Netz="N"}
                local sh=SH[t[1]] or t[1]:sub(1,1)
                lab=(#t[1]<=width-1) and t[1] or ((#(sh..t[2])<=width-1) and (sh..t[2]) or sh)
            end
            local x=1+(i-1)*tw
            if active then pill(x,2,width,lab,"filter:"..t[3],colors.lightBlue,true,colors.black)
            else
                local l=lab:sub(1,width)
                text(x+math.floor((width-#l)/2),2,l,colors.lightGray,colors.black)
                ui.buttons[#ui.buttons+1]={x=x,y=2,w=width,action="filter:"..t[3],enabled=true}
            end
        end
        if ui.filter=="net" then return ui.drawNet(nodes,link,text,right,fill,pill,w,h,notice) end
        if ui.filter=="store" then return ui.drawStore(nodes,link,text,right,fill,pill,w,h,notice,3) end
        local third=math.floor(w/3)
        -- Fusszeile: Hinweiszeile + grosse Tastenreihe + untere Reihe
        -- Grosse Bildschirme bekommen hoehere Knoepfe (leichter zu treffen).
        local bh=1
        local foot=h-1-bh
        local sel=ui.selected and entries[ui.selected]
        local job=sel and jobOf(sel) or (ui.filter~="all" and ui.filter) or nil
        -- Was ist bei den Zielen gerade moeglich?
        local canStart,canStop,faultsT,running=false,false,0,0
        for _,id in ipairs(ids) do
            local e=entries[id]
            if (not ui.selected or ui.selected==id) and e then
                local d=e.data or {}
                local _,k=M.state(e,link)
                local active=d.mode=="auto" or d.mode=="once" or (d.mode==nil and (k=="work" or k=="move" or k=="wait"))
                if link and e.online and e.data and not d.recovery and not active then canStart=true end
                if link and e.online and active then canStop=true;running=running+1 end
                if link and (k=="fault" or k=="warn") then canStop=true;faultsT=faultsT+1 end
                if link and k=="pause" then canStop=true end
            end
        end
        ui.state={canStart=canStart,canStop=canStop,faults=faultsT,running=running}
        local startL="Start"
        local stopL="Stopp"
        local onceL=JOB[job] and JOB[job].once or "Einmal"
        onceL=onceL:sub(1,1)..onceL:sub(2):lower()
        local gap=w>=30 and 2 or 1
        local bw=math.floor((w-2*gap)/3)
        for i,b in ipairs({{startL,"start",colors.green,canStart},{stopL,"stop",colors.red,canStop},{onceL,"once",colors.blue,canStart}}) do
            local x=1+(i-1)*(bw+gap)
            pill(x,foot+1,i==3 and w-x+1 or bw,b[1],b[2],b[3],b[4])
        end
        local perPage
        -- ===== Detailansicht =====
        if sel then
            local d=sel.data or {}
            local label,kind=M.state(sel,link)
            local name=(sel.label and sel.label~="" and sel.label or JOB[jobOf(sel)].name).." #"..ui.selected
            local chests=type(d.chestList)=="table" and #d.chestList or 0
            if chests==0 and ui.detailView=="chests" then ui.detailView=nil end
            ui.chestView=ui.detailView=="chests"
            pill(1,3,math.min(w,#name+(w>=30 and 14 or 4)),(w>=30 and "\27 Zurueck  " or "\27 ")..name,"group",colors.gray,true)
            -- Reiter der Turtle: Info | Steuern | Einstellungen | Kisten
            local dtabs={{"Info","dv:info",nil},{w>=30 and "Steuern" or "Steuer","dv:drive","drive"},{w>=30 and "Einstellungen" or "Einst.","dv:config","config"}}
            if chests>0 then dtabs[#dtabs+1]={(w>=30 and "Kisten " or "K")..chests,"chests","chests"} end
            local tw2=math.floor(w/#dtabs)
            for i,t in ipairs(dtabs) do
                local act=ui.detailView==t[3]
                local width=i==#dtabs and w-(i-1)*tw2 or tw2-1
                pill(1+(i-1)*tw2,4,width,t[1],t[2],act and colors.lightBlue or colors.gray,true,act and colors.black or colors.white)
            end
            if ui.detailView=="chests" then
                -- Liste der gesetzten Abladekisten (scrollbar)
                local lines={}
                for _,k in ipairs(d.chestList) do
                    lines[#lines+1]={"Kiste "..tostring(k.n),colors.yellow}
                    local p=type(k.pos)=="table" and ("X:"..num(k.pos.x).." Y:"..num(k.pos.y).." Z:"..num(k.pos.z))
                        or (type(k.rel)=="table" and M.posText({rel=k.rel})) or "Position unbekannt"
                    lines[#lines+1]={p,colors.white}
                end
                local top=5
                local avail=math.max(2,foot-1-top);avail=avail-avail%2      -- immer ganze Kisten (2 Zeilen)
                ui.chestMax=math.max(0,#lines-avail)
                ui.chestScroll=math.max(0,math.min(ui.chestScroll or 0,ui.chestMax))
                if ui.chestScroll%2==1 then ui.chestScroll=ui.chestScroll-1 end
                for i=1,avail do
                    local l=lines[ui.chestScroll+i];if not l then break end
                    text(1,top+i-1,l[1]:sub(1,w-2),l[2])
                end
                if ui.chestMax>0 then
                    pill(w,top,1,"\24","cup",colors.gray,ui.chestScroll>0,colors.white)
                    pill(w,top+avail-1,1,"\25","cdown",colors.gray,ui.chestScroll<ui.chestMax,colors.white)
                end
            elseif ui.detailView=="drive" then
                ui.drawDrive(sel,d,link,text,right,fill,pill,button,w,foot)
            elseif ui.detailView=="config" then
                ui.drawConfig(sel,d,link,text,right,fill,pill,w,foot,fleet.configs and fleet.configs[ui.selected])
            else
            fill(5,COLOR[kind])
            local why=(kind=="fault" or kind=="warn" or kind=="pause") and (d.fault or d.status) or nil
            text(2,5,label..(why and (": "..tostring(why)) or ""),colors.black,COLOR[kind])
            -- Detailtext umbrechen (max. 2 Zeilen)
            local det=kind=="off" and "Keine Meldung: Chunk entladen? An der Turtle: toast.lua config -> Chunks -> An der Basis wach = j (oder /forceload)" or tostring(d.detail or "")
            local y=6
            while #det>0 and y<=7 do text(1,y,det:sub(1,w),colors.lightGray);det=det:sub(w+1);y=y+1 end
            y=8
            -- Fortschrittsbalken (nur wenn es eine Runde gibt)
            if hasProgress(d) then
                local pc=progress(d)
                local barW=math.max(4,w-6)
                local fillW=math.floor(barW*pc+0.5)
                text(1,y,string.rep(" ",fillW),colors.white,colors.lime)
                text(1+fillW,y,string.rep(" ",barW-fillW),colors.white,TRACK)
                right(y,math.floor(pc*100+0.5).."%",colors.white)
                y=y+2
            end
            local rows=common_rows(JOB[jobOf(sel)].rows(d),d)
            for _,r in ipairs(rows) do
                if y>=foot-1 then break end
                text(1,y,r[1],colors.lightGray);text(13,y,r[2],colors.white);y=y+1
            end
            end
        else
        -- ===== Uebersicht =====
            local y=3
            for _,j in ipairs(ORDER) do
                local gg=g[j]
                if count[j]>0 and (ui.filter=="all" or ui.filter==j) then
                    text(1,y,JOB[j].name,colors.white)
                    text(6,y,gg.act.."/"..count[j]..(w>=34 and " aktiv" or ""),gg.act>0 and colors.lime or colors.lightGray)
                    right(y,JOB[j].metric.." "..short(gg.value),colors.lightGray)
                    y=y+1
                end
            end
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
                local spec=JOB[jobOf(e)]
                local name=e.label and e.label~="" and e.label or (spec.name.." #"..id)
                local stW=8
                -- Rechts: [gruener Balken] [Prozent] [Wert] [Zustand]
                local barW=w>=70 and 20 or w>=44 and 10 or w>=34 and 6 or 0
                local value=wide and string.format("  %-8s%6s",spec.metric,short(spec.value(d))) or ""
                local block=barW>0 and (barW+5+#value) or 0      -- Balken + " 100%" + Wert
                local nameW=w-2-stW-1-(block>0 and block+1 or 0)
                local mark=ui.kbd and id==ui.cursor
                local bg=mark and colors.gray or colors.black
                local sc=(mark and kind=="off") and colors.lightGray or COLOR[kind]
                text(1,yy,string.rep(" ",w),colors.white,bg)
                text(1,yy,mark and "\16" or (kind=="pause" and "!" or "\7"),mark and colors.white or sc,bg)
                text(3,yy,name:sub(1,nameW),kind=="off" and (mark and colors.lightGray or colors.gray) or colors.white,bg)
                if block>0 and kind~="off" then
                    local x0=w-stW-block
                    if hasProgress(d) then
                        local pc=progress(d)
                        thinBar(text,x0,yy,barW,pc,colors.lime,bg)
                        text(x0+barW,yy,string.format("%4d%%",math.floor(pc*100+0.5)),mark and colors.white or colors.lightGray,bg)
                    end
                    if #value>0 then text(x0+barW+5,yy,value,mark and colors.white or colors.lightGray,bg) end
                end
                right(yy,string.format("%-8s",label),sc,bg)
                ui.buttons[#ui.buttons+1]={x=1,y=yy,w=w,action="id:"..id,enabled=true}
            end
        end
        -- Hinweiszeile + untere Tastenreihe
        local info=tostring(notice or "")
        if info:find("Warte auf Geraete",1,true) then info="" end
        local infoCol=colors.lightGray
        local goal=sel and "diese Turtle" or (ui.filter=="all" and "alle" or ("alle "..(JOB[ui.filter] and JOB[ui.filter].plural or ui.filter)))
        if confirming() and ui.confirm.action=="update" then
            info=w>=40 and "Alle Geraete updaten? Update nochmal tippen" or "Update? Nochmal tippen";infoCol=colors.cyan
        elseif confirming() then
            info=#goal+24<=w and ("Reset fuer "..goal.."? Nochmal = ja") or "Reset? Nochmal = ja";infoCol=colors.orange
        elseif info=="" or info:find("bestaetigt",1,true) then
            info="Ziel: "..goal
            local tip
            if ui.kbd then
                tip=sel and (w>=40 and "\24\25 Turtle  \27 zurueck  H Hilfe" or "\27 zurueck  H Hilfe")
                    or (w>=40 and "\24\25 Wahl  Enter Details  H Hilfe" or "\24\25 Enter  H Hilfe")
            else tip=not sel and "Tippen = Details" or nil end
            -- rechts die eigene Version (nicht bei Seitenzahl)
            local ver=((ui.pages or 1)>1 and not sel) and "" or (" v"..common.version)
            local W2=w-#ver
            if tip and #info+2+#tip<=W2 then info=info..string.rep(" ",W2-#info-#tip)..tip
            elseif tip and #tip<=W2 and ui.kbd and #info>W2 then info=tip end
            info=info:sub(1,W2)..string.rep(" ",math.max(0,W2-#info))
            if ver~="" then text(W2+1,foot,ver,colors.gray) end
        end
        text(1,foot,info:sub(1,w),infoCol)
        local pages=ui.pages or 1
        local sure=confirming() and ui.confirm.action=="reset"
        -- Reset: orange, wenn es Fehler gibt ("Fehler loeschen"), sonst unauffaellig grau
        -- Reset als dezenter Knopf: dunkelgrau, Schrift orange bei Fehlern, rot bei Nachfrage
        local function resetLabel(width)
            if sure then return width>=22 and "Sicher? Nochmal tippen" or "Sicher?" end
            if faultsT>0 then return width>=22 and "Fehler loeschen + heim" or width>=17 and "Fehler loeschen" or "Reset" end
            return width>=20 and "Reset (Stopp + heim)" or "Reset"
        end
        local rfg=sure and colors.white or (faultsT>0 and colors.orange or colors.lightGray)
        local rbg=sure and colors.red or colors.gray
        local y2=h
        if not sel and pages>1 then
            local pw=math.max(5,math.floor(w/6))
            pill(1,y2,pw,"\27","pageprev",colors.gray,ui.page>1,colors.white)
            pill(w-pw+1,y2,pw,"\26","pagenext",colors.gray,ui.page<pages,colors.white)
            local mw=w-2*pw-2*gap
            local lab=resetLabel(mw-2)
            pill(pw+gap+1,y2,mw,lab,"reset",rbg,link and #ids>0,rfg)
        else
            local lab=resetLabel(w-2)
            local rw=math.min(w,math.max(#lab+6,bw))
            pill(math.floor((w-rw)/2)+1,y2,rw,lab,"reset",rbg,link and #ids>0,rfg)
        end
        if not sel and pages>1 then right(foot,ui.page.."/"..pages,colors.gray) end
    end
    -- ===== Netz-Ansicht =====
    local NODE_NAMES={repeater="Repeater",gps="GPS-Sender",info="Infoscreen",pocket="Pocket",storage="Lager"}
    -- ===== Lager (Kistenueberwachung) =====
    -- Kisten mit Fuellstand oder Inhalt (alle Lager zusammen, mit Suche).
    -- Tippen auf ein Item zeigt, in welchen Kisten es liegt.
    local function fillColor(p,warn)
        p=num(p);if p>=100 then return colors.red elseif p>=num(warn or 90) then return colors.orange end
        return colors.lime
    end
    -- ===== Fernsteuerung: von Hand fahren =====
    local function bname(n)
        if not n then return "-" end
        n=tostring(n):gsub("^[^:]+:",""):gsub("_"," ")
        return n
    end
    function ui.drawDrive(sel,d,link,text,right,fill,pill,button,w,foot)
        local on=d.manual==true
        local can=link and sel.online and d.mode=="off" and not d.recovery
        local y=5
        if on and ui.endAsk then
            -- Beenden: zur Basis oder stehen bleiben?
            fill(y,colors.orange);text(2,y,"Steuerung beenden?",colors.black,colors.orange);y=y+2
            text(1,y,"Was soll die Turtle tun?",colors.white);y=y+2
            local bh=foot-1-y>=8 and 2 or 1
            button(1,y,w,"Zurueck zur Basis fahren","end:home",colors.blue,link,bh);y=y+bh+1
            button(1,y,w,"Hier stehen bleiben","end:park",colors.green,link,bh);y=y+bh+1
            button(1,y,w,"Abbrechen (weiter steuern)","end:cancel",colors.gray,true,bh)
            return
        end
        if on then
            fill(y,colors.lime);text(2,y,"Fernsteuerung AN",colors.black,colors.lime)
            local l=" Beenden "
            pill(w-#l+1,y,#l,l,"end:ask",colors.red,link,colors.white)
        elseif d.parked then
            fill(y,colors.yellow);text(2,y,"Abgestellt",colors.black,colors.yellow)
            local l=" Steuern "
            pill(w-#l+1,y,#l,l,"rc:manual_on",colors.green,can,colors.white)
            y=y+1
            text(1,y,"Steht, wo du sie abgestellt hast.",colors.lightGray);y=y+1
            text(1,y,"Start = erst heim, dann Arbeit.",colors.lightGray);y=y+2
            button(1,y,w,"Zur Basis fahren","rc:gohome",colors.blue,link and sel.online,2)
            return
        else
            fill(y,colors.gray);text(2,y,can and "Fernsteuerung aus" or (d.mode~="off" and "Erst stoppen" or "nicht erreichbar"),colors.white,colors.gray)
            local l=" Steuern "
            pill(w-#l+1,y,#l,l,"rc:manual_on",colors.green,can,colors.white)
        end
        y=y+1
        if on then
            text(1,y,"Vorne",colors.lightGray);text(8,y,bname(d.mFront):sub(1,w-8));y=y+1
            local ou="Oben "..bname(d.mUp):sub(1,math.floor(w/2)-6)
            text(1,y,ou,colors.lightGray);text(math.floor(w/2)+1,y,("Unten "..bname(d.mDown)):sub(1,w-math.floor(w/2)),colors.lightGray);y=y+1
            -- Modus: Abbau/Angriff <-> Bauen (Taste B oder Tab), im Bau-Modus Block (Taste T)
            local build=ui.driveMode=="build"
            local half=math.floor(w/2)
            pill(1,y,half-1,(build and "Bauen" or "Abbau/Angriff")..(ui.kbd and " B" or ""),"dm:toggle",build and colors.green or colors.brown,true,colors.white)
            if build then
                local nl=(w>=30 and "Naechster Block" or "Block \26")..(ui.kbd and " T" or "")
                pill(half+1,y,w-half,nl,"rc:nextblock",colors.blue,link,colors.white)
                y=y+1
                local bl=d.mBlock and (bname(d.mBlock)..(d.mBlockN and (" x"..d.mBlockN) or "")) or "kein Block (nach 'Steuern' einlegen)"
                text(1,y,("Setzt: "..bl):sub(1,w),d.mBlock and colors.white or colors.orange)
            else
                text(half+1,y,("Hand "..bname(d.mLeft)):sub(1,w-half),colors.gray)
            end
            y=y+1
        else
            text(1,y,"Turtle stoppen, dann 'Steuern'.",colors.lightGray);y=y+1
            text(1,y,"Beenden = sie faehrt zur Basis.",colors.lightGray);y=y+1
            y=y+1
        end
        local msg=tostring(d.mMsg or "")
        text(1,y,msg:sub(1,w),msg:find("Geht nicht",1,true) and colors.orange or colors.cyan);y=y+1
        -- Steuerkreuz 3x3 (Tasten in Klammern):
        --   Hoch(E)      Vor(W)        oben(R)
        --   Links(A)     Leertaste     Rechts(D)
        --   Runter(C)    Zurueck(S)    unten(F)
        -- Mitte/oben/unten = abbauen ODER angreifen, je nach Werkzeug (Schwert = Angriff)
        local sword=tostring(d.mLeft or ""):find("sword",1,true) or tostring(d.mRight or ""):find("sword",1,true)
        local use=sword and "Angriff" or "Abbau"
        local k=ui.kbd
        local function L(long,short,key) local s=w>=30 and long or short;return k and (s.." "..key) or s end
        local u3=sword and "Ang" or "Abb"
        local uc=sword and colors.red or colors.brown
        if ui.driveMode=="build" then use,u3,uc="Setzen","Setz",colors.green end
        local grid={
            {{L("Hoch","Hoch","E"),"up",colors.cyan},{L("\24 Vor","\24 Vor","W"),"forward",colors.blue},{L(use.." \24",u3.." \24","R"),"useUp",colors.brown}},
            {{L("\27 Links","\27 Links","A"),"left",colors.blue},{L(use,ui.driveMode=="build" and "Setzen" or (sword and "Angr." or "Abbau"),"[ ]"),"use",uc},{L("Rechts \26","Rechts\26","D"),"right",colors.blue}},
            {{L("Runter","Runter","C"),"down",colors.cyan},{L("\25 Zurueck","\25 Zur.","S"),"back",colors.blue},{L(use.." \25",u3.." \25","F"),"useDown",colors.brown}},
        }
        local free=foot-1-y
        local bh=free>=9 and 3 or free>=6 and 2 or 1
        local cw=math.floor(w/3)
        for _,r in ipairs(grid) do
            if y+bh-1>foot-1 then break end
            for i,b in ipairs(r) do
                local x=1+(i-1)*cw
                local width=i==3 and w-x+1 or cw
                button(x,y,width,b[1],"rc:"..b[2],b[3],on and link,bh,true)
            end
            y=y+bh
        end
        if y<=foot-1 and not k then
            text(1,y,(w>=36 and "Tastatur: WASD, Leer, E/C, R/F, B Modus, T Block" or "WASD Leer E/C R/F B T"):sub(1,w),colors.gray)
        end
    end
    -- ===== Fernsteuerung: Einstellungen abrufen/aendern =====
    ui.cfgEdits={}
    local function cfgLines(cf,id)
        local ed=ui.cfgEdits[id] or {values={}}
        local L={}
        local jobs=cf.jobs or common.JOBS
        L[#L+1]={kind="job",label="Aufgabe",value=ed.job or cf.job,opts=jobs,changed=ed.job~=nil}
        L[#L+1]={kind="name",label="Name",value=ed.name or cf.name or "",changed=ed.name~=nil}
        for _,sec in ipairs(cf.sections or {}) do
            L[#L+1]={kind="title",label=sec.title or sec.name}
            for _,f in ipairs(sec.fields or {}) do
                local ev=ed.values[sec.name] and ed.values[sec.name][f.k]
                local v=ev;if v==nil then v=f.v end
                L[#L+1]={kind="field",sec=sec.name,k=f.k,label=f.d or f.k,value=v,opts=f.o,changed=ev~=nil,orig=f.v}
            end
        end
        return L
    end
    local function showVal(l)
        local v=l.value
        if l.kind=="job" then return common.JOB_NAMES[v] or tostring(v) end
        if type(v)=="boolean" then return v and "ja" or "nein" end
        if v=="" then return "-" end
        return tostring(v)
    end
    function ui.drawConfig(sel,d,link,text,right,fill,pill,w,foot,cfgEntry)
        local id=ui.selected
        local y=5
        fill(y,colors.gray);text(2,y,"Einstellungen",colors.white,colors.gray)
        local rl=w>=30 and " Neu laden " or " Laden "
        pill(w-#rl+1,y,#rl,rl,"rc:getconfig",colors.blue,link and sel.online,colors.white)
        y=y+1
        local cf=cfgEntry and cfgEntry.config
        if not cf then
            text(1,y+1,"Lade Einstellungen ...",colors.lightGray)
            text(1,y+2,link and sel.online and "(Turtle muss erreichbar sein)" or "Turtle nicht erreichbar",colors.gray)
            return
        end
        local L=cfgLines(cf,id)
        ui.cfgLinesCache=L
        -- unten: Beschreibung, Bearbeiten, Speichern
        local editY=foot-3
        local listTop,listBot=y,editY-1
        local avail=listBot-listTop+1
        ui.cfgSel=ui.cfgSel or 1
        if not L[ui.cfgSel] or L[ui.cfgSel].kind=="title" then
            for i,l in ipairs(L) do if l.kind~="title" then ui.cfgSel=i;break end end
        end
        ui.cfgScroll=ui.cfgScroll or 0
        if ui.cfgSel<=ui.cfgScroll then ui.cfgScroll=ui.cfgSel-1 end
        if ui.cfgSel>ui.cfgScroll+avail then ui.cfgScroll=ui.cfgSel-avail end
        ui.cfgScroll=math.max(0,math.min(ui.cfgScroll,math.max(0,#L-avail)))
        for i=1,avail do
            local idx=ui.cfgScroll+i;local l=L[idx];if not l then break end
            local yy=listTop+i-1
            if l.kind=="title" then
                text(1,yy,("- "..l.label):sub(1,w),colors.cyan)
            else
                local val=showVal(l)
                local selc=idx==ui.cfgSel
                local bg=selc and colors.gray or colors.black
                local vw=math.min(#val,math.floor(w/2))
                text(1,yy,string.rep(" ",w),colors.white,bg)
                text(1,yy,l.label:sub(1,w-vw-1),colors.lightGray,bg)
                text(w-vw+1,yy,val:sub(1,vw),l.changed and colors.yellow or colors.white,bg)
                ui.buttons[#ui.buttons+1]={x=1,y=yy,w=w-1,action="cf:sel:"..idx,enabled=true}
            end
        end
        if #L>avail then
            pill(w,listTop,1,"\24","cf:scroll:-1",colors.gray,ui.cfgScroll>0,colors.white)
            pill(w,listBot,1,"\25","cf:scroll:1",colors.gray,ui.cfgScroll<#L-avail,colors.white)
        end
        -- Bearbeiten
        local l=L[ui.cfgSel]
        local msgOk=cfgEntry.msg and os.clock()-(cfgEntry.at or 0)<20
        if msgOk then text(1,editY,tostring(cfgEntry.msg):sub(1,w),cfgEntry.ok==false and colors.orange or colors.lime)
        elseif l then text(1,editY,(l.k and (l.k..": ") or "")..tostring(l.label):sub(1,w),colors.gray) end
        local ey=editY+1
        if l and l.kind~="title" then
            local v=l.value
            if l.kind=="job" or (l.opts and type(v)=="string") then
                local q=math.floor(w/4)
                pill(1,ey,q,"\27","cf:opt:-1",colors.blue,true,colors.white)
                local vs=showVal(l);text(q+1+math.floor((w-2*q-#vs)/2),ey,vs:sub(1,w-2*q),colors.yellow)
                pill(w-q+1,ey,q,"\26","cf:opt:1",colors.blue,true,colors.white)
            elseif type(v)=="boolean" then
                pill(1,ey,w,v and "ja  (tippen = nein)" or "nein  (tippen = ja)","cf:toggle",colors.blue,true,colors.white)
            elseif type(v)=="number" then
                local q=math.floor(w/4)
                for i,st in ipairs({{"-10",-10},{"-1",-1},{"+1",1},{"+10",10}}) do
                    pill(1+(i-1)*q,ey,i==4 and w-3*q or q-1,st[1],"cf:add:"..st[2],colors.blue,true,colors.white)
                end
            else
                text(1,ey,(ui.kbd and "Tastatur: tippen, Back = loeschen" or "Text: am Pocket/PC tippen"):sub(1,w-8),colors.lightGray)
                pill(w-6,ey,7,"Leeren","cf:clear",colors.gray,true,colors.white)
            end
        end
        local ed=ui.cfgEdits[id]
        local dirty=ed and (ed.job or ed.name or next(ed.values or {}))
        local half=math.floor(w/2)
        pill(1,foot-1,half-1,"Speichern","cf:save",colors.green,dirty and link and sel.online and true or false,colors.white)
        pill(half+1,foot-1,w-half,"Verwerfen","cf:discard",colors.gray,dirty and true or false,colors.white)
    end
    local function cfgEdit(id) ui.cfgEdits[id]=ui.cfgEdits[id] or {values={}};return ui.cfgEdits[id] end
    local function cfgSet(l,v)
        l.value=v;l.changed=true          -- sofort sichtbar (auch ohne Neuzeichnen dazwischen)
        local ed=cfgEdit(ui.selected)
        if l.kind=="job" then ed.job=v
        elseif l.kind=="name" then ed.name=v
        else
            ed.values[l.sec]=ed.values[l.sec] or {}
            if v==l.orig then ed.values[l.sec][l.k]=nil;if not next(ed.values[l.sec]) then ed.values[l.sec]=nil end
            else ed.values[l.sec][l.k]=v end
        end
    end
    -- Aktionen der Fernsteuerung -> nil oder {id=,payload=} (an die Turtle)
    function ui.remoteAction(a)
        local id=ui.selected;if not id then return end
        if a:match("^rc:") then
            local op=a:sub(4)
            if ui.driveMode=="build" then
                op=({use="place",useUp="placeUp",useDown="placeDown"})[op] or op
            end
            return {id=id,payload={op=op}}
        end
        local L=ui.cfgLinesCache or {}
        local l=L[ui.cfgSel or 0]
        if a:match("^cf:sel:") then ui.cfgSel=tonumber(a:sub(8));return end
        if a:match("^cf:scroll:") then ui.cfgScroll=(ui.cfgScroll or 0)+tonumber(a:sub(11));return end
        if a=="cf:discard" then ui.cfgEdits[id]=nil;return end
        if a=="cf:save" then
            local ed=ui.cfgEdits[id];if not ed then return end
            ui.cfgEdits[id]=nil
            return {id=id,payload={op="setconfig",job=ed.job,name=ed.name,values=ed.values}}
        end
        if not l or l.kind=="title" then return end
        if a=="cf:toggle" and type(l.value)=="boolean" then cfgSet(l,not l.value)
        elseif a:match("^cf:add:") and type(l.value)=="number" then cfgSet(l,l.value+tonumber(a:sub(8)))
        elseif a:match("^cf:opt:") then
            local opts=l.opts;if not opts then return end
            local i=1;for k,o in ipairs(opts) do if o==l.value then i=k end end
            i=(i-1+tonumber(a:sub(8)))%#opts+1;cfgSet(l,opts[i])
        elseif a=="cf:clear" and (l.kind=="name" or type(l.value)=="string") then cfgSet(l,"")
        end
    end
    -- Texteingabe im Einstellungs-Reiter (freie Texte, z.B. keepOres, Name)
    local function cfgTextField()
        if ui.detailView~="config" or not ui.selected then return end
        local l=(ui.cfgLinesCache or {})[ui.cfgSel or 0]
        if l and (l.kind=="name" or (l.kind=="field" and type(l.value)=="string" and not l.opts)) then return l end
    end
    -- Texteingabe / Steuermodus: Q beendet dann nicht das Programm
    function ui.textInput() return ui.filter=="store" or cfgTextField()~=nil or (ui.selected~=nil and ui.detailView=="drive") end
    function ui.drawStore(nodes,link,text,right,fill,pill,w,h,notice,y0)
        ui.ids={};ui.selected=nil
        local stores={}
        for _,id in ipairs(nodes.ids or {}) do
            local e=nodes.entries[id]
            if e.role=="storage" then stores[#stores+1]={id=id,e=e,st=(e.data and e.data.stats) or {}} end
        end
        ui.storeView=ui.storeView or "chests"
        ui.search=ui.search or ""
        local y=y0 or 3
        -- Umschalter Kisten / Inhalt
        local half=math.floor(w/2)
        local isC=ui.storeView=="chests" and not ui.storeItem
        pill(1,y,half-1,"Kisten","sview:chests",isC and colors.lightBlue or colors.gray,true,isC and colors.black or colors.white)
        pill(half+1,y,w-half,"Inhalt","sview:items",(not isC) and colors.lightBlue or colors.gray,true,(not isC) and colors.black or colors.white)
        y=y+1
        if #stores==0 then
            text(1,y+1,"Noch kein Lager gemeldet.",colors.lightGray)
            text(1,y+2,"Computer an die Kisten stellen",colors.lightGray)
            text(1,y+3,"(oder per Netzwerkkabel) und",colors.lightGray)
            text(1,y+4,"als 5 'Lager' installieren.",colors.lightGray)
            return
        end
        local multi=#stores>1
        local rows={}
        if ui.storeItem then
            -- Wo liegt das Item?
            local name,total=ui.storeItem,0
            local where={}
            for _,s in ipairs(stores) do
                for _,it in ipairs(s.st.items or {}) do
                    if it.id==ui.storeItem then
                        name=it.n or it.id;total=total+num(it.c)
                        for _,wh in ipairs(it.w or {}) do
                            local ch=(s.st.chests or {})[wh.i] or {}
                            where[#where+1]={label=(multi and ((s.e.label~="" and s.e.label or ("Lager #"..s.id)).." / ") or "")..tostring(ch.n or ("Kiste "..wh.i)),c=num(wh.c),p=ch.p}
                        end
                    end
                end
            end
            pill(1,y,math.min(w,#name+(w>=30 and 12 or 3)),(w>=30 and "\27 Zurueck  " or "\27 ")..name,"sback",colors.gray,true)
            y=y+1
            text(1,y,"Gesamt",colors.lightGray);right(y,short(total).." Stueck",colors.white);y=y+1
            for _,wh in ipairs(where) do rows[#rows+1]={kind="where",label=wh.label,c=wh.c,p=wh.p} end
            if #where==0 then rows[1]={kind="note",label="Nicht mehr im Lager."} end
        elseif ui.storeView=="chests" then
            for _,s in ipairs(stores) do
                local st=s.st
                local lname=s.e.label~="" and s.e.label or ("Lager #"..s.id)
                rows[#rows+1]={kind="head",label=lname..(s.e.online and "" or " (offline)"),p=st.pct,warn=st.warn,
                    info=short(st.count).." Kisten, "..short(st.types).." Sorten",on=s.e.online}
                for _,ch in ipairs(st.chests or {}) do
                    rows[#rows+1]={kind="chest",label=tostring(ch.n),p=ch.p,warn=st.warn,slots=num(ch.u).."/"..num(ch.s)}
                end
            end
        else
            -- Inhalt aller Lager, zusammengezaehlt, mit Suche
            local byId,list={},{}
            for _,s in ipairs(stores) do
                for _,it in ipairs(s.st.items or {}) do
                    local e=byId[it.id]
                    if not e then e={id=it.id,n=tostring(it.n or it.id),c=0,first=nil};byId[it.id]=e;list[#list+1]=e end
                    e.c=e.c+num(it.c)
                    if not e.first and it.w and it.w[1] then local ch=(s.st.chests or {})[it.w[1].i];e.first=ch and ch.n end
                end
            end
            local q=ui.search:lower()
            local shown={}
            for _,e in ipairs(list) do
                if q=="" or e.n:lower():find(q,1,true) or e.id:lower():find(q,1,true) then shown[#shown+1]=e end
            end
            table.sort(shown,function(a,b) return a.c>b.c end)
            if ui.kbd or q~="" then
                text(1,y,"Suche: ",colors.lightGray);text(8,y,(q~="" and q or "")..(ui.kbd and "_" or ""),colors.yellow)
                right(y,#shown.." Sorten",colors.lightGray);y=y+1
            end
            for _,e in ipairs(shown) do rows[#rows+1]={kind="item",label=e.n,c=e.c,id=e.id,first=e.first} end
            if #shown==0 then rows[1]={kind="note",label=q~="" and ("Nichts gefunden: "..q) or "Lager ist leer."} end
        end
        -- Seiten
        local avail=math.max(1,h-y)
        local pages=math.max(1,math.ceil(#rows/avail))
        ui.page=math.max(1,math.min(ui.page or 1,pages));ui.storePages=pages
        local first=(ui.page-1)*avail
        for i=1,avail do
            local r=rows[first+i];if not r then break end
            local yy=y+i-1
            if r.kind=="head" then
                local pc=string.format("%3d%%",num(r.p))
                text(1,yy,r.label:sub(1,w-6),r.on and colors.white or colors.gray)
                right(yy,pc,fillColor(r.p,r.warn))
                if w>=40 then text(math.max(#r.label+3,w-6-#r.info-1),yy,r.info,colors.lightGray) end
            elseif r.kind=="chest" or r.kind=="where" then
                local nameW=math.min(w>=40 and 18 or 10,math.max(6,w-16))
                local tail=r.kind=="where" and short(r.c) or string.format("%3d%%",num(r.p))
                local barX=nameW+3
                local barW=w-barX-#tail-1
                text(2,yy,r.label:sub(1,nameW),colors.white)
                if r.kind=="chest" and barW>=3 then thinBar(text,barX,yy,barW,num(r.p)/100,fillColor(r.p,r.warn),colors.black)
                elseif r.kind=="where" and r.p and barW>=3 then thinBar(text,barX,yy,barW,num(r.p)/100,fillColor(r.p,90),colors.black) end
                right(yy,tail,r.kind=="chest" and fillColor(r.p,r.warn) or colors.white)
            elseif r.kind=="item" then
                local cnt=short(r.c)
                local loc=(w>=44 and r.first) and tostring(r.first) or nil
                local nameW=w-#cnt-2-(loc and (#loc+2) or 0)
                text(1,yy,r.label:sub(1,nameW),colors.white)
                if loc then text(w-#cnt-#loc-2,yy,loc,colors.gray) end
                right(yy,cnt,colors.lightGray)
                ui.buttons[#ui.buttons+1]={x=1,y=yy,w=w,action="sitem:"..r.id,enabled=true}
            else text(1,yy,r.label:sub(1,w),colors.lightGray) end
        end
        -- Fusszeile
        if pages>1 then
            local pw=math.max(4,math.floor(w/6))
            pill(1,h,pw,"\27","pageprev",colors.gray,ui.page>1,colors.white)
            pill(w-pw+1,h,pw,"\26","pagenext",colors.gray,ui.page<pages,colors.white)
            local m=ui.page.."/"..pages
            text(math.floor((w-#m)/2)+1,h,m,colors.lightGray)
        else
            local info=tostring(notice or "")
            if info:find("Warte auf",1,true) or info:find("bestaetigt",1,true) or info:find("Verbunden",1,true) then info="" end
            if info=="" then
                info=ui.storeItem and "Zurueck: Pfeil links / Backspace"
                    or (ui.storeView=="items" and (ui.kbd and "Tippen = suchen, Item = wo liegt es" or "Item antippen = wo liegt es")
                    or (w>=30 and "Orange = fast voll, Rot = voll" or "Orange fast voll, Rot voll"))
            end
            local ver=" v"..common.version
            if #info+#ver<=w then text(1,h,info,colors.lightGray);text(w-#ver+1,h,ver,colors.gray)
            else text(1,h,info:sub(1,w),colors.lightGray) end
        end
    end
    function ui.drawNet(nodes,link,text,right,fill,pill,w,h,notice)
        local ids=nodes.ids
        ui.ids=ids
        if ui.selected and not common.contains(ids,ui.selected) then ui.selected=nil end
        if ui.cursor and not common.contains(ids,ui.cursor) then ui.cursor=nil end
        if not ui.cursor then ui.cursor=ui.selected or ids[1] end
        local function coords(d)
            local p=d and d.pos;if type(p)~="table" then return nil end
            return "X"..num(p.x).." Y"..num(p.y).." Z"..num(p.z)
        end
        local foot=h-1
        local sel=ui.selected and nodes.entries[ui.selected]
        if sel then
            local d=sel.data or {}
            local name=(sel.label~="" and sel.label or NODE_NAMES[sel.role] or "Geraet").." #"..ui.selected
            pill(1,3,math.min(w,#name+(w>=30 and 14 or 4)),(w>=30 and "\27 Zurueck  " or "\27 ")..name,"group",colors.gray,true)
            local kind=sel.online and "done" or "off"
            fill(4,COLOR[kind])
            text(2,4,sel.online and "Online" or "Offline - keine Meldung seit 30 s",colors.black,COLOR[kind])
            local rows={{"Typ",NODE_NAMES[sel.role] or tostring(sel.role)},
                {"Version",tostring(d.toast)..((d.toast and d.toast~=common.version) and (" (Zentrale "..common.version..")") or "")}}
            local c=coords(d)
            rows[#rows+1]={"Koordinaten",c and (c..(d.pos.src and (" "..d.pos.src) or "")) or "unbekannt"}
            local st=d.stats or {}
            if st.gps then rows[#rows+1]={"GPS-Anfragen",short(st.gps)} end
            if st.repeated then rows[#rows+1]={"Weitergeleitet",short(st.repeated).." Nachrichten"} end
            local y=6
            for _,r in ipairs(rows) do if y<foot then text(1,y,r[1],colors.lightGray);text(15,y,r[2],colors.white);y=y+1 end end
        else
            local y=3
            if #ids==0 then
                text(1,y+1,"Keine Netzgeraete gemeldet.",colors.lightGray)
                text(1,y+2,"Repeater/GPS-Sender melden sich",colors.lightGray)
                text(1,y+3,"nach dem Update auf 3.4 selbst.",colors.lightGray)
            end
            local avail=foot-y
            for row=1,avail do
                local id=ids[row];if not id then break end
                local e=nodes.entries[id];local d=e.data or {}
                local yy=y+row-1
                local mark=ui.kbd and id==ui.cursor
                local bg=mark and colors.gray or colors.black
                text(1,yy,string.rep(" ",w),colors.white,bg)
                text(1,yy,mark and "\16" or "\7",e.online and colors.lime or colors.gray,bg)
                local name=e.label~="" and e.label or ((NODE_NAMES[e.role] or "Geraet").." #"..id)
                local typ=NODE_NAMES[e.role] or e.role
                local c=coords(d)
                if w>=60 then
                    text(3,yy,name:sub(1,24),e.online and colors.white or colors.gray,bg)
                    text(29,yy,typ,colors.lightGray,bg)
                    if c then text(42,yy,c,colors.lightGray,bg) end
                    right(yy,(e.online and "" or "Offline ").."v"..tostring(d.toast),e.online and colors.lightGray or colors.gray,bg)
                else
                    text(3,yy,name:sub(1,w-13),e.online and colors.white or colors.gray,bg)
                    right(yy,e.online and typ:sub(1,10) or "Offline",e.online and colors.lightGray or colors.gray,bg)
                end
                ui.buttons[#ui.buttons+1]={x=1,y=yy,w=w,action="id:"..id,enabled=true}
            end
        end
        local info=tostring(notice or "")
        if info:find("Warte auf Geraete",1,true) or info:find("bestaetigt",1,true) then info="" end
        if info=="" then info=sel and "Update oben aktualisiert alle Geraete" or "Tippen = Details, Position, Version" end
        local ver=" v"..common.version
        if #info+#ver<=w then info=info..string.rep(" ",w-#info-#ver) end
        text(1,h,info:sub(1,w),colors.lightGray)
        if #info+#ver<=w+#ver and #info<=w-#ver then text(w-#ver+1,h,ver,colors.gray) end
    end
    local function indexOf(id) for i,v in ipairs(ui.ids) do if v==id then return i end end return 0 end
    function ui.action(a)
        if not a then return end
        if a~="reset" and a~="update" then ui.confirm=nil end
        if a=="redraw" then return
        elseif type(a)=="string" and (a:match("^rc:") or a:match("^cf:")) then return ui.remoteAction(a)
        elseif a=="dm:toggle" then ui.driveMode=ui.driveMode=="build" and "use" or "build";return
        elseif a=="end:ask" then ui.endAsk=true;return
        elseif a=="end:cancel" then ui.endAsk=nil;return
        elseif a=="end:home" or a=="end:park" then
            ui.endAsk=nil
            if ui.selected then return {id=ui.selected,payload={op=a=="end:home" and "manual_off" or "manual_park"}} end
            return
        elseif a=="dv:info" then ui.detailView=nil;return
        elseif a=="dv:drive" then ui.detailView="drive";return
        elseif a=="dv:config" then
            ui.detailView="config";ui.cfgSel=nil;ui.cfgScroll=0
            if ui.selected then return {id=ui.selected,payload={op="getconfig"}} end
            return
        elseif a=="chests" then ui.detailView=ui.detailView~="chests" and "chests" or nil;ui.chestView=ui.detailView=="chests";ui.chestScroll=0;return
        elseif a=="cup" or a=="cdown" or (ui.chestView and ui.selected and (a=="up" or a=="down" or a=="pageprev" or a=="pagenext")) then
            local d=(a=="cup" or a=="up" or a=="pageprev") and -2 or 2
            if a=="pageprev" or a=="pagenext" then d=d*4 end
            ui.chestScroll=math.max(0,math.min(ui.chestMax or 0,(ui.chestScroll or 0)+d));return
        elseif a:match("^sview:") then ui.storeView=a:sub(7);ui.storeItem=nil;ui.page=1;return
        elseif a:match("^sitem:") then ui.storeItem=a:sub(7);ui.page=1;return
        elseif a=="sback" then ui.storeItem=nil;return
        elseif ui.filter=="store" and (a=="up" or a=="down") then
            if a=="up" then ui.page=math.max(1,(ui.page or 1)-1) else ui.page=math.min(ui.storePages or 1,(ui.page or 1)+1) end
            return
        elseif ui.filter=="store" and a=="group" then
            if ui.storeItem then ui.storeItem=nil elseif (ui.search or "")~="" then ui.search=ui.search:sub(1,-2);ui.page=1 end
            return
        elseif a=="help" then ui.help=not ui.help
        elseif a:match("^filter:") then ui.filter=a:sub(8);ui.selected=nil;ui.page=1;ui.cursor=nil
        elseif a:match("^id:") then ui.selected=tonumber(a:sub(4));ui.cursor=ui.selected;ui.chestView=nil;ui.detailView=nil
        elseif a=="group" then
            if ui.detailView then ui.detailView=nil;ui.chestView=nil;return end
            ui.cursor=ui.selected or ui.cursor;ui.selected=nil;ui.followCursor=true
        elseif a=="pageprev" then ui.page=math.max(1,ui.page-1)
        elseif a=="pagenext" then ui.page=math.min((ui.filter=="store" and ui.storePages) or ui.pages or 1,ui.page+1)
        elseif a=="tabprev" or a=="tabnext" then
            local TABS=ui.tabs or {"all","farm","mining"}
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
        elseif a=="reset" or a=="update" then
            -- Sicherheitsabfrage: zweimal innerhalb von 5 s druecken/tippen
            if confirming() and ui.confirm.action==a then ui.confirm=nil;return a end
            ui.confirm={at=os.clock(),action=a};return
        else return a end
    end
    -- Tastatur: Sondertasten (Name aus keys.getName) und Zeichen
    local KEYS={up="up",down="down",enter="open",numPadEnter="open",space="open",backspace="group",
        tab="tabnext",pageUp="pageprev",pageDown="pagenext",home="first",["end"]="last"}
    function ui.key(name)
        if not name then return end
        ui.kbd=true
        if ui.help then ui.help=false;return "redraw" end
        if ui.selected and ui.detailView=="drive" then
            local K={up="rc:forward",down="rc:back",left="rc:left",right="rc:right",pageUp="rc:up",pageDown="rc:down",
                space="rc:use",leftShift="rc:down",rightShift="rc:down",leftCtrl="rc:useDown",tab="dm:toggle"}
            if K[name] then return K[name] end
            if name=="backspace" then return "group" end
        end
        if ui.selected and ui.detailView=="config" then
            local tf=cfgTextField()
            if name=="backspace" and tf then
                local v=tostring(tf.value or "");if #v>0 then cfgSet(tf,v:sub(1,-2));return "redraw" end
                return "group"
            end
            if name=="up" or name=="down" then
                local L=ui.cfgLinesCache or {};local i=ui.cfgSel or 1
                repeat i=i+(name=="down" and 1 or -1) until not L[i] or L[i].kind~="title"
                if L[i] then ui.cfgSel=i end
                return "redraw"
            end
            if name=="left" then return "cf:opt:-1" end
            if name=="right" then return "cf:opt:1" end
            if name=="enter" then return "cf:toggle" end
        end
        if ui.filter=="store" and name=="left" and ui.storeItem then return "sback" end
        if ui.filter=="store" and ui.storeOnly and (name=="left" or name=="right" or name=="tab") then
            return "sview:"..(ui.storeView=="items" and "chests" or "items")
        end
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
        if ui.selected and ui.detailView=="drive" then
            local K={w="rc:forward",s="rc:back",a="rc:left",d="rc:right",e="rc:up",c="rc:down",r="rc:useUp",f="rc:useDown",
                b="dm:toggle",t="rc:nextblock",[" "]="redraw"}           -- Leertaste kommt schon als Taste (space)
            if K[ch:lower()] then return K[ch:lower()] end
            return "redraw"               -- andere Tasten im Steuermodus nicht als Befehle (z.B. R = Reset)
        end
        local tf=cfgTextField()
        if tf and ch:match("^[%w _,%.:%-]$") then cfgSet(tf,(tostring(tf.value or "")..ch):sub(1,48));return "redraw" end
        if ui.selected and ui.detailView=="config" then
            if ch=="+" then return "cf:add:1" elseif ch=="-" then return "cf:add:-1" end
        end
        if ui.filter=="store" and ch:match("^[%w _%-]$") then
            -- Lager: Buchstaben = Suche im Inhalt
            ui.search=((ui.search or "")..ch:lower()):sub(1,24);ui.storeView="items";ui.storeItem=nil;ui.page=1
            return "redraw"
        end
        return ui.keys[ch:lower()] or ui.keys[ch]
    end
    function ui.target() return ui.selected or ui.filter end
    function ui.click(x,y)
        for i=#ui.buttons,1,-1 do
            local b=ui.buttons[i]
            if b.enabled and y==b.y and x>=b.x and x<b.x+b.w then return b.action end
        end
    end
    ui.keys={k="chests",["0"]="group",["1"]="start",["2"]="stop",["3"]="once",["4"]="reset",
        s="start",x="stop",e="once",r="reset",h="help",["?"]="help",u="update",
        a="filter:all",f="filter:farm",m="filter:mining"}
    return ui
end
-- fuer Tests: Detailzeilen einer Aufgabe
function M.jobRows(job,d) local j=JOB[job];return j and j.rows and j.rows(d) end
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
    send({kind="hello",role="pocket",version=1,controllerId=cfg.controllerId,info=common.nodeInfo(cfg,"pocket")})
end
-- Lagerdaten (Kisten/Inhalt) kommen alle 10 s extra; hier an die Flotte haengen
local storeStats={}
local configs={}       -- Einstellungen der Turtles (Fernsteuerung), kommen auf Anfrage
local function withStats(f)
    if f then f.configs=configs end
    if f and f.nodes and f.nodes.entries then
        for id,e in pairs(f.nodes.entries) do
            if e.role=="storage" and storeStats[id] and e.data then e.data.stats=storeStats[id] end
        end
    end
    return f
end
local lastDraw,frameT=-1e9,nil
local function draw()lastDraw=os.clock();frameT=nil;ui.draw(withStats(fleet) or {ids={},entries={}},connected(),notice)end
-- Live: hoechstens ~7x pro Sekunde neu zeichnen, Rest sammeln
local function soon()
    if os.clock()-lastDraw>=0.15 then draw() elseif not frameT then frameT=os.startTimer(0.15) end
end
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
    if type(cmd)=="table" and connected() then
        -- Fernsteuerung: ueber die Zentrale an die Turtle
        serial=math.max(serial+1,os.epoch("utc"))
        pcall(common.saveState,PATH,{serial=serial})
        pending={message={kind="remote",version=1,controllerId=cfg.controllerId,target=cmd.id,payload=cmd.payload,serial=serial},at=os.clock()}
        send(pending.message)
    elseif cmd and connected() and common.actions[cmd] then
        local target=ui.target();local eligible=cmd=="stop" or cmd=="reset" or cmd=="update"
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
local tick,due=0,0
local function loop()
    poll();draw();local timer=os.startTimer(cfg.network.pollInterval);due=os.clock()+cfg.network.pollInterval*3
    while true do
        local e,a,b,c=os.pullEvent()
        if e=="rednet_message" and a==cfg.controllerId and c==common.remoteProtocol and type(b)=="table"
            and b.kind=="fleet" and b.version==1 and b.controllerId==cfg.controllerId and validFleet(b.fleet) then
            fleet,seen=b.fleet,os.clock();serial=math.max(serial,common.number(b.ack))
            if pending and common.number(b.ack)>=pending.message.serial then pending=nil end
            notice=pending and "Warte auf Zentrale..." or tostring(b.notice or "Verbunden");soon()
        elseif e=="rednet_message" and a==cfg.controllerId and c==common.remoteProtocol and type(b)=="table"
            and b.kind=="fleetdelta" and b.version==1 and b.controllerId==cfg.controllerId and fleet then
            if common.mergeDelta(fleet,b,cfg.network.maxDevices) then
                seen=os.clock()
                if not pending then notice=tostring(b.notice or "Verbunden") end
                soon()
            end
        elseif e=="timer" and a==frameT then frameT=nil;draw()
        elseif e=="rednet_message" and a==cfg.controllerId and c==common.remoteProtocol and type(b)=="table"
            and b.kind=="turtleconfig" and b.controllerId==cfg.controllerId and common.id(b.id) and type(b.config)=="table" then
            configs[b.id]={config=b.config,ok=b.ok,msg=b.msg,at=os.clock()}
            if b.msg then notice=tostring(b.msg) end
            soon()
        elseif e=="rednet_message" and a==cfg.controllerId and c==common.remoteProtocol and type(b)=="table"
            and b.kind=="nodestats" and b.controllerId==cfg.controllerId and type(b.stats)=="table" then
            storeStats=b.stats
            if ui.filter=="store" then draw() end
        elseif e=="rednet_message" and a==cfg.controllerId and c==common.remoteProtocol and type(b)=="table"
            and b.kind=="update" and b.controllerId==cfg.controllerId then
            notice="Update wird installiert ...";draw()
            local ok,why=common.selfUpdate(nil,b.target)
            if not ok then notice="Update fehlgeschlagen: "..tostring(why);draw() end
        elseif (e=="timer" and a==timer) or os.clock()>=due then
            -- "due": falls der Timer verloren ging (z.B. waehrend einer GPS-Abfrage), trotzdem weiter
            due=os.clock()+cfg.network.pollInterval*3
            -- Hallo nur alle 2 s (die Zentrale schickt die Daten sowieso regelmaessig)
            tick=(tick or 0)+1;if tick%2==0 or not connected() then poll() end
            if pending then
                if not connected() or os.clock()-pending.at>=cfg.network.commandTimeout then pending=nil;notice="Befehl unbestaetigt/verfallen"
                else send(pending.message)end
            end
            draw();timer=os.startTimer(cfg.network.pollInterval);due=os.clock()+cfg.network.pollInterval*3
        elseif e=="peripheral" or e=="peripheral_detach" then poll()
        elseif e=="mouse_click" and a==1 then action(ui.click(b,c))
        elseif e=="term_resize" then draw()
        elseif e=="char" then
            if (a=="q" or a=="Q") and not ui.help and not ui.textInput() then return end
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
local lastDraw,frameT=-1e9,nil
local function draw()
    lastDraw=os.clock();frameT=nil
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
-- Live: hoechstens ~7x pro Sekunde neu zeichnen
local function soon()
    if os.clock()-lastDraw>=0.15 then draw() elseif not frameT then frameT=os.startTimer(0.15) end
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
            fleet,seen=b.fleet,os.clock();soon()
        elseif e=="rednet_message" and a==cfg.controllerId and c==common.remoteProtocol and type(b)=="table"
            and b.kind=="fleetdelta" and b.version==1 and b.controllerId==cfg.controllerId then
            if not STORE and common.mergeDelta(fleet,b,cfg.network.maxDevices) then seen=os.clock();soon() end
        elseif e=="timer" and a==frameT then frameT=nil;draw()
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
    -- Zuckerrohr: waechst bis 3 hoch, wird nicht neu gepflanzt. Die Turtle faehrt
    -- in Hoehe des 3. Blocks: vorne den 3. Block, unten den 2. Block ernten,
    -- der unterste bleibt stehen und waechst nach.
    sugarcane = { block = "minecraft:sugar_cane", seed = "minecraft:sugar_cane",
        produce = "minecraft:sugar_cane", label = "Zuckerrohr", cane = true },
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
if CROPS[CFG.crop] and CROPS[CFG.crop].cane then RESERVE = 0
elseif RESERVE == 0 then
    RESERVE = math.max(16, math.min(192, CFG.width * CFG.length - #CFG.water))
end
-- CCChunkloader: Chunkloader bleibt angebaut, Werkzeug <-> Modem werden getauscht.
local TC = dofile("/toast_common.lua")
local CL = TC.chunkConfig(config.chunkload)
local GEAR
local lastRadio=os.clock()    -- letztes Funkfenster (Chunkloader)
local LIVE                    -- Live-Funk (TC.live), wird unten angelegt
if CL.enabled then
    local why
    GEAR, why = TC.gear(CL, TOOLS)
    assert(GEAR, why)
    assert(GEAR.radio(), "Chunkloader: Funk-/Endermodem ins Turtle-Inventar legen.")
end
local drainPerSec = CL.enabled and TC.chunkCostPerTick(CL.radius) * 20 or 0
local budget = CFG.width * CFG.length + CFG.width + CFG.length + 20
    + math.ceil(drainPerSec * (CFG.width * CFG.length * 1.5 + math.max(CFG.interval, CFG.maxInterval or 0) + 90))

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
if st.layout ~= layout then st.scanAt = nil end      -- neues Feld: angefangene Runde verwerfen
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
local function fail(why) run.mode, run.fault, run.retryAt = "off", why, nil; pcall(TC.log, "Farm gestoppt: " .. tostring(why)) end
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
local function maybeUpdate()
    if not run.updateReq then return end
    local want = type(run.updateReq) == "string" and run.updateReq or nil
    run.updateReq = false
    local ok, why = TC.selfUpdate(function(a, b) run.status, run.detail = a, b end, want)
    if not ok then run.status, run.detail = "Update fehlgeschlagen", tostring(why); TC.log("Update: " .. tostring(why)) end
end
local function active()
    maybeUpdate()
    -- radioTimeout = 0: auch ohne Zentrale weiterarbeiten.
    -- Mit Chunkloader: nur Funkfenster ohne Antwort zaehlen (siehe radioWindow).
    if run.mode ~= "off" and CFG.radioTimeout > 0 then
        if GEAR then
            if os.clock() - run.lastContact < 3 then run.radioMiss = 0 end
            -- nur wenn wirklich so lange kein Kontakt war (verpasste Fenster allein reichen nicht)
            if (run.radioMiss or 0) >= math.max(3, math.ceil(CFG.radioTimeout / math.max(1, LIVE and LIVE.every or CL.report)))
                and os.clock() - run.lastContact > CFG.radioTimeout then
                fail("Funkverbindung verloren")
            end
        elseif os.clock() - run.lastContact > CFG.radioTimeout then
            fail("Funkverbindung verloren")
        end
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
-- Mit Chunkloader: Modem statt Werkzeug, solange nicht geerntet wird
-- (2 Schritte ohne Ernte). Das Werkzeug kommt beim naechsten Ernten zurueck.
local freeMoves = 0
-- Zuckerrohr direkt vor der Turtle (3. Block): mitnehmen statt blockiert
local function caneAhead()
    if not crop.cane then return end
    local e, b = turtle.inspect()
    if not (e and b.name == crop.block) then return end
    local before = count(crop.produce)
    local ok, why = turtle.dig()
    if not ok and tostring(why):find("No tool", 1, true) and equipTool() then ok = turtle.dig() end
    if ok then
        local net = math.max(0, count(crop.produce) - before)
        st.total, run.roundYield = (st.total or 0) + net, run.roundYield + net
        freeMoves = 0
    end
end
local function forward()
    local last
    if LIVE then LIVE.point() end
    freeMoves = freeMoves + 1
    caneAhead()
    if GEAR and freeMoves >= 2 and GEAR.radio() then lastRadio = os.clock() end
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
    if crop.cane or count(crop.seed) >= RESERVE then return true end
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
    if crop.cane then
        -- 2. Block unter der Turtle ernten (der unterste bleibt stehen)
        if not (exists and block.name == crop.block) then return true end
        if freeSlots() < 1 then return false, "resupply" end
        status("Ernte", "Zuckerrohr wird geerntet, der unterste Block bleibt stehen.")
        local before = count(crop.produce)
        local dug, why = turtle.digDown()
        if not dug and tostring(why):find("No tool", 1, true) then
            if not equipTool() then return false, NO_TOOL end
            dug, why = turtle.digDown()
        end
        if not dug then return false, "Zuckerrohr nicht abbaubar" end
        local net = math.max(0, count(crop.produce) - before)
        st.harvested, run.roundPlants = (st.harvested or 0) + 1, run.roundPlants + 1
        st.total, run.roundYield = (st.total or 0) + net, run.roundYield + net
        freeMoves = 0
        save()
        return true
    end
    if exists and block.name ~= crop.block then return true end
    if exists and tonumber((block.state or {}).age) ~= crop.age then return true end
    if count(crop.seed) == 0 then return false, "resupply" end
    if exists and freeSlots() < 2 then return false, "resupply" end
    local before = count(crop.produce)
    -- Samen extra zaehlen (Weizen/Rote Bete: Frucht + Samen; Karotte/Kartoffel: beides dasselbe)
    local seedBefore = crop.seed ~= crop.produce and count(crop.seed) or 0
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
        freeMoves = 0
    else
        status("Pflanzen", "Leere Ackerstellen werden bepflanzt.")
    end
    local slot = findSlot(crop.seed)
    if not slot then return false, "Saatgut fehlt" end
    turtle.select(slot)
    local planted = turtle.placeDown()
    local net = math.max(0, count(crop.produce) - before)
    -- Ueberschuessige Samen (nach dem Neupflanzen) gehoeren zum Ertrag
    local seedNet = 0
    if exists and crop.seed ~= crop.produce then seedNet = math.max(0, count(crop.seed) - seedBefore) end
    st.seedsGained = (st.seedsGained or 0) + seedNet
    net = net + seedNet
    st.total, run.roundYield = (st.total or 0) + net, run.roundYield + net
    save()
    -- Kein Acker (z.B. Weg/Erde) blockiert nicht mehr die ganze Runde.
    if not planted then run.skipped = (run.skipped or 0) + 1 end
    return true
end
local sendStatus
lastRadio=os.clock()
-- Mit Chunkloader: alle reportEvery Sekunden kurz Modem anlegen und funken.
-- Das Werkzeug kommt beim naechsten Ernten automatisch zurueck.
local function radioWindow() if LIVE then LIVE.point() end end
local function scan()
    if st.parked then st.parked = nil; run.parked = nil; save() end     -- abgestellt: prepare() faehrt erst heim
    run.scanned, run.roundYield, run.roundPlants, run.waitUntil, run.skipped = 0, 0, 0, 0, 0
    -- Angefangene Runde (Stopp, Fehler, Neustart, Nachschub): dort weitermachen
    local first = 1
    if type(st.scanAt) == "number" and st.scanAt > 1 and st.scanAt <= CFG.width * CFG.length then
        first = st.scanAt
        run.scanned, run.roundYield, run.roundPlants, run.skipped = first - 1, st.roundYield or 0, st.roundPlants or 0, st.roundSkipped or 0
    end
    if not prepare() then return false end
    if first > 1 then status("Fortsetzen", "Runde geht weiter ab Feld " .. first .. " / " .. CFG.width * CFG.length) end
    for index = first, CFG.width * CFG.length do
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
        -- Fortschritt merken (fuer Stopp/Neustart mitten in der Runde)
        st.scanAt, st.roundYield, st.roundPlants, st.roundSkipped = index + 1, run.roundYield, run.roundPlants, run.skipped
        save()
    end
    st.scanAt, st.roundYield, st.roundPlants, st.roundSkipped = nil, nil, nil, nil
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
    if run.manual then status("Fernsteuerung", "Wird von Hand gesteuert (Zentrale/Pocket)."); return end
    if st.parked then status("Abgestellt", "Steht, wo sie abgestellt wurde. 'Zur Basis' oder Start = faehrt heim."); return end
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
-- Spar-Pause: Pflanzen brauchen ~5-30 min. Waren beim letzten Durchgang nur
-- wenige reif, wird die Pause laenger (bis maxInterval), bei fast allen reif
-- wieder kuerzer (bis interval). Spart viele unnoetige Runden = Fuel.
local function nextPause()
    local maxI = CFG.maxInterval or 0
    if maxI <= CFG.interval then return CFG.interval end
    local cells = CFG.width * CFG.length - #CFG.water - (run.skipped or 0)
    local f = cells > 0 and (run.roundPlants or 0) / cells or 1
    local p = st.pause or CFG.interval
    if f < 0.25 then p = p * 2 elseif f < 0.6 then p = p * 1.4 elseif f > 0.9 then p = p * 0.7 end
    p = math.floor(math.max(CFG.interval, math.min(maxI, p)))
    st.pause, st.lastRipe = p, math.floor(f * 100 + 0.5)
    save()
    return p
end
local function worker()
    while true do
        if run.recovery then
            sleep(0.2)
        elseif active() then
            local complete = scan()
            if complete and run.mode == "once" then finish() end
            if complete and active() then
                local pause = nextPause()
                run.waitUntil = os.clock() + pause
                if GEAR then GEAR.radio() end
                while active() and run.waitUntil > os.clock() do
                    chunkTick()
                    local left = math.max(0, math.ceil(run.waitUntil - os.clock()))
                    status("Warten", "Naechste Runde in " .. (left >= 120 and (math.ceil(left / 60) .. " min") or (left .. " s"))
                        .. (st.lastRipe and (", zuletzt " .. st.lastRipe .. "% reif") or "")
                        .. ((run.skipped or 0) > 0 and (". " .. run.skipped .. " Felder ohne Acker.") or ""))
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
        fuel = turtle.getFuelLevel(), budget = budget, seeds = (not crop.cane) and count(crop.seed) or nil, cane = crop.cane,
        chunks = GEAR and (GEAR.radius > 0 and CL.chunks or 0) or nil,
        chunkFuel = GEAR and math.floor(GEAR.perSecond() * 3600 + 0.5) or nil,
        freeSlots = freeSlots(), x = st.x, z = st.z, total = st.total or 0,
        harvested = st.harvested or 0, rounds = st.rounds or 0, seedsGained = st.seedsGained or 0,
        roundYield = run.roundYield, roundPlants = run.roundPlants,
        scanned = run.scanned, cells = CFG.width * CFG.length,
        wait = math.max(0, math.ceil(run.waitUntil - os.clock())), pause = st.pause, lastRipe = st.lastRipe }
end
LIVE = TC.live({ snapshot = snapshot, gear = GEAR, every = math.min(CL.report, 3), run = run,
    transmit = function(s) pcall(rednet.send, st.controller, s, PROTOCOL) end,
    contact = function() return run.lastContact end,
    onWindow = function(ok) if ok then run.radioMiss = 0 else run.radioMiss = (run.radioMiss or 0) + 1 end end })
sendStatus = function() LIVE.send() end
local function reset()
    run.mode, run.fault, run.lastMode, run.retries, run.retryAt, run.waitUntil = "off", nil, nil, 0, nil, 0
    st.lastMode = nil
    if run.recovery and resolvePending() then run.recovery = false end
    if run.recovery then status("Position unklar", "RESET reicht nicht: an Basis setzen, toast.lua --dock")
    else status("Reset", "Fehler geloescht; Turtle faehrt zur Basis.") end
end
-- Fernsteuerung (Zentrale/Pocket): Einstellungen + von Hand fahren (nur waagrecht)
local REMOTE = TC.remoteControl({ cfg = config, job = "farm", st = st, run = run, save = save, gear = function() return GEAR end,
    transmit = function(msg) pcall(rednet.send, st.controller, msg, PROTOCOL) end,
    send = function() sendStatus() end,
    atHome = function() return isHome() end,
    stopped = function() return run.mode == "off" end,
    ops = TC.manualOps({ noVertical = true, run = run,
        move = function(kind)
            local d = st.dir
            if kind == "back" then
                local ok, why = face((d + 2) % 4); if not ok then return false, why end
            end
            local ok, why = action("move", turtle.forward, function() st.x, st.z = st.x + DX[st.dir], st.z + DZ[st.dir] end)
            if kind == "back" then face(d) end
            return ok, why
        end,
        turn = function(left) return face((st.dir + ((left ~= MIRROR) and 3 or 1)) % 4) end,
        tool = function() return equipTool() end }) })
local function listener()
    while true do
        local event, sender, message, protocol = os.pullEvent()
        if (event == "key" and sender == keys.q) or (event == "char" and (sender == "q" or sender == "Q")) then
            finish(); run.fault = nil
        elseif event == "char" and (sender == "n" or sender == "N") and run.mode == "off" and isHome() then
            error("TOAST_NEUER_AUFTRAG", 0)
        elseif event == "peripheral" or event == "peripheral_detach" then common.refreshModems(); sendStatus()
        elseif event == "rednet_message" and sender == st.controller and protocol == PROTOCOL
            and type(message) == "table" then
            if REMOTE.handle(message) then
            elseif message.kind == "poll" then
                run.lastContact = os.clock()
                if os.clock() - LIVE.lastSent > 2.5 then sendStatus() end
            elseif message.kind == "command" and common.serial(message.serial)
                and ({ start = true, stop = true, once = true, reset = true, update = true })[message.action] then
                run.lastContact = os.clock()
                if message.serial > (st.commandSerial or 0) then
                    st.commandSerial = message.serial
                    if message.action == "update" then
                        run.updateReq = type(message.target) == "string" and message.target or true; run.status, run.detail = "Update", "Wird gleich installiert ..."
                    elseif message.action == "stop" then
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
local function heartbeat() LIVE.loop() end
if not GEAR then pcall(equipTool) end
term.clear(); term.setCursorPos(1, 1)
print("TOAST FARM v" .. TC.version .. " - Turtle #" .. os.getComputerID())
print("Zentrale #" .. st.controller .. " | " .. crop.label)
if GEAR then print("Chunkloader: " .. CL.chunks .. " Chunk(s), ca. " .. TC.chunkFuelPerHour(CL.chunks) .. " Fuel/h beim Arbeiten") end
print("Q: Stopp + Heimfahrt. N: neuer Auftrag (gestoppt, an Basis).")
if run.recovery then printError(run.detail) elseif resolvedAtStart then print(run.detail) end
local ok, why = pcall(function() parallel.waitForAll(worker, listener, heartbeat, REMOTE.loop) end)
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
    assert(({wheat=true,carrots=true,potatoes=true,beetroot=true,sugarcane=true})[f.crop], "Unbekannte crop.")
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
local lastRadio=os.clock()    -- letztes Funkfenster (Chunkloader)
local LIVE                    -- Live-Funk (TC.live), wird unten angelegt
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
    pcall(TC.log,"Mine gestoppt: "..tostring(why))
end
-- Update-Knopf der Zentrale: nur zwischen zwei Schritten ausfuehren (sicherer Punkt)
local function maybeUpdate()
    if not run.updateReq then return end
    local want=type(run.updateReq)=="string" and run.updateReq or nil
    run.updateReq=false
    local ok,why=TC.selfUpdate(function(a,b) run.status,run.detail=a,b end,want)
    if not ok then run.status,run.detail="Update fehlgeschlagen",tostring(why);TC.log("Update: "..tostring(why)) end
end
local function active()
    maybeUpdate()
    -- radioTimeout=0: auch ohne Zentrale weiterarbeiten (z.B. Zentrale in entladenem Chunk).
    -- Mit Chunkloader ist das Modem nur kurz angelegt (Funkfenster): dann zaehlen nur
    -- Funkfenster ohne Antwort, nicht die Zeit (lange Wege ohne Fenster sind normal).
    if run.mode~="off" and C.radioTimeout>0 then
        if GEAR then
            if os.clock()-run.lastContact<3 then run.radioMiss=0 end
            if (run.radioMiss or 0)>=math.max(3,math.ceil(C.radioTimeout/math.max(1,LIVE and LIVE.every or CL.report)))
                and os.clock()-run.lastContact>C.radioTimeout then fail("Funkverbindung verloren") end
        elseif os.clock()-run.lastContact>C.radioTimeout then fail("Funkverbindung verloren") end
    end
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
-- Mit Chunkloader: Modem statt Spitzhacke, sobald die Turtle nur faehrt (2 Schritte
-- ohne Abbau). Die Spitzhacke kommt beim naechsten Abbau automatisch zurueck.
local digCount,freeMoves=0,0
-- ===== Wasser/Lava und Erze (wie beim Aushub) =====
-- mine.drain: Wasser/Lava im Gang mit einem Block fuellen und wieder abbauen.
-- mine.seal: "liquids" = Wasser/Lava an der Gangwand zubauen, "all" = auch Loecher.
-- mine.keepOres: "", "all" oder "diamond,emerald": diese Erze oben/unten/seitlich
--   stehen lassen (in der Fahrspur selbst muss die Turtle durch).
local FILL={}
for _,n in ipairs({"cobblestone","cobbled_deepslate","stone","deepslate","dirt","netherrack","andesite","diorite",
    "granite","tuff","calcite","blackstone","basalt","smooth_basalt","end_stone"}) do FILL["minecraft:"..n]=true end
local DRAIN,SEAL=C.drain==true,C.seal or "off"
local KEEPALL,KEEPORES=false,{}
do local ko=tostring(C.keepOres or ""):lower()
    if ko=="all" or ko=="alle" then KEEPALL=true else for w in ko:gmatch("[^,;%s]+") do KEEPORES[#KEEPORES+1]=w end end end
local function keptOre(n)
    if not (n:find("_ore",1,true) or n=="minecraft:ancient_debris") then return false end
    if KEEPALL then return true end
    for _,k in ipairs(KEEPORES) do if n:find(k,1,true) then return true end end
    return false
end
local PLACEOF={[turtle.inspect]=turtle.place,[turtle.inspectUp]=turtle.placeUp,[turtle.inspectDown]=turtle.placeDown}
local function placeFill(place)
    for i=1,16 do
        local it=turtle.getItemDetail(i)
        if it and FILL[it.name] then
            turtle.select(i);local ok=place();turtle.select(1)
            if ok then st.noFill=nil end
            return ok
        end
    end
    st.noFill=true
    return false
end
local KEEPON=KEEPALL or #KEEPORES>0
local forceOre=false        -- true = Erz in der Fahrspur doch abbauen (am Rand)
local function clear(inspect,dig,interruptible,digOnly)
    -- Rueckweg (nicht unterbrechbar): immer freiraeumen, auch mit vollem Inventar
    -- (Block faellt dann als Item auf den Boden) und laenger auf Kies/Sand warten.
    local tries=interruptible and C.digRetries or math.max(64,C.digRetries)
    for _=1,tries do
        if interruptible and not active() then return false,"stopped" end
        local exists,b=inspect()
        if not exists then return true end
        if liquid[b.name] then
            -- Wasser/Lava im Gang: Block rein, im naechsten Durchlauf wieder abbauen
            if not (DRAIN and PLACEOF[inspect] and placeFill(PLACEOF[inspect])) then return true end
            st.drained=(st.drained or 0)+1
            exists,b=inspect()
            if not exists then return true end
        end
        if digOnly and keptOre(b.name) then st.keptOres=(st.keptOres or 0)+1;return true end
        -- Erz im Weg: nicht abbauen, Aufrufer sucht einen Weg drumherum
        if not digOnly and KEEPON and not forceOre and keptOre(b.name) then return false,"ore" end
        if forceOre and KEEPON and keptOre(b.name) then st.oresMined=(st.oresMined or 0)+1 end
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
            st.harvested=(st.harvested or 0)+1;digCount=digCount+1;save()
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
    if LIVE then LIVE.point() end
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
        local before=digCount
        local ok,why=clear(inspect,dig,interruptible);if not ok then return false,why end
        if digCount==before then freeMoves=freeMoves+1 else freeMoves=0 end
        if GEAR and freeMoves>=2 and GEAR.radio() then lastRadio=os.clock() end
        if interruptible and not active() then return false,"stopped" end
        ok,why=action(kind,fn,update)
        if ok then return true end
        last=why
        if tostring(why):lower():find("fuel",1,true) then break end
        if attempt<R.moveRetries then pcall(attack);sleep(0.5) end
    end
    return false,"Bewegung blockiert: "..tostring(last)
end
-- Gehoert die Stelle zur geplanten Mine?
local function inPlan(x,y,z)
    local r=-y
    if z<1 or z>L or r<0 or r>=H or x<0 then return false end
    if SIDE then return x<W end
    return x<width and x%(G+1)==0
end
-- Waende an der Turtle zubauen (Wasser/Lava, bei "all" auch Luft)
local function sealHere()
    if SEAL~="liquids" and SEAL~="all" then return end
    local x,y,z=st.x,st.y,st.z
    local function outside(nx,ny,nz) return not (nx==0 and ny==0 and nz==0) and not inPlan(nx,ny,nz) and not blockDug(nx,ny,nz) end
    local function check(inspect,place)
        local e,b=inspect()
        if (not e and SEAL=="all") or (e and liquid[b.name]) then
            if placeFill(place) then st.sealed=(st.sealed or 0)+1 end
        end
    end
    if outside(x,y-1,z) then check(turtle.inspectUp,turtle.placeUp) end
    if outside(x,y+1,z) then check(turtle.inspectDown,turtle.placeDown) end
    for d=0,3 do
        if outside(x+DX[d],y,z+DZ[d]) and face(d) then check(turtle.inspect,turtle.place) end
    end
end
-- Erz, das nicht umgangen werden kann (Querweg, Rand): doch abbauen
local function forced(kind,i)
    local ok,why=move(kind,i)
    if not ok and why=="ore" then
        forceOre=true;ok,why=move(kind,i);forceOre=false
    end
    return ok,why
end
local function seq(...)
    for _,f in ipairs({...}) do local ok,why=f();if not ok then return false,why end end
    return true
end
-- Erz direkt vor der Turtle im Gang (Fahrt entlang z): ueber die Reihe darueber,
-- darunter oder seitlich drumherum. Liegen mehrere Erze hintereinander, faehrt
-- sie so weit, bis wieder ein freies Feld im Gang kommt (hoechstens maxSteps
-- Felder weit). Die Felder ueber/unter den Erzen werden mit abgebaut, die Erze
-- bleiben stehen. Rueckgabe: ok, Anzahl Felder.
local function detour(dz,i,maxSteps)
    local x,y,z=st.x,st.y,st.z
    maxSteps=math.min(maxSteps or 2,12)
    if maxSteps<2 or not inPlan(x,y,z+2*dz) then return false,"rand" end
    local fwd,back=dz>0 and 0 or 2,dz>0 and 2 or 0
    local function oreAt(insp) local e,bl=insp();return e and keptOre(bl.name) end
    local function row(dy) for k=0,2 do if not inPlan(x,y+dy,z+k*dz) then return false end end;return true end
    local up,dn=row(-1),row(1)
    status("Erz umgehen","Erz im Gang bleibt stehen, Turtle faehrt drumherum.")
    -- Weg: raus (hoch/runter/seitlich), vor bis neben ein freies Gangfeld, wieder rein.
    -- Vorher jedes Feld pruefen; geht es nicht weiter: zurueck an den Anfang.
    -- landInsp prueft das Gangfeld neben der Turtle (ist es Erz, weiterfahren).
    local function try(out,inn,outInsp,landInsp)
        if outInsp and oreAt(outInsp) then return false,"blocked" end
        local ok,why=out();if not ok then return false,why end
        local steps=0
        local function abort()
            local okb,whyb=face(back);if not okb then return false,whyb end
            for _=1,steps do okb,whyb=move("forward",i);if not okb then return false,whyb end end
            okb,whyb=inn();if not okb then return false,whyb end
            return false,"blocked"
        end
        while true do
            ok,why=face(fwd);if not ok then return false,why end
            if steps>=maxSteps or not inPlan(x,y,z+(steps+1)*dz) or oreAt(turtle.inspect) then return abort() end
            ok,why=move("forward",i);if not ok then return false,why end
            steps=steps+1
            if steps>=2 then
                local ore;ore,why=landInsp();if ore==nil then return false,why end
                if not ore then break end
            end
        end
        ok,why=inn();if not ok then return false,why end
        return true,steps
    end
    local function look(insp) return function() return oreAt(insp)==true end end
    local ways={}
    if up then ways[#ways+1]={function()return move("up",i)end,function()return move("down",i)end,turtle.inspectUp,look(turtle.inspectDown),row=-1} end
    if dn then ways[#ways+1]={function()return move("down",i)end,function()return move("up",i)end,turtle.inspectDown,look(turtle.inspectUp),row=1} end
    for _,d in ipairs({1,3}) do
        local inward=(d+2)%4
        ways[#ways+1]={function() local ok,why=face(d);if not ok then return false,why end
                if oreAt(turtle.inspect) then return false,"blocked" end;return move("forward",i) end,
            function() local ok,why=face(inward);if not ok then return false,why end;return move("forward",i) end,
            nil,
            function() local ok,why=face(inward);if not ok then return nil,why end;return oreAt(turtle.inspect)==true end}
    end
    local ok,why,steps,used
    for _,wy in ipairs(ways) do
        ok,why=try(wy[1],wy[2],wy[3],wy[4])
        if ok then steps,used=why,wy.row;break end
        if why~="blocked" then break end
        local okf=face(fwd);if not okf then return false,"Drehen" end
    end
    if not ok and why=="blocked" then return false,"rand" end
    if not ok then return false,why end
    -- Felder ueber/unter den Erzen (gehoeren zum Gang) freilegen, soweit erreichbar:
    -- in die Reihe, zurueck ueber die Erze, Felder abbauen, wieder zurueck.
    local function sweep(go,ret,insp)
        if oreAt(insp) then return true end
        local ok2,why2=go();if not ok2 then return false,why2 end
        local walked=0
        for k=1,steps-1 do
            ok2,why2=face(back);if not ok2 then return false,why2 end
            ok2,why2=clear(turtle.inspect,turtle.dig,i,true);if not ok2 then return false,why2 end
            if k<steps-1 then
                if turtle.detect() then break end          -- Erz steht da: nicht weiter
                ok2,why2=move("forward",i);if not ok2 then return false,why2 end
                walked=walked+1
            end
        end
        if walked>0 then
            ok2,why2=face(fwd);if not ok2 then return false,why2 end
            for _=1,walked do ok2,why2=move("forward",i);if not ok2 then return false,why2 end end
        end
        return ret()
    end
    if up and used~=-1 and st.y==y then
        ok,why=sweep(function()return move("up",i)end,function()return move("down",i)end,turtle.inspectUp)
        if not ok then return false,why end
    end
    if dn and used~=1 and st.y==y then
        ok,why=sweep(function()return move("down",i)end,function()return move("up",i)end,turtle.inspectDown)
        if not ok then return false,why end
    end
    st.keptOres=(st.keptOres or 0)+steps-1;save()
    ok,why=face(fwd);if not ok then return false,why end
    return true,steps
end
local function lineX(x,i)
    while st.x~=x do
        local ok,why=face(st.x<x and 1 or 3);if not ok then return false,why end
        ok,why=forced("forward",i);if not ok then return false,why end
    end
    return true
end
local function lineZ(z,i)
    while st.z~=z do
        local dz=st.z<z and 1 or -1
        local ok,why=face(dz>0 and 0 or 2);if not ok then return false,why end
        ok,why=move("forward",i)
        if not ok and why=="ore" then
            if st.z+dz==z then return false,"ore" end          -- das Ziel selbst ist Erz
            ok,why=detour(dz,i,math.abs(z-st.z))
            if not ok and why=="rand" then ok,why=forced("forward",i) end
        end
        if not ok then return false,why end
    end
    return true
end
local function vertical(y,i)
    while st.y~=y do local ok,why=forced(st.y<y and "down" or "up",i);if not ok then return false,why end end
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
-- Mitgenommene Kisten (mine.placeChests) und Fackeln (mine.torches) nie abladen
local TORCHES={['minecraft:torch']=true}
local function keepItem(name)
    return TOOLS[name] or TC.MODEM_ITEMS[name] or (C.placeChests and containers[name]) or ((C.torches or 0)>0 and TORCHES[name])
end
-- Fuellbloecke (Bruchstein usw.) fuer Abdichten/Trockenlegen: einen Stapel behalten
local function keepSlot(item,kept)
    if keepItem(item.name) then return true end
    if (DRAIN or SEAL=="liquids" or SEAL=="all") and FILL[item.name] and (kept.fill or 0)<64 then
        kept.fill=(kept.fill or 0)+item.count;return true
    end
    return false
end
local function countItems(set) local n=0;for i=1,16 do local it=turtle.getItemDetail(i);if it and set[it.name] then n=n+it.count end end;return n end
local function findItem(set) for i=1,16 do local it=turtle.getItemDetail(i);if it and set[it.name] then return i end end end
local function unload()
    if not container(turtle.inspectDown) then return false,"Ausgabekiste fehlt" end
    burnCoal()      -- uebrige Kohle zuerst in den Tank (falls eingeschaltet)
    local kept={}
    for i=1,16 do
        local item=turtle.getItemDetail(i)
        if item and not keepSlot(item,kept) then
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
-- Obere Kiste an der Basis = Nachschub: Kohle (Fuel) und, wenn eingeschaltet,
-- Kisten (mine.placeChests) und Fackeln (mine.torches). Die Turtle holt alles in
-- freie Slots, nimmt was sie braucht (Fuel bis fuelTarget, je 1 Stapel Kisten
-- und Fackeln) und legt den Rest zurueck.
local STOCK=64
local function refuel()
    local unlimited=turtle.getFuelLevel()=="unlimited"
    local function needFuel() return not unlimited and turtle.getFuelLevel()<fuelTarget end
    local function needChests() return C.placeChests and countItems(containers)<STOCK end
    local function needTorches() return (C.torches or 0)>0 and countItems(TORCHES)<STOCK end
    if not needFuel() and not needChests() and not needTorches() then return true end
    if not container(turtle.inspectUp) then
        if needFuel() then return false,"Brennstoffkiste fehlt" end
        return true
    end
    for _=1,4 do
        if not active() and needFuel() then return false,"stopped" end
        if not needFuel() and not needChests() and not needTorches() then break end
        -- alles Erreichbare in freie Slots holen
        local pulled={}
        for i=1,16 do
            if turtle.getItemCount(i)==0 then
                turtle.select(i)
                if not turtle.suckUp() then break end
                pulled[#pulled+1]=i
            end
        end
        if #pulled==0 then break end
        for _,i in ipairs(pulled) do
            local it=turtle.getItemDetail(i)
            if it and FUELS[it.name] and needFuel() then
                turtle.select(i)
                while turtle.getItemCount(i)>0 and needFuel() do if not turtle.refuel(1) then break end end
            end
        end
        -- Kisten/Fackeln: nur bis je 1 Stapel behalten, Rest + alles andere zurueck
        local have={chest=0,torch=0}
        for i=1,16 do
            local isPulled=false;for _,p in ipairs(pulled) do if p==i then isPulled=true end end
            local it=turtle.getItemDetail(i)
            if it and not isPulled then
                if containers[it.name] then have.chest=have.chest+it.count end
                if TORCHES[it.name] then have.torch=have.torch+it.count end
            end
        end
        for _,i in ipairs(pulled) do
            local it=turtle.getItemDetail(i)
            if it then
                local keepN=0
                if C.placeChests and containers[it.name] then keepN=math.max(0,STOCK-have.chest);have.chest=have.chest+math.min(keepN,it.count)
                elseif (C.torches or 0)>0 and TORCHES[it.name] then keepN=math.max(0,STOCK-have.torch);have.torch=have.torch+math.min(keepN,it.count) end
                local back=it.count-math.min(keepN,it.count)
                if back>0 then turtle.select(i);turtle.dropUp(back) end
            end
        end
        turtle.select(1)
    end
    turtle.select(1)
    if needFuel() then return false,"Treibstoff fehlt" end
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
-- ===== Kiste unterwegs (mine.placeChests) =====
-- Inventar voll: statt heimzufahren eine mitgebrachte Kiste in den Boden unter
-- der untersten Reihe setzen (dort wird nie gegraben) und hineinladen.
-- Nur wenn die Spalte bis zur untersten Reihe schon frei ist.
local function dugAt(x,y,z) if SIDE then return blockDug(x,y,z) end return cellDug(x,y,z) end
local function dumpHere()
    if not C.placeChests or homePosition() or st.z<1 then return false end
    local slot=findItem(containers);if not slot then return false end
    for yy=st.y+1,0 do if not dugAt(st.x,yy,st.z) then return false end end
    burnCoal()
    local y0=st.y
    status("Kiste setzen","Inventar voll: Kiste in den Boden, kein Heimweg noetig.")
    local ok=vertical(0,false);if not ok then return false end
    local e,b=turtle.inspectDown()
    if e and (liquid[b.name] or blockReason(b)) then vertical(y0,false);return false end
    if e then
        ok=clear(turtle.inspectDown,turtle.digDown,false)
        if not ok then vertical(y0,false);return false end
    end
    slot=findItem(containers)
    if not slot then vertical(y0,false);return false end
    turtle.select(slot)
    if not turtle.placeDown() then turtle.select(1);vertical(y0,false);return false end
    local kept={}
    for i=1,16 do
        local item=turtle.getItemDetail(i)
        if item and not keepSlot(item,kept) then
            turtle.select(i);local before=turtle.getItemCount(i);turtle.dropDown()
            st.total=(st.total or 0)+before-turtle.getItemCount(i)
        end
    end
    turtle.select(1)
    st.chestsPlaced=(st.chestsPlaced or 0)+1
    st.chestSpots=st.chestSpots or {}
    if #st.chestSpots<64 then st.chestSpots[#st.chestSpots+1]={x=st.x,y=st.y+1,z=st.z,n=st.chestsPlaced} end
    save()
    -- Liste der Kisten auch als Datei (an der Turtle: edit /toast_kisten.txt)
    pcall(function()
        local okc,full=pcall(TC.load)
        local f=fs.open("/toast_kisten.txt","w")
        f.writeLine("Abladekisten von Turtle #"..os.getComputerID().." (Mine)")
        for _,k in ipairs(st.chestSpots) do
            local pos,rel=nil,nil
            if okc then pos,rel=TC.worldPos(full,"mining",k.x,k.y or 1,k.z) end
            local where=rel and (rel.fwd.." vor, "..math.abs(rel.right)..(rel.right>=0 and " rechts, " or " links, ")..math.abs(rel.up).." tief") or ""
            f.writeLine("Kiste "..(k.n or "?")..": "..(pos and ("X "..pos.x.." Y "..pos.y.." Z "..pos.z.."  ") or "")..where)
        end
        f.close()
    end)
    ok=vertical(y0,false)
    return ok
end
-- ===== Fackeln (mine.torches = Abstand, 0 = aus) =====
-- Auf den Boden der untersten Reihe, waehrend die Turtle in Reihe 2 vorbeifaehrt.
local function placeTorch()
    local n=C.torches or 0
    if n<=0 or st.y~=-1 or st.z<1 or st.z%n~=0 then return end
    st.torchAt=st.torchAt or {}
    local k=st.x..":"..st.z
    if st.torchAt[k] then return end
    local e=turtle.inspectDown();if e then return end
    local slot=findItem(TORCHES);if not slot then return end
    turtle.select(slot)
    if turtle.placeDown() then st.torchAt[k]=true;st.torchesPlaced=(st.torchesPlaced or 0)+1;save() end
    turtle.select(1)
end
local function fuelOk()
    local fuel=turtle.getFuelLevel()
    return fuel=="unlimited" or fuel>=reserve()
end
local function finish()
    run.mode,run.lastMode="off",nil
    if st.lastMode then st.lastMode=nil;save() end
end
local function idle()
    if run.manual then status("Fernsteuerung","Wird von Hand gesteuert (Zentrale/Pocket).");return end
    if st.parked then status("Abgestellt","Steht, wo sie abgestellt wurde. 'Zur Basis' oder Start = faehrt heim.");return end
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
    elseif st.next>cells then status("Fertig","Neuer Auftrag: an der Turtle N druecken")
    else status("Bereit","START setzt fort | 1 GANG: aktuellen Gang") end
    if GEAR then GEAR.radio() end
    chunkTick()
end
local sendStatus
lastRadio=os.clock()
-- Mit Chunkloader: Funkfenster (Modem kurz an, senden, Antwort abwarten) macht
-- der Live-Funk (TC.live) an sicheren Stellen. Spitzhacke kommt beim naechsten Abbau zurueck.
local function radioWindow() if LIVE then LIVE.point() end end
local function work()
    while true do
        chunkTick()
        if not run.recovery then
            if active() and st.parked then
                -- war abgestellt: erst zur Basis, dann normal weiter
                st.parked=nil;run.parked=nil;save()
                local ok,why=home();if not ok then fail("Rueckweg blockiert: "..tostring(why)) end
            elseif active() then
                radioWindow()
                if st.next>cells then finish();status("Fertig","Neuer Auftrag: an der Turtle N druecken")
                else
                    local ok,why=true
                    local fuel=turtle.getFuelLevel()
                    if homePosition() or freeSlots()<C.freeSlots or (fuel~="unlimited" and fuel<reserve()) then
                        if not (freeSlots()<C.freeSlots and fuelOk() and dumpHere() and freeSlots()>=C.freeSlots) then
                            ok,why=supplies()
                        end
                    end
                    if ok and active() then
                        status("Abbau",SIDE and ("Spur "..(math.floor((st.next-1)/L)+1).." / "..#LANES)
                            or ("Gang "..(math.floor((st.next-1)/area)+1).." / "..C.tunnels))
                        local x,y,z,up,down,left,right=step(st.next)
                        local px,py,pz
                        if st.next>1 then px,py,pz=step(st.next-1) end
                        if px and st.x==px and st.y==py and st.z==pz then ok,why=direct(x,y,z,true)
                        else ok,why=routeTo(x,y,z,true) end
                        if not ok and why=="ore" then
                            -- Das Zielfeld selbst ist ein Erz: stehen lassen und ueber die Reihe
                            -- darueber/darunter zum naechsten Feld; am Rand doch abbauen.
                            local dz=st.dir==0 and 1 or (st.dir==2 and -1 or 0)
                            local nx,ny,nz
                            if st.next<cells then nx,ny,nz=step(st.next+1) end
                            if dz~=0 and nx==st.x and ny==st.y and nz==st.z+2*dz and st.x==x and st.y==y then
                                -- wie viele Schritte liegen weiter geradeaus? (mehrere Erze hintereinander)
                                local reach,sz=2,st.z
                                while reach<12 and st.next+reach<=cells do
                                    local ax,ay,az=step(st.next+reach)
                                    if ax==st.x and ay==st.y and az==sz+(reach+1)*dz then reach=reach+1 else break end
                                end
                                local steps
                                ok,steps=detour(dz,true,reach)
                                if ok then
                                    st.next=st.next+steps-1;save()
                                    x,y,z,up,down,left,right=step(st.next)
                                else why=steps end
                            else
                                -- Erz irgendwo auf dem Weg (Wendepunkt): anders herum versuchen
                                ok,why=direct(x,y,z,true)
                                if not ok and why=="ore" then why="rand" end
                            end
                            if not ok and (why=="rand" or why=="ore") then
                                forceOre=true;ok,why=direct(x,y,z,true);forceOre=false
                            end
                        end
                        if ok and up then ok,why=clear(turtle.inspectUp,turtle.digUp,true,true) end
                        if ok and down then ok,why=clear(turtle.inspectDown,turtle.digDown,true,true) end
                        if ok then sealHere() end
                        if ok then placeTorch() end
                        -- Spurmodus: links/rechts durch Drehen mitabbauen (kostet kein Fuel).
                        -- Schon freie Seiten werden uebersprungen (spart Zeit).
                        if SIDE and ok then
                            local sides={}
                            if right and not blockDug(x+1,y,z) then sides[#sides+1]=1 end
                            if left and not blockDug(x-1,y,z) then sides[#sides+1]=3 end
                            for _,d in ipairs(sides) do
                                if ok and active() then
                                    ok,why=face(d)
                                    if ok then ok,why=clear(turtle.inspect,turtle.dig,true,true) end
                                end
                            end
                        end
                    end
                    if ok and active() then
                        st.next=st.next+1;save();run.retries=0
                        if run.mode=="once" and st.next>run.onceEnd then finish() end
                        if st.next>cells then finish() end
                    elseif not ok and why=="resupply" then
                        if not (freeSlots()<C.freeSlots and fuelOk() and dumpHere() and freeSlots()>=C.freeSlots) then
                            local ready,problem=supplies()
                            if not ready and problem~="stopped" then fail(problem) end
                        end
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
        placeChests=C.placeChests==true,chestsPlaced=st.chestsPlaced or 0,chestsLeft=C.placeChests and countItems(containers) or nil,
        chestSpots=st.chestSpots,keptOres=st.keptOres or 0,oresMined=st.oresMined or 0,sealed=st.sealed or 0,drained=st.drained or 0,noFill=st.noFill,
        torches=C.torches or 0,torchesPlaced=st.torchesPlaced or 0,torchesLeft=(C.torches or 0)>0 and countItems(TORCHES) or nil,
        rounds=math.floor((st.next-1)/area),scanned=st.next-1,cells=cells,lanes=SIDE and #LANES or nil}
end
LIVE=TC.live({snapshot=snapshot,gear=GEAR,every=math.min(CL.report,3),run=run,
    transmit=function(s) pcall(rednet.send,cfg.controllerId,s,common.protocol) end,
    contact=function() return run.lastContact end,
    onWindow=function(ok) if ok then run.radioMiss=0 else run.radioMiss=(run.radioMiss or 0)+1 end end})
sendStatus=function() LIVE.send() end
local function reset()
    run.mode,run.fault,run.lastMode,run.retries,run.retryAt="off",nil,nil,0,nil
    st.lastMode=nil
    if run.recovery and resolvePending() then run.recovery=false end
    if run.recovery then status("Position unklar","RESET reicht nicht: an Basis setzen, toast.lua --dock")
    else status("Reset","Fehler geloescht; Turtle faehrt zur Basis.") end
end
-- Fernsteuerung (Zentrale/Pocket): Einstellungen + von Hand fahren (ohne Abbau beim Fahren)
local REMOTE=TC.remoteControl({cfg=cfg,job="mining",st=st,run=run,save=save,gear=function() return GEAR end,
    transmit=function(msg) pcall(rednet.send,cfg.controllerId,msg,common.protocol) end,
    send=function() sendStatus() end,
    atHome=function() return homePosition() end,
    stopped=function() return run.mode=="off" end,
    ops=TC.manualOps({run=run,
        move=function(kind)
            if kind=="back" then
                local d=st.dir
                local ok,why=face((d+2)%4);if not ok then return false,why end
                ok,why=action("move",turtle.forward,function()st.x,st.z=st.x+DX[st.dir],st.z+DZ[st.dir] end)
                face(d);return ok,why
            end
            local fn,update
            if kind=="up" then fn,update=turtle.up,function()st.y=st.y-1 end
            elseif kind=="down" then fn,update=turtle.down,function()st.y=st.y+1 end
            else fn,update=turtle.forward,function()st.x,st.z=st.x+DX[st.dir],st.z+DZ[st.dir] end end
            return action("move",fn,update)
        end,
        turn=function(left) return face((st.dir+((left~=MIRROR) and 3 or 1))%4) end,
        tool=function() return equipTool() end})})
local function listener()
    while true do
        local e,a,b,c=os.pullEvent()
        if e=="char" and (a=="q" or a=="Q") then finish();run.fault=nil
        elseif e=="char" and (a=="n" or a=="N") and run.mode=="off" and homePosition() then error("TOAST_NEUER_AUFTRAG",0)
        elseif e=="peripheral" or e=="peripheral_detach" then common.refreshModems();sendStatus()
        elseif e=="rednet_message" and a==cfg.controllerId and c==common.protocol and type(b)=="table" then
            if REMOTE.handle(b) then
            elseif b.kind=="poll" then run.lastContact=os.clock();run.pollToken=b.token
                -- Status kommt ohnehin alle 2 s; auf den Poll nur antworten, wenn laenger nichts kam
                if os.clock()-LIVE.lastSent>2.5 then sendStatus() end
            elseif b.kind=="command" and common.serial(b.serial) and ({start=true,stop=true,once=true,reset=true,update=true})[b.action] then
                run.lastContact=os.clock()
                if b.serial>(st.commandSerial or 0) then
                    st.commandSerial=b.serial
                    if b.action=="update" then run.updateReq=type(b.target)=="string" and b.target or true;run.status,run.detail="Update","Wird gleich installiert ..."
                    elseif b.action=="stop" then finish();run.fault,run.retries,run.retryAt=nil,0,nil
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
local function heartbeat() LIVE.loop() end
if not GEAR then pcall(equipTool) end
term.clear();term.setCursorPos(1,1)
print("TOAST MINING v"..TC.version.." / Turtle #"..os.getComputerID())
print(C.tunnels.." Gaenge / "..C.length.." lang / "..C.height.." hoch / Abstand "..C.gap)
if sideNote then print(sideNote) end
print("Zentrale #"..cfg.controllerId)
if GEAR then print("Chunkloader: "..CL.chunks.." Chunk(s), ca. "..TC.chunkFuelPerHour(CL.chunks).." Fuel/h beim Arbeiten") end
print("Q: Stopp/Heimfahrt. N: neuer Auftrag (gestoppt, an Basis).")
if run.recovery then printError(run.detail) elseif resolvedAtStart then print(run.detail) end
local ok,why=pcall(function()parallel.waitForAll(work,listener,heartbeat,REMOTE.loop)end)
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
    assert(f.placeChests==nil or type(f.placeChests)=="boolean", "placeChests: true oder false.")
    assert(f.torches==nil or integer(f.torches,0,64), "torches: 0 (aus) bis 64.")
    assert(f.drain==nil or type(f.drain)=="boolean", "drain: true oder false.")
    assert(f.seal==nil or f.seal=="off" or f.seal=="liquids" or f.seal=="all", "seal: off, liquids oder all.")
    assert(f.keepOres==nil or type(f.keepOres)=="string", "keepOres: Text.")
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
local gpsHost
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
-- Toast-Netz: nebenbei GPS-Sender und Meldung an die Zentrale (falls Toast installiert)
local common,toastCfg
pcall(function()
    common=dofile("/toast/toast_common.lua")
    toastCfg=common.load()
    common.refreshModems()
    gpsHost=common.gpsHost(toastCfg,true)
end)
local beaconAt=-1e9
local function beacon()
    if not common or os.clock()-beaconAt<10 then return end
    beaconAt=os.clock()
    common.nodeBeacon(toastCfg,"repeater",{repeated=repeated,gps=gpsHost and gpsHost.served or nil})
end
local function draw()
    local w,h=term.getSize()
    term.setBackgroundColor(colors.black);term.setTextColor(colors.white);term.clear()
    local function line(y,text)
        if y<=h then term.setCursorPos(1,y);term.write(tostring(text):sub(1,w)) end
    end
    local count=0;for _ in pairs(modems) do count=count+1 end
    local label=os.getComputerLabel and os.getComputerLabel()
    line(1,"TOAST REPEATER"..(common and (" v"..common.version) or "")..(label and (" / "..label) or ""))
    line(3,"Computer-ID: "..os.getComputerID())
    line(4,"Funkmodems: "..count..(count==0 and " - BITTE ANBRINGEN" or " / AKTIV"))
    line(6,"Weitergeleitet: "..repeated)
    line(7,"Doppelte ignoriert: "..duplicates)
    line(8,"Cache voll: "..dropped)
    line(10,"Rednet: Farm, Mining, Pocket")
    line(12,"Endermodem: Reichweite unbegrenzt")
    line(11,"IDs bleiben unveraendert.")
    line(13,gpsHost and ("GPS-Sender: "..gpsHost.served.." Anfragen") or "GPS-Sender: aus")
    line(13,gpsHost and ("GPS-Sender: "..gpsHost.x.." "..gpsHost.y.." "..gpsHost.z.."  ("..gpsHost.served..")") or "")
    line(14,"Q / Ctrl+T: beenden")
end
local function cleanup()
    for _,m in pairs(modems) do if m.owned then pcall(m.device.close,CHANNEL_REPEAT) end end
end
local function loop()
    scan();draw();local timer=os.startTimer(1)
    while true do
        local e,name,channel,reply,message,dist=os.pullEventRaw()
        if gpsHost and gpsHost.event(e,name,channel,reply,message,dist) then
            -- GPS-Anfrage beantwortet
        elseif e=="rednet_message" and common and toastCfg and common.isUpdateFor(toastCfg,name,channel) then
            -- Update-Befehl der Zentrale (name=Absender, channel=Nachricht)
            cleanup()
            local ok,why=common.selfUpdate(nil,type(channel)=="table" and channel.target or nil)
            if not ok then common.log("Update: "..tostring(why)) end
            scan()
        elseif e=="terminate" or (e=="char" and (name=="q" or name=="Q")) then return
        elseif e=="peripheral" or e=="peripheral_detach" then scan();draw()
        elseif e=="term_resize" then draw()
        elseif e=="timer" and name==timer then
            local now=os.clock()
            for id,expires in pairs(seen) do if expires<=now then seen[id]=nil;cacheCount=cacheCount-1 end end
            beacon();draw();timer=os.startTimer(1)
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
if not ok and tostring(why):find("TOAST_UPDATE",1,true) then error(why,0) end
if not ok then printError(tostring(why)) else print("Repeater beendet.") end
]======]
FILES["toast_worker.lua"]=[======[
-- Toast Control: gemeinsames Grundgeruest fuer Holzfarm- und Mob-Turtles.
-- Enthaelt alles, was jede Turtle braucht: Zustand auf der Disk, Bewegung mit
-- Wiederherstellung nach Absturz (ueber den Fuelstand), Funk mit der Zentrale
-- (START/STOP/1x/RESET), Statusmeldungen, Abladen/Tanken an der Basis und
-- automatische neue Versuche nach Fehlern.
--
-- Koordinaten: Basis = 0,0,0, Blick nach vorne = dir 0 (+z).
-- dir 1 = rechts (+x), 2 = zurueck, 3 = links. y = Hoehe (oben positiv).
-- mirror=true spiegelt rechts/links (Arbeitsbereich liegt links).
local common=dofile("/toast/toast_common.lua")
local W={}
local DX,DZ={[0]=0,1,0,-1},{[0]=1,0,-1,0}
W.DX,W.DZ=DX,DZ
local CONTAINERS={["minecraft:chest"]=true,["minecraft:trapped_chest"]=true,["minecraft:barrel"]=true}
W.FUELS={["minecraft:coal"]=80,["minecraft:charcoal"]=80,["minecraft:coal_block"]=800}

function W.new(o)
    local cfg=o.cfg
    local C=o.section
    local R=common.recovery(cfg.recovery)
    local PROTOCOL=common.workerProtocols[o.job]
    local FILE=o.stateFile
    local MIRROR=o.mirror==true
    local w={cfg=cfg,C=C,R=R}

    -- ===== Zustand =====
    local function readTable(path)
        if not fs.exists(path) then return nil end
        local f=fs.open(path,"r");if not f then return nil end
        local ok,s=pcall(textutils.unserialize,f.readAll());f.close()
        if ok and type(s)=="table" and type(s.x)=="number" and type(s.z)=="number" and type(s.dir)=="number" then return s end
    end
    local st=readTable(FILE..".tmp") or readTable(FILE)
    if not st then
        if fs.exists(FILE) or fs.exists(FILE..".tmp") then
            error("Zustand beschaedigt. Turtle an Basis setzen: toast.lua --dock",0)
        end
        st={x=0,y=0,z=0,dir=0,total=0,harvested=0,rounds=0}
    end
    st.y=st.y or 0
    w.st=st
    local lastSave=0
    function w.save()
        local f=assert(fs.open(FILE..".tmp","w"),"Zustand nicht schreibbar.")
        f.write(textutils.serialize(st));f.close()
        if fs.exists(FILE) then fs.delete(FILE) end
        fs.move(FILE..".tmp",FILE)
    end
    -- Zaehler (Ertrag usw.) nicht bei jedem Schlag schreiben: hoechstens alle 5 s.
    function w.saveSoon() if os.clock()-lastSave>=5 then lastSave=os.clock();w.save() end end
    local function clearPending() st.pending,st.after,st.pendingFuel=nil,nil,nil end
    local function resolvePending()
        if not st.pending then return true end
        local fuel=turtle.getFuelLevel()
        if st.pending~="turn" and type(fuel)=="number" and type(st.pendingFuel)=="number" and type(st.after)=="table" then
            if fuel==st.pendingFuel then clearPending();w.save();return true end
            if fuel==st.pendingFuel-1 then
                st.x,st.y,st.z,st.dir=st.after.x,st.after.y,st.after.z,st.after.dir
                clearPending();w.save();return true
            end
        end
        if st.pending~="turn" and fuel=="unlimited" then return false end
        return false
    end
    local resolvedAtStart=st.pending~=nil and resolvePending()
    for _,a in ipairs(o.args or {}) do
        if a=="--dock" then
            print("Turtle muss an der Basis stehen und nach vorne schauen.")
            write("Zum Bestaetigen DOCK eingeben: ")
            assert(read()=="DOCK","Positionsreset abgebrochen.")
            st.x,st.y,st.z,st.dir=0,0,0,0;clearPending();st.lastMode=nil
        else error("Start: toast.lua [--dock]",0) end
    end
    st.controller=cfg.controllerId
    -- Neue Masse nur an der Basis uebernehmen
    if o.layout then
        assert(not st.layout or st.layout==o.layout or (st.x==0 and st.y==0 and st.z==0 and not st.pending),
            "Masse nur an der Basis aendern. Bei versetzter Turtle: toast.lua --dock")
        st.layout=o.layout
    end
    w.save()
    -- Chunkloader (Mod CCChunkloader): eine Seite Chunkloader, die andere wechselt
    -- zwischen Werkzeug (nur beim Abbauen/Angreifen) und Modem (sonst immer).
    local CL=common.chunkConfig(cfg.chunkload)
    local G
    local lastTool=-1e9
    if CL.enabled and o.tools then
        local set=setmetatable({},{__index=function(_,k) return o.tools(k) or nil end})
        local why;G,why=common.gear(CL,set)
        assert(G,why)
        assert(G.radio(),"Chunkloader: Funk-/Endermodem ins Turtle-Inventar legen.")
    end
    w.gear=G
    common.modem()

    -- ===== Laufzustand =====
    local run={mode="off",status="Bereit",detail="START an der Zentrale druecken.",scanned=0,cells=o.cells or 0,
        lastContact=os.clock(),fault=nil,recovery=st.pending~=nil,lastMode=nil,retries=0,retryAt=nil,waitUntil=0}
    w.run=run
    if run.recovery then run.status,run.detail="Position unklar","An Basis setzen; toast.lua --dock starten."
    elseif resolvedAtStart then run.detail="Position nach Neustart wiederhergestellt." end
    if not run.recovery and (st.lastMode=="auto" or st.lastMode=="once") then
        run.mode,run.lastMode=st.lastMode,st.lastMode
        run.status,run.detail="Fortsetzen","Auftrag nach Neustart fortgesetzt."
    end
    function w.status(t,d) run.status,run.detail=t,d or "" end
    function w.fail(why) run.mode,run.fault,run.retryAt="off",why,nil end
    function w.finish()
        run.mode,run.lastMode="off",nil
        if st.lastMode then st.lastMode=nil;w.save() end
    end
    local radioTimeout=C.radioTimeout or 60
    function w.active()
        if run.updateReq then
            local want=type(run.updateReq)=="string" and run.updateReq or nil
            run.updateReq=false
            local ok,why=common.selfUpdate(w.status,want)
            if not ok then w.status("Update fehlgeschlagen",tostring(why));common.log("Update: "..tostring(why)) end
        end
        if run.mode~="off" and radioTimeout>0 and os.clock()-run.lastContact>radioTimeout then w.fail("Funkverbindung verloren") end
        return run.mode~="off" and not run.recovery
    end
    function w.isHome() return st.x==0 and st.y==0 and st.z==0 end

    -- ===== Inventar =====
    function w.freeSlots() local n=0;for i=1,16 do if turtle.getItemCount(i)==0 then n=n+1 end end;return n end
    function w.count(match)
        local n=0
        for i=1,16 do local it=turtle.getItemDetail(i);if it and match(it.name) then n=n+it.count end end
        return n
    end
    function w.find(match)
        for i=1,16 do local it=turtle.getItemDetail(i);if it and match(it.name) then return i,it end end
    end
    function w.items() local n=0;for i=1,16 do n=n+turtle.getItemCount(i) end;return n end
    -- Werkzeug aus dem Inventar anlegen (Seite ohne Modem)
    function w.equipTool(tools)
        if G then lastTool=os.clock();return G.tool() end
        for i=1,16 do
            local it=turtle.getItemDetail(i)
            if it and tools(it.name) then
                turtle.select(i)
                for _,side in ipairs({"left","right"}) do
                    if peripheral.getType(side)~="modem" then
                        local fn=side=="left" and turtle.equipLeft or turtle.equipRight
                        if fn() then turtle.select(1);return true end
                    end
                end
            end
        end
        turtle.select(1)
        return false
    end

    -- ===== Bewegung =====
    local function action(kind,fn,update)
        local x,y,z,dir=st.x,st.y,st.z,st.dir
        update();st.after={x=st.x,y=st.y,z=st.z,dir=st.dir}
        st.x,st.y,st.z,st.dir=x,y,z,dir
        st.pending,st.pendingFuel=kind,turtle.getFuelLevel();w.save()
        local ok,why=fn();if ok then update() end
        clearPending();w.save();return ok,why
    end
    function w.face(dir)
        while st.dir~=dir do
            local left=(st.dir-dir)%4==1
            local ok,why=action("turn",(left~=MIRROR) and turtle.turnLeft or turtle.turnRight,
                function() st.dir=(st.dir+(left and 3 or 1))%4 end)
            if not ok then return false,"Drehen fehlgeschlagen: "..tostring(why) end
        end
        return true
    end
    -- opts.dig: Bloecke wegraeumen (nur erlaubte, opts.canDig(name))
    -- opts.attack: Mob im Weg angreifen; sonst nur warten
    local MOVES={
        forward={turtle.forward,turtle.detect,turtle.inspect,turtle.dig,turtle.attack,function() st.x,st.z=st.x+DX[st.dir],st.z+DZ[st.dir] end},
        up={turtle.up,turtle.detectUp,turtle.inspectUp,turtle.digUp,turtle.attackUp,function() st.y=st.y+1 end},
        down={turtle.down,turtle.detectDown,turtle.inspectDown,turtle.digDown,turtle.attackDown,function() st.y=st.y-1 end},
    }
    function w.move(kind,opts)
        opts=opts or {}
        w.point()
        local m=MOVES[kind]
        local last
        for attempt=1,math.max(R.moveRetries,opts.dig and 24 or 0) do
            local ok,why=action("move",m[1],m[6])
            if ok then return true end
            last=why
            if tostring(why):lower():find("fuel",1,true) then return false,"Kein Fuel mehr" end
            if m[2]() then
                local _,b=m[3]()
                local name=b and b.name or "?"
                if opts.dig and (not opts.canDig or opts.canDig(name)) then
                    local dug,dwhy=m[4]()
                    if not dug and tostring(dwhy):find("No tool",1,true) then
                        if o.tools and w.equipTool(o.tools) then dug=m[4]() end
                        if not dug then return false,o.noTool or "Kein Werkzeug" end
                    end
                    if not dug then sleep(0.3) end
                else
                    return false,"Weg blockiert: "..name
                end
            else
                -- Kein Block: Mob/Spieler im Weg
                if opts.attack and attempt>=2 then pcall(m[5]) end
                sleep(opts.attack and 0.3 or 0.6)
            end
        end
        return false,"Weg blockiert: "..tostring(last)
    end
    -- Zu Position fahren: erst Hoehe 0, dann z, dann x (sichere Fahrspur bei x=0)
    function w.home(opts)
        opts=opts or {}
        while st.y>0 do local ok,why=w.move("down",opts);if not ok then return false,why end end
        while st.y<0 do local ok,why=w.move("up",opts);if not ok then return false,why end end
        if st.x~=0 then
            local ok,why=w.face(st.x>0 and 3 or 1);if not ok then return false,why end
            while st.x~=0 do ok,why=w.move("forward",opts);if not ok then return false,why end end
        end
        if st.z~=0 then
            local ok,why=w.face(st.z>0 and 2 or 0);if not ok then return false,why end
            while st.z~=0 do ok,why=w.move("forward",opts);if not ok then return false,why end end
        end
        return w.face(0)
    end

    -- ===== Gelaende (fuer Waechter und Holzfaeller) =====
    -- Bewegung in einem Gebiet vor der Basis (x = 0..width-1, z = 1..length),
    -- folgt dem Boden, klettert ueber Hindernisse (bis climb) und baut nur ab,
    -- was opt.canDig erlaubt (z.B. Blaetter). Merkt sich die Spur ab dem
    -- Basis-Ausgang: Heimweg = Spur rueckwaerts (sicher frei, Fuel bekannt).
    function w.terrain(opt)
        local T={}
        local CLIMB=opt.climb or 8
        local mopt={attack=opt.attack~=false,dig=opt.canDig~=nil,canDig=opt.canDig}
        -- Gefahr (Standard: Lava): nie hineinfahren, auch nicht von oben hinein
        local avoid=opt.avoid or function(n) return n:find("lava",1,true)~=nil end
        local function danger(inspect) local ok,b=inspect();return ok and type(b)=="table" and avoid(b.name or "") end
        T.danger=danger
        local TRAILMAX=800
        st.trail=type(st.trail)=="table" and st.trail or nil
        local idx={}
        local function key(x,y,z) return x..","..y..","..z end
        local function rebuild() idx={};for i,k in ipairs(st.trail or {}) do idx[k]=i end end
        rebuild()
        local function push()
            if not st.trail then return end
            local k=key(st.x,st.y,st.z)
            local i=idx[k]
            if i then for j=#st.trail,i+1,-1 do idx[st.trail[j]]=nil;st.trail[j]=nil end
            elseif #st.trail>=TRAILMAX then st.trail=nil;idx={}
            else st.trail[#st.trail+1]=k;idx[k]=#st.trail end
        end
        function T.mv(kind)
            local ok,why=w.move(kind,mopt)
            if ok then push() end
            return ok,why
        end
        function T.fuel() local f=turtle.getFuelLevel();if f=="unlimited" then return math.huge end;return f end
        function T.homeCost()
            local drain=G and math.ceil(G.perSecond()*60) or 0
            if st.trail then return #st.trail+CLIMB+20+(opt.extraCost or 0)+drain end
            return (math.abs(st.x)+math.abs(st.z))*3+math.abs(st.y)+CLIMB*3+40+(opt.extraCost or 0)
        end
        function T.startTrail() st.trail={};idx={} end
        function T.dropTrail() st.trail=nil;idx={} end
        -- Am Boden bleiben: runter, solange darunter Luft (oder Erlaubtes wie Blaetter)
        function T.hug()
            local n=0
            while st.y>-CLIMB and n<CLIMB+16 do
                if danger(turtle.inspectDown) then break end
                if turtle.detectDown() then
                    local _,b=turtle.inspectDown()
                    if not (opt.canDig and b and opt.canDig(b.name) and (not opt.hugThrough or opt.hugThrough(b.name))) then break end
                end
                if not T.mv("down") then break end
                n=n+1
            end
        end
        -- Ein Schritt nach vorne; fester Block -> hochklettern (nie abbauen)
        function T.step()
            if opt.before then opt.before() end
            if danger(turtle.inspect) then return false,"Lava" end
            local ok,why=T.mv("forward")
            if ok then return true end
            if not tostring(why):find("blockiert",1,true) then return false,why end
            while turtle.detect() and st.y<CLIMB do
                if turtle.detectUp() then
                    local _,b=turtle.inspectUp()
                    if not (opt.canDig and b and opt.canDig(b.name)) then break end
                end
                if not T.mv("up") then break end
            end
            if turtle.detect() then return false,"zu hoch" end
            if danger(turtle.inspect) then return false,"Lava" end
            return T.mv("forward")
        end
        local DIRV={[0]={0,1},{1,0},{0,-1},{-1,0}}
        T.DIRV=DIRV
        local wall,unreach={},{}
        local function ckey(x,z) return x..":"..z end
        T.wall,T.unreach,T.ckey=wall,unreach,ckey
        local function blocked(why) return why=="zu hoch" or why=="Lava" or tostring(why):find("blockiert",1,true)~=nil end
        -- Zu (tx,tz) laufen. ground: dem Boden folgen. watchFuel: bei knappem Fuel abbrechen.
        -- opt.facing(dir) wird nach jedem Drehen aufgerufen (z.B. Baum vor der Nase faellen).
        function T.nav(tx,tz,ground,watchFuel)
            local limit=(math.abs(tx-st.x)+math.abs(tz-st.z))*3+24
            local steps=0
            while st.x~=tx or st.z~=tz do
                if run.mode~="off" and not w.active() then return false,"stopped" end
                if watchFuel and T.fuel()<T.homeCost() then return false,"lowFuel" end
                steps=steps+1
                if steps>limit then return false,"kein Weg" end
                local dx,dz=tx-st.x,tz-st.z
                local cands={}
                local xd=dx>0 and 1 or 3;local zd=dz>0 and 0 or 2
                if math.abs(dx)>=math.abs(dz) then
                    if dx~=0 then cands[#cands+1]=xd end;if dz~=0 then cands[#cands+1]=zd end
                else
                    if dz~=0 then cands[#cands+1]=zd end;if dx~=0 then cands[#cands+1]=xd end
                end
                local side={(cands[1]+1)%4,(cands[1]+3)%4}
                if math.random(2)==1 then side[1],side[2]=side[2],side[1] end
                cands[#cands+1]=side[1];cands[#cands+1]=side[2]
                local moved=false
                for _,d in ipairs(cands) do
                    local nx,nz=st.x+DIRV[d][1],st.z+DIRV[d][2]
                    if (opt.inArea(nx,nz) or (nx==tx and nz==tz)) and not wall[ckey(nx,nz)] then
                        local ok,why=w.face(d);if not ok then return false,why end
                        if opt.facing then
                            local okf,whyf=opt.facing(d);if not okf then return false,whyf end
                        end
                        local okm,whym=T.step()
                        if okm then moved=true;break end
                        if not blocked(whym) then return false,whym end
                        if whym=="zu hoch" or whym=="Lava" then wall[ckey(nx,nz)]=true end
                    end
                end
                if not moved then return false,"kein Weg" end
                if ground then T.hug() end
                -- ueber Lava gelandet (Senke voller Lava): Feld merken und meiden
                if danger(turtle.inspectDown) then wall[ckey(st.x,st.z)]=true end
            end
            return true
        end
        -- Heim: Spur rueckwaerts, sonst Weg suchen (notfalls in Kletterhoehe),
        -- dann auf Basishoehe vor der Basis und hinein.
        function T.home()
            if w.isHome() then st.trail=nil;idx={};w.save();return w.face(0) end
            if st.trail and #st.trail>0 and idx[key(st.x,st.y,st.z)] then
                local i=idx[key(st.x,st.y,st.z)]
                local okT=true
                for j=i-1,1,-1 do
                    local x,y,z=st.trail[j]:match("(-?%d+),(-?%d+),(-?%d+)")
                    x,y,z=tonumber(x),tonumber(y),tonumber(z)
                    local ok
                    if y>st.y then ok=w.move("up",mopt)
                    elseif y<st.y then ok=w.move("down",mopt)
                    else
                        local d=x>st.x and 1 or x<st.x and 3 or z>st.z and 0 or 2
                        ok=w.face(d);if ok then ok=w.move("forward",mopt) end
                    end
                    if not ok then okT=false;break end
                    st.trail[j+1]=nil
                end
                rebuild()
                if not okT then st.trail=nil;idx={} end
            end
            local ok=(st.x==0 and st.z==1 and st.y==0) or T.nav(0,1,true,false)
            if not ok then
                while st.y<CLIMB and not turtle.detectUp() do if not w.move("up",mopt) then break end end
                local ok2,why2=T.nav(0,1,false,false)
                if not ok2 then return false,why2 end
            end
            while st.y>0 do local okd,whyd=w.move("down",mopt);if not okd then return false,"Basis-Eingang: "..tostring(whyd) end end
            while st.y<0 do local oku,whyu=w.move("up",mopt);if not oku then return false,"Basis-Eingang: "..tostring(whyu) end end
            local okf,whyf=w.face(2);if not okf then return false,whyf end
            local okm,whym=w.move("forward",mopt);if not okm then return false,"Basis-Eingang: "..tostring(whym) end
            st.trail=nil;idx={};w.save()
            return w.face(0)
        end
        -- Basis verlassen (Feld davor muss auf Basishoehe frei sein)
        function T.leave()
            local ok,why=w.face(0);if not ok then return false,why end
            T.startTrail()
            ok,why=T.step()
            if not ok then return false,"Basis-Ausgang blockiert: "..tostring(why) end
            if st.x~=0 or st.z~=1 or st.y~=0 then T.dropTrail() end
            T.hug()
            return true
        end
        return T
    end

    -- ===== Basis: Abladen (Kiste unten) und Tanken (Kiste oben) =====
    local function container(fn) local ok,b=fn();return ok and CONTAINERS[b.name]==true end
    w.container=container
    -- keep(name,count) -> wie viele davon behalten
    function w.unload(keep)
        if not container(turtle.inspectDown) then return false,"Ausgabekiste fehlt","Kiste oder Fass UNTER die Basis setzen." end
        local kept={}
        for i=1,16 do
            local it=turtle.getItemDetail(i)
            if it then
                local want=keep and keep(it.name) or 0
                local k=math.min(it.count,math.max(0,want-(kept[it.name] or 0)))
                kept[it.name]=(kept[it.name] or 0)+k
                local drop=it.count-k
                if drop>0 then
                    turtle.select(i)
                    turtle.dropDown(drop)
                    if turtle.getItemCount(i)>k then turtle.select(1);return false,"Lager voll","Ausgabekiste leeren oder vergroessern." end
                end
            end
        end
        turtle.select(1)
        return true
    end
    -- Bis target tanken; Kohle aus der Kiste oben, sonst extra(name) aus dem Inventar
    function w.refuel(target,extra)
        local lvl=turtle.getFuelLevel()
        if lvl=="unlimited" or lvl>=target then return true end
        -- zuerst Brennstoff aus dem Inventar
        for i=1,16 do
            local it=turtle.getItemDetail(i)
            if it and (W.FUELS[it.name] or (extra and extra(it.name))) then
                turtle.select(i)
                while turtle.getItemCount(i)>0 and turtle.getFuelLevel()<target do if not turtle.refuel(1) then break end end
            end
            if turtle.getFuelLevel()>=target then turtle.select(1);return true end
        end
        if container(turtle.inspectUp) then
            local slot;for i=1,16 do if turtle.getItemCount(i)==0 then slot=i;break end end
            while slot and turtle.getFuelLevel()<target do
                turtle.select(slot)
                if not turtle.suckUp(math.max(1,math.min(64,math.ceil((target-turtle.getFuelLevel())/80)))) then break end
                local it=turtle.getItemDetail(slot)
                if not it or not W.FUELS[it.name] then turtle.dropUp();break end
                while turtle.getItemCount(slot)>0 and turtle.getFuelLevel()<target do if not turtle.refuel(1) then break end end
                if turtle.getItemCount(slot)>0 then turtle.dropUp() end
            end
        end
        turtle.select(1)
        if turtle.getFuelLevel()>=target then return true end
        return false,"Treibstoff fehlt","Kohle / Holzkohle in die Kiste UEBER der Basis legen."
    end

    -- ===== Funk =====
    local sendStatus
    local function snapshot()
        local s={kind="status",version=2,id=os.getComputerID(),status=run.status,detail=run.detail,
            mode=run.mode,recovery=run.recovery,ack=st.commandSerial or 0,fault=run.fault,retries=run.retries,
            contactAge=math.max(0,math.floor(os.clock()-run.lastContact)),radioTimeout=radioTimeout,
            fuel=turtle.getFuelLevel(),freeSlots=w.freeSlots(),x=st.x,y=st.y,z=st.z,
            chunks=G and (G.radius>0 and CL.chunks or 0) or nil,chunkFuel=G and math.floor(G.perSecond()*3600+0.5) or nil,
            total=st.total or 0,harvested=st.harvested or 0,rounds=st.rounds or 0,
            scanned=run.scanned,cells=run.cells,wait=math.max(0,math.ceil(run.waitUntil-os.clock()))}
        if o.extra then for k,v in pairs(o.extra()) do s[k]=v end end
        s.label,s.job,s.controllerId,s.toast=cfg.label,o.job,cfg.controllerId,common.version
        pcall(common.addPosition,s,cfg,o.job)
        return s
    end
    -- Live-Funk: sendet bei jeder Aenderung sofort, sonst alle 2 s (eigener Ablauf)
    local LIVE
    sendStatus=function() if LIVE then LIVE.send() end end
    w.sendStatus=sendStatus
    -- sichere Stelle im Arbeitsablauf: mit Chunkloader kurz Modem an + funken
    function w.point() if LIVE then LIVE.point() end end
    local function reset()
        run.mode,run.fault,run.lastMode,run.retries,run.retryAt,run.waitUntil="off",nil,nil,0,nil,0
        st.lastMode=nil
        if run.recovery and resolvePending() then run.recovery=false end
        if run.recovery then w.status("Position unklar","RESET reicht nicht: an Basis setzen, toast.lua --dock")
        else w.status("Reset","Fehler geloescht; Turtle geht zur Basis.") end
    end
    -- Fernsteuerung (Zentrale/Pocket): Einstellungen + von Hand fahren
    local REMOTE=common.remoteControl({cfg=cfg,job=o.job,st=st,run=run,save=w.save,gear=function() return G end,
        transmit=function(msg) pcall(rednet.send,st.controller,msg,PROTOCOL) end,
        send=function() sendStatus() end,
        atHome=function() return w.isHome() end,
        stopped=function() return run.mode=="off" end,
        ops=common.manualOps({run=run,
            move=function(kind)
                if kind=="back" then
                    local d=st.dir
                    local ok,why=w.face((d+2)%4);if not ok then return false,why end
                    ok,why=w.move("forward",{});w.face(d);return ok,why
                end
                return w.move(kind,{})
            end,
            turn=function(left) return w.face((st.dir+((left~=MIRROR) and 3 or 1))%4) end,
            tool=o.tools and function() return w.equipTool(o.tools) end})})
    local function listener()
        while true do
            local e,a,b,c=os.pullEvent()
            if (e=="char" and (a=="q" or a=="Q")) then w.finish();run.fault=nil
            elseif e=="char" and (a=="n" or a=="N") and run.mode=="off" and w.isHome() then error("TOAST_NEUER_AUFTRAG",0)
            elseif e=="peripheral" or e=="peripheral_detach" then common.refreshModems();sendStatus()
            elseif e=="rednet_message" and a==st.controller and c==PROTOCOL and type(b)=="table" then
                if REMOTE.handle(b) then
                elseif b.kind=="poll" then run.lastContact=os.clock();if os.clock()-LIVE.lastSent>2.5 then sendStatus() end
                elseif b.kind=="command" and common.serial(b.serial) and common.actions[b.action] then
                    run.lastContact=os.clock()
                    if b.serial>(st.commandSerial or 0) then
                        st.commandSerial=b.serial
                        if b.action=="update" then run.updateReq=type(b.target)=="string" and b.target or true;w.status("Update","Wird gleich installiert ...")
                        elseif b.action=="stop" then w.finish();run.fault,run.retries,run.retryAt=nil,0,nil
                        elseif b.action=="reset" then reset()
                        elseif not run.recovery then
                            run.mode=b.action=="once" and "once" or "auto"
                            run.lastMode,st.lastMode=run.mode,run.mode
                            run.fault,run.waitUntil,run.retries,run.retryAt=nil,0,0,nil
                        end
                        w.save()
                    end
                    sendStatus()
                end
            end
        end
    end
    -- Chunks laden: bei Arbeit, unterwegs, bei neuem Versuch; an der Basis nur mit
    -- chunkload.idle ("An der Basis wach"). Modem zurueck, sobald kein Werkzeug gebraucht wird.
    local function chunkTick()
        if not G then return end
        local need=run.mode~="off" or not w.isHome() or (run.fault~=nil and run.retryAt~=nil) or CL.idle
        G.set(need and CL.radius or 0)
        if os.clock()-lastTool>3 then G.radio() end
    end
    w.chunkTick=chunkTick
    LIVE=common.live({snapshot=snapshot,gear=G,every=math.min(CL.report,3),tick=chunkTick,run=run,
        transmit=function(s) pcall(rednet.send,st.controller,s,PROTOCOL) end,
        contact=function() return run.lastContact end})
    local function heartbeat() LIVE.loop() end

    -- ===== Ablauf =====
    -- Warten, solange aktiv (fuer Pausen zwischen Runden)
    function w.wait(seconds,title,detail)
        run.waitUntil=os.clock()+seconds
        while w.active() and run.waitUntil>os.clock() do
            w.status(title or "Warten",detail or "Naechste Runde startet automatisch.")
            sleep(0.5)
        end
        run.waitUntil=0
    end
    local function idle()
        if run.manual then w.status("Fernsteuerung","Wird von Hand gesteuert (Zentrale/Pocket).");return end
        if st.parked then w.status("Abgestellt","Steht, wo sie abgestellt wurde. 'Zur Basis' oder Start = faehrt heim.");return end
        if o.idleHome then
            local ok,why=o.idleHome()
            if not ok then w.status("Rueckweg blockiert",why);return end
        end
        if o.idleBase then
            local ok,title,detail=o.idleBase()
            if not ok then w.status(title,detail);return end
        end
        if run.fault then
            local now=os.clock()
            if run.lastMode and common.retryable(run.fault) and run.retries<R.autoRetry then
                run.retryAt=run.retryAt or now+R.retryDelay
                local contact=radioTimeout==0 or now-run.lastContact<radioTimeout
                if now>=run.retryAt and contact then
                    run.retries,run.retryAt,run.fault,run.mode=run.retries+1,nil,nil,run.lastMode
                    w.status("Neuer Versuch","Automatisch "..run.retries.."/"..R.autoRetry)
                else
                    w.status(run.fault,contact and ("Neuer Versuch in "..math.max(0,math.ceil(run.retryAt-now))
                        .."s ("..(run.retries+1).."/"..R.autoRetry..") | RESET: abbrechen")
                        or "Warte auf Funkkontakt fuer neuen Versuch")
                end
            else
                w.status(run.fault,"Problem beheben; RESET loescht Fehler, START startet neu.")
            end
        else
            w.status("Bereit",o.readyText or "START: Dauerbetrieb | 1x: eine Runde.")
        end
    end
    local function worker()
        while true do
            if run.recovery then sleep(0.5)
            elseif w.active() and st.parked then
                -- war abgestellt: erst zur Basis, dann normal weiter
                st.parked=nil;run.parked=nil;w.save()
                if o.idleHome then local ok,why=o.idleHome();if not ok then w.fail("Rueckweg blockiert: "..tostring(why)) end end
            elseif w.active() then
                local complete=o.round()
                if complete then
                    st.rounds=(st.rounds or 0)+1;run.retries=0;w.save()
                    if run.mode=="once" then w.finish() end
                    if w.active() and (o.interval or 0)>0 then w.wait(o.interval) end
                end
            else
                idle();sleep(0.5)
            end
        end
    end
    function w.start(title,info)
        term.clear();term.setCursorPos(1,1)
        print(title.." v"..common.version.." - Turtle #"..os.getComputerID())
        print("Zentrale #"..st.controller..(info and (" | "..info) or ""))
        print("Q: Stopp + zur Basis. N: neuer Auftrag (gestoppt, an Basis).")
        if run.recovery then printError(run.detail) elseif resolvedAtStart then print(run.detail) end
        local ok,why=pcall(function() parallel.waitForAll(worker,listener,heartbeat,REMOTE.loop) end)
        if not ok then
            run.mode="off"
            run.recovery=st.pending~=nil and not resolvePending()
            w.status(run.recovery and "Position unklar" or "Programm beendet",tostring(why))
            sendStatus()
            if why~="Terminated" then error(why,0) end
            printError("Abgebrochen.")
        end
    end
    return w
end
return W
]======]
FILES["tree_turtle.lua"]=[======[
-- Toast Control: Holzfaeller im Gelaende. Die Turtle faehrt ein Gebiet vor der
-- Basis (Laenge nach vorne x Breite zur Seite) in Bahnen ab, folgt dabei dem
-- Boden (klettert ueber Huegel, steigt in Senken ab) und sucht links und rechts
-- nach Baeumen. Gefundene Baeume (egal wo sie stehen) werden komplett gefaellt
-- (ganzer Stamm), auf Wunsch wird ein Setzling nachgepflanzt.
-- Baut ausser Holz und Blaettern NIE etwas ab.
-- Basis: Kiste UNTER der Turtle = Ausgabe, Kiste UEBER der Turtle = Kohle,
-- optional Kiste HINTER der Turtle = Setzlinge.
local common=dofile("/toast/toast_common.lua")
local cfg=common.load()
local C=cfg.tree
local W=dofile("/toast/toast_worker.lua")
local function isLog(n) return n:find("_log",1,true)~=nil or n:find("_stem",1,true)~=nil
    or (n:find("_wood",1,true)~=nil and n:find("planks",1,true)==nil) end
local function isLeaves(n) return n:find("leaves",1,true)~=nil or n:find("wart_block",1,true)~=nil
    or n=="minecraft:vine" or n=="minecraft:shroomlight" end
local function isSapling(n) return n:find("_sapling",1,true)~=nil or n:find("_propagule",1,true)~=nil
    or n=="minecraft:crimson_fungus" or n=="minecraft:warped_fungus" end
local function isTool(n) return n:find("_axe",1,true)~=nil or n:find("_pickaxe",1,true)~=nil end
local CLIMB=C.climb or 8
-- Bahnen alle 3 Bloecke: jede Bahn prueft links und rechts mit (Drehen kostet kein Fuel)
local POINTS={}
do
    local lanes={}
    if C.width<=2 then lanes={math.min(1,C.width-1)}
    else local x=1;while x<C.width do lanes[#lanes+1]=x;x=x+3 end
        if lanes[#lanes]<C.width-2 then lanes[#lanes+1]=C.width-1 end end
    for i,x in ipairs(lanes) do
        if i%2==1 then for z=1,C.length do POINTS[#POINTS+1]={x,z} end
        else for z=C.length,1,-1 do POINTS[#POINTS+1]={x,z} end end
    end
end
local w,round,idleHome,idleBase
w=W.new({job="tree",cfg=cfg,section=C,stateFile="/toast_tree_state",args={...},cells=#POINTS,
    layout="forest:"..C.length..":"..C.width..":"..C.side,mirror=C.side=="left",
    tools=isTool,noTool="Keine Axt: Diamant-Axt in die Turtle legen",
    interval=C.interval,readyText="START: Dauerbetrieb | 1 RUNDE: Gebiet einmal absuchen",
    extra=function() return {saplings=w and w.count(isSapling) or 0,felled=w and w.st.harvested or 0} end,
    round=function() return round() end,
    idleHome=function() return idleHome() end,
    idleBase=function() return idleBase() end})
local st,run=w.st,w.run
local function logs() return w.count(isLog) end
local function keep(name)
    if isSapling(name) then return C.keepSaplings end
    if W.FUELS[name] or isTool(name) or common.MODEM_ITEMS[name] then return 4096 end
    return 0
end
local function inArea(x,z) return x>=0 and x<C.width and z>=1 and z<=C.length end
local fell
local T
-- Vor jedem Schritt: steht ein Stamm vor der Nase -> faellen
local function checkFront()
    local e,b=turtle.inspect()
    if e and isLog(b.name) then return fell(st.dir) end
    return true
end
T=w.terrain({climb=CLIMB,inArea=inArea,attack=true,canDig=isLeaves,hugThrough=isLeaves,
    extraCost=C.maxHeight*2+10,before=function() pcall(turtle.suck);checkFront() end,
    facing=function() return checkFront() end})
-- ===== Basis =====
local function refillSaplings()
    if not C.replant or w.count(isSapling)>0 then return end
    if not w.face(2) then return end
    if w.container(turtle.inspect) then
        for i=1,16 do
            if turtle.getItemCount(i)==0 then
                turtle.select(i)
                if turtle.suck(math.min(64,C.keepSaplings)) then
                    local it=turtle.getItemDetail(i)
                    if it and not isSapling(it.name) then turtle.drop() end
                end
                break
            end
        end
        turtle.select(1)
    end
    w.face(0)
end
local function base()
    local before=logs()
    local ok,title,detail=w.unload(keep)
    if not ok then return false,title,detail end
    ok,title,detail=w.refuel(C.fuelTarget)
    if not ok then
        -- Notfall: eigenes Holz verbrennen (15 Fuel pro Stamm), damit sie nicht stehen bleibt
        local need=(C.length+C.width)*3+C.maxHeight*2+CLIMB*4+60
        if turtle.getFuelLevel()<need then
            ok=w.refuel(need,isLog)
            if not ok then return false,title,detail end
        end
    end
    refillSaplings()
    return true
end
-- ===== Baum faellen =====
local function plantBelow()
    if not C.replant then return false end
    local slot=w.find(isSapling)
    if not slot then return false end
    turtle.select(slot)
    local ok=turtle.placeDown()
    turtle.select(1)
    return ok
end
local function dig(fn)
    local ok,why=fn()
    if not ok and tostring(why):find("No tool",1,true) then
        if w.equipTool(isTool) then ok,why=fn() end
    end
    return ok,why
end
-- Turtle steht vor dem Stamm (Blick dir). Stamm ganz faellen (hoch und runter),
-- unten nachpflanzen, dann zurueck auf das Feld davor und wieder zum Stamm schauen.
fell=function(dir)
    w.status("Faellt Baum","Baum gefunden, wird gefaellt.")
    local before=logs()
    local y0=st.y
    local ok,why=dig(turtle.dig);if not ok then return false,"Baum nicht abbaubar: "..tostring(why) end
    st.felling=true;w.save()
    ok,why=T.mv("forward");if not ok then st.felling=nil;return false,why end
    -- hoch
    while st.y-y0<C.maxHeight do
        local e,b=turtle.inspectUp()
        if not e or not isLog(b.name) then break end
        if not dig(turtle.digUp) then break end
        if not T.mv("up") then break end
    end
    -- zurueck auf Starthoehe, dann Stamm nach unten (Baum steht tiefer)
    while st.y>y0 do if not T.mv("down") then break end end
    while true do
        local e,b=turtle.inspectDown()
        if not e or not isLog(b.name) then break end
        if not dig(turtle.digDown) then break end
        if not T.mv("down") then break end
    end
    local planted=false
    -- nachpflanzen: einen hoch, Setzling nach unten (auf den Boden unter dem Stamm)
    if C.replant and w.find(isSapling) then
        local e=turtle.detectDown()
        if e and T.mv("up") then planted=plantBelow() end
    end
    -- zurueck auf das Feld davor (auf Starthoehe oder knapp darueber)
    while st.y<y0 do if not T.mv("up") then break end end
    ok,why=w.face((dir+2)%4);if not ok then return false,why end
    ok,why=T.mv("forward")
    if not ok then
        -- Feld davor auf dieser Hoehe belegt: eine Stufe hoeher versuchen
        if T.mv("up") then ok,why=T.mv("forward") end
        if not ok then return false,"Rueckweg vom Baum: "..tostring(why) end
    end
    T.hug()
    st.felling=nil
    st.harvested=(st.harvested or 0)+1
    st.total=(st.total or 0)+math.max(0,logs()-before)
    if planted then st.planted=(st.planted or 0)+1 end
    w.save()
    pcall(turtle.suck)
    return w.face(dir)
end
-- Nach Absturz mitten im Stamm: Rest des Stamms ueber der Turtle noch faellen
local function finishColumn()
    if not st.felling then return true end
    w.status("Faellt Baum","Stamm nach Neustart fertig faellen.")
    local y0=st.y
    while st.y-y0<C.maxHeight do
        local e,b=turtle.inspectUp()
        if not e or not isLog(b.name) then break end
        if not dig(turtle.digUp) or not T.mv("up") then break end
    end
    while st.y>y0 do if not T.mv("down") then break end end
    st.felling=nil;st.harvested=(st.harvested or 0)+1;w.save()
    return true
end
idleHome=function()
    if w.isHome() and st.dir==0 then return true end
    finishColumn()
    w.status("Rueckkehr","Faehrt zur Basis.")
    return T.home()
end
-- Ohne Auftrag / nach Fehler: nur abladen. Nicht tanken/Setzlinge holen, sonst
-- dreht sie sich alle halbe Sekunde zur hinteren Kiste und zurueck.
idleBase=function() return w.unload(keep) end
local function resupply()
    w.status("Rueckkehr","Nachschub / Abladen an der Basis.")
    local ok,why=T.home();if not ok then return false,"Rueckweg: "..tostring(why) end
    local ok2,title=base();if not ok2 then return false,title end
    return T.leave()
end
-- Links und rechts nach Baeumen sehen
local function lookAround()
    -- Bahnen laufen in z-Richtung: Baeume stehen links/rechts (x-Richtung)
    for _,d in ipairs({1,3}) do
        local ok=w.face(d);if not ok then return false end
        local e,b=turtle.inspect()
        if e and isLog(b.name) then
            local okf,why=fell(d);if not okf then return false,why end
        end
    end
    return true
end
round=function()
    if not w.isHome() then local ok,why=idleHome();if not ok then w.fail(why);return false end end
    local ok,title,detail=base()
    if not ok then w.status(title,detail);w.fail(title);return false end
    st.sweep=st.sweep or 1
    if st.sweep>#POINTS then st.sweep=1 end
    local okl,whyl=T.leave();if not okl then w.fail(whyl);return false end
    while st.sweep<=#POINTS do
        if not w.active() then return false end
        if T.fuel()<T.homeCost()+20 or w.freeSlots()<3 then
            local r,why=resupply();if not r then w.fail(why);return false end
        end
        local p=POINTS[st.sweep]
        run.scanned=st.sweep-1
        w.status("Sucht Baeume","Bahn "..math.ceil(st.sweep/C.length).." , Feld "..st.sweep.." / "..#POINTS)
        local okn,whyn=T.nav(p[1],p[2],true,true)
        if not okn then
            if whyn=="stopped" then return false end
            if whyn=="lowFuel" then
                local r,why=resupply();if not r then w.fail(why);return false end
            elseif whyn~="kein Weg" then w.fail(whyn);return false end
            -- unerreichbar: Punkt auslassen
            if whyn=="kein Weg" then st.sweep=st.sweep+1 end
        else
            local oka,whya=lookAround();if not oka and whya then w.fail(whya);return false end
            st.sweep=st.sweep+1;w.saveSoon()
        end
    end
    st.sweep=1;run.scanned=#POINTS
    local okh,whyh=idleHome();if not okh then w.fail("Rueckweg: "..tostring(whyh));return false end
    ok,title,detail=base()
    if not ok then w.status(title,detail) end
    return true
end
math.randomseed(os.epoch and os.epoch("utc") or math.floor(os.clock()*1000))
pcall(w.equipTool,isTool)
w.start("TOAST HOLZ","Gebiet "..C.length.."x"..C.width..(C.side=="left" and " links" or " rechts"))
]======]
FILES["mob_turtle.lua"]=[======[
-- Toast Control: Mob-Turtle mit Schwert. Drei Arten (mob.mode):
--   "farm"   Mobfarm: steht an der Toetungsstelle, schlaegt zu, sammelt Drops und
--            liefert sie in die Kiste UNTER sich.
--   "guard"  Wache: steht an einer Stelle (Tor, Gang) und wehrt Mobs ab.
--   "patrol" Waechter: faehrt im Gebiet (Rechteck vor der Basis) zufaellig umher,
--            folgt dem Gelaende (klettert ueber Huegel, steigt in Senken ab) und
--            greift Mobs an. Erst wenn das Fuel knapp wird, faehrt er zur Basis,
--            tankt, liefert Drops ab und macht weiter. Baut NIE Bloecke ab.
--            Basis: Kiste unten = Drops, Kiste oben = Kohle.
-- Achtung: Eine Turtle kann Mobs und Spieler nicht unterscheiden. Sie greift an,
-- was direkt vor ihr steht (unterwegs erst nach kurzem Warten).
local common=dofile("/toast/toast_common.lua")
local cfg=common.load()
local C=cfg.mob
local W=dofile("/toast/toast_worker.lua")
local PATROL=C.mode=="patrol"
local CLIMB=C.climb or 8
local function isTool(n) return n:find("_sword",1,true)~=nil or n:find("_axe",1,true)~=nil end
local function keep(name)
    if W.FUELS[name] and PATROL then return 4096 end
    if isTool(name) or common.MODEM_ITEMS[name] then return 4096 end
    return 0
end
local DIRS=C.attack=="all" and {"front","up","down"} or C.attack=="up" and {"up"} or {"front"}
local ATTACK={front=turtle.attack,up=turtle.attackUp,down=turtle.attackDown}
local SUCK={front=turtle.suck,up=turtle.suckUp,down=turtle.suckDown}
local w,round,idleHome,idleBase
local lastHit=0
-- Fortschritt beim Waechter: verbrauchter Tank (voll = 0 %, Rueckkehr = 100 %)
local tankStart=0
w=W.new({job="mob",cfg=cfg,section=C,stateFile="/toast_mob_state",args={...},cells=PATROL and 100 or 0,
    layout=C.mode..":"..C.length..":"..C.width..":"..C.side,mirror=PATROL and C.side=="left",
    tools=isTool,noTool="Kein Schwert: Diamant-Schwert in die Turtle legen",
    interval=PATROL and C.interval or 0,
    readyText=PATROL and "START: patrouilliert bis Tank leer, tankt, weiter | 1x: eine Tankfuellung"
        or "START: Dauerbetrieb | 1x: bis keine Mobs mehr da",
    extra=function() return {mobMode=C.mode,hits=w and w.st.harvested or 0,lastHit=math.floor(os.clock()-lastHit),
        targets=w and w.st.targets or 0,looted=w and w.st.looted or 0,carried=w and w.items() or 0} end,
    round=function() return round() end,
    idleHome=function() return idleHome() end,
    idleBase=function() return idleBase() end})
local st,run=w.st,w.run
local lastUnload=os.clock()
-- Einmal in alle Richtungen zuschlagen; true = etwas getroffen
local function strike()
    local hit=false
    for _,d in ipairs(DIRS) do
        for _=1,20 do
            local ok,why=ATTACK[d]()
            if not ok and tostring(why):find("No tool",1,true) and w.equipTool(isTool) then ok=ATTACK[d]() end
            if not ok then break end
            hit=true;st.harvested=(st.harvested or 0)+1
        end
    end
    return hit
end
-- Drops/Items einsammeln: vorne, oben und unten (immer alle drei, auch wenn nur
-- nach vorne angegriffen wird). Mehrmals, weil jedes Mal nur ein Stapel kommt.
local function collect()
    local got=0
    local INS={front=turtle.inspect,up=turtle.inspectUp,down=turtle.inspectDown}
    for _,d in ipairs({"front","up","down"}) do
        -- nie aus Kisten saugen (Kohlekiste oben, Ausgabekiste unten)
        local box=w and w.container(INS[d])
        for _=1,box and 0 or 8 do
            if w and w.freeSlots()==0 then return got end
            local ok,r=pcall(SUCK[d])
            if not ok or not r then break end
            got=got+1
        end
    end
    if got>0 and w then w.st.looted=(w.st.looted or 0)+got end
    return got
end
local function hasChest() return w.container(turtle.inspectDown) end
local function stash(force)
    if not hasChest() then
        -- Ohne Kiste unter der Turtle: weiter verteidigen, aber Hinweis wenn voll
        if w.freeSlots()==0 then w.status("Lager voll","Kiste UNTER die Turtle stellen, dann laedt sie die Drops ab.") end
        return true
    end
    if w.items()==0 then return true end
    if force or w.freeSlots()<=2 or os.clock()-lastUnload>=30 then
        lastUnload=os.clock()
        local before=w.items()
        local ok,title,detail=w.unload(keep)
        st.total=(st.total or 0)+math.max(0,before-w.items());w.save()
        if not ok then return false,title,detail end
    end
    return true
end
-- mob.nightOnly: nur nachts aktiv (Spielzeit 18:30 - 5:30, dann spawnen Mobs)
local function isDay()
    if not C.nightOnly or not os.time then return false end
    local ok,t=pcall(os.time)
    if not ok or type(t)~="number" then return false end
    return t>=5.5 and t<18.5
end
-- ===== Mobfarm / Wache (steht still, braucht kein Fuel) =====
local function stand()
    local quiet=os.clock()
    while w.active() do
        w.point()             -- mit Chunkloader: kurz funken (Schwert kommt beim naechsten Schlag zurueck)
        if strike() then
            lastHit,quiet=os.clock(),os.clock()
            w.status("Kampf",C.mode=="farm" and "Mobs werden besiegt, Drops gesammelt." or "Mob wird abgewehrt.")
            collect();w.saveSoon()
            sleep(0.2)
        else
            collect()
            if w.freeSlots()==0 and not hasChest() then
                w.status("Lager voll","Kiste UNTER die Turtle stellen, dann laedt sie die Drops ab.")
            else
                w.status("Wache",C.mode=="farm" and "Warte auf Mobs in der Farm." or "Halte Wache.")
            end
            sleep(0.5)
        end
        local ok,title,detail=stash(false)
        if not ok then w.status(title,detail);w.fail(title);return false end
        if run.mode=="once" and os.clock()-quiet>=8 then stash(true);return true end
        while w.active() and isDay() do
            w.status("Tagpause","Nur nachts aktiv - wartet bis ca. 18:30 Spielzeit.");stash(true);sleep(5)
        end
    end
    w.save()
    return false
end
-- ===== Waechter im Gelaende =====
-- Gebiet: x = 0 .. width-1 (zur Seite), z = 1 .. length (nach vorne), y = Hoehe
-- relativ zur Basis (+-climb). Basis selbst: x=0, z=0, y=0.
local function inArea(x,z) return x>=0 and x<C.width and z>=1 and z<=C.length end
local function fight()
    if strike() then lastHit=os.clock();w.status("Kampf","Mob abgewehrt.");collect();w.saveSoon();return true end
    collect();return false
end
-- Gelaende-Bewegung mit Spur (gemeinsam mit dem Holzfaeller, siehe toast_worker.lua)
local T=w.terrain({climb=CLIMB,inArea=inArea,attack=true,before=fight})
local fuelLeft,homeCost=T.fuel,T.homeCost
local wall,unreach,ckey=T.wall,T.unreach,T.ckey
local nav=T.nav
local function atBase()
    local before=w.items()
    local ok,title,detail=w.unload(keep)
    st.total=(st.total or 0)+math.max(0,before-w.items());w.save()
    if not ok then return false,title,detail end
    local need=(C.length+C.width)*4+CLIMB*6+80
    ok,title,detail=w.refuel(math.max(C.fuelTarget,need))
    if not ok and fuelLeft()<need then return false,title,detail end
    return true
end
idleHome=function()
    if not PATROL or (w.isHome() and st.dir==0) then return true end
    w.status("Rueckkehr","Faehrt zur Basis.")
    return T.home()
end
-- Eine Tankfuellung lang zufaellig im Gebiet umherfahren, dann heim.
local function patrol()
    run.scanned=0
    local ok,title,detail=atBase()
    if not ok then w.status(title,detail);w.fail(title);return false end
    tankStart=fuelLeft()
    local okl,whyl=T.leave()
    if not okl then w.fail(whyl);return false end
    local misses,count=0,0
    while w.active() do
        -- Fortschritt = verbrauchter Tank bis zur Rueckkehr
        if tankStart~=math.huge then
            local usable=math.max(1,tankStart-homeCost())
            run.scanned=math.max(0,math.min(100,math.floor((tankStart-fuelLeft())/usable*100)))
        end
        if fuelLeft()<homeCost() then break end
        if isDay() then break end
        -- Inventar fast voll: Beute zur Basis bringen (danach geht es weiter)
        if w.freeSlots()<=2 then w.status("Rueckkehr","Beute zur Basis bringen.");break end
        local tx,tz
        for _=1,20 do
            tx,tz=math.random(0,C.width-1),math.random(1,C.length)
            if not wall[ckey(tx,tz)] and not unreach[ckey(tx,tz)] and (tx~=st.x or tz~=st.z) then break end
        end
        w.status("Patrouille","Faehrt im Gebiet umher.")
        local okn,whyn=nav(tx,tz,true,true)
        count=count+1
        if okn then
            misses=0;st.targets=(st.targets or 0)+1;w.saveSoon()
            -- kurz umsehen: in alle vier Richtungen zuschlagen
            for _=1,4 do if not w.active() then break end;fight();w.face((st.dir+1)%4) end
        elseif whyn=="lowFuel" then break
        elseif whyn=="stopped" then return false
        elseif whyn=="kein Weg" then
            misses=misses+1;unreach[ckey(tx,tz)]=true
            if misses>=12 then w.status("Gelaende","Viele Ziele unerreichbar - Gebiet/Kletterhoehe pruefen.") end
        else w.fail(whyn);return false end
        -- unbegrenztes Fuel: 1x = 20 Ziele, Dauerbetrieb alle 50 Ziele kurz zur Basis
        if tankStart==math.huge and count>=(run.mode=="once" and 20 or 50) then break end
    end
    if run.mode=="off" then return false end
    run.scanned=100
    local okh,whyh=idleHome()
    if not okh then w.fail("Rueckweg: "..tostring(whyh));return false end
    ok,title,detail=atBase()
    if not ok then w.status(title,detail) end
    return true
end
idleBase=function()
    if PATROL then return w.unload(keep) end
    -- Still stehende Turtle: auch ohne Auftrag Drops wegraeumen
    local ok,title,detail=stash(false)
    if not ok then return false,title,detail end
    return true
end
round=function()
    -- Tagsueber an der Basis warten (Waechter) bzw. an der Stelle (Wache/Mobfarm)
    if isDay() then
        if PATROL and not w.isHome() then local ok,why=idleHome();if not ok then w.fail(why);return false end;w.unload(keep) end
        while w.active() and isDay() do
            w.status("Tagpause","Nur nachts aktiv - wartet bis ca. 18:30 Spielzeit.");sleep(5)
        end
        if not w.active() then return false end
    end
    if PATROL then
        if not w.isHome() then local ok,why=idleHome();if not ok then w.fail(why);return false end end
        return patrol()
    end
    return stand()
end
math.randomseed(os.epoch and os.epoch("utc") or math.floor(os.clock()*1000))
pcall(w.equipTool,isTool)
local names={farm="Mobfarm",guard="Wache",patrol="Waechter "..C.length.."x"..C.width}
w.start("TOAST MOBS",names[C.mode])
]======]
FILES["dig_turtle.lua"]=[======[
-- Toast Control: Aushub. Hoehlt eine Form vor der Basis aus:
--   room      Quader / Raum / Schacht (Breite x Laenge x Hoehe)
--   cylinder  Zylinder / runder Schacht (Durchmesser = Breite, Hoehe)
--   sphere    Kugel (Durchmesser = Breite)
--   dome      Halbkugel: nach oben = Kuppel, nach unten = Schale
-- direction "down" = von der Basis-Ebene nach unten, "up" = nach oben.
-- Extras:
--   seal      "off" | "liquids" (Wasser/Lava an den Waenden zubauen) |
--             "all" (auch Loecher/Hoehlen zubauen = komplett dichter Raum)
--   drain     Wasser/Lava IM Raum entfernen (Block rein, wieder abbauen):
--             fuer Arbeiten unter Wasser oder in Lava.
--   keepOres  "" = alles abbauen, "all" = alle Erze stehen lassen,
--             "diamond,emerald" = nur diese Erze stehen lassen. Die Turtle
--             graebt drumherum, die Erze kann man spaeter von Hand abbauen.
-- Basis: Kiste UNTER der Turtle = Ausgabe, Kiste UEBER der Turtle = Kohle.
-- Die Form beginnt direkt VOR der Turtle.
local common=dofile("/toast/toast_common.lua")
local cfg=common.load()
local C=cfg.dig
local W=dofile("/toast/toast_worker.lua")
local DOWN=C.direction~="up"
local SEAL=C.seal or "liquids"
local DRAIN=C.drain==true
-- Verkleidung: Waende/Boden/Decke aus einem bestimmten Block (liegt in der Kiste OBEN)
local WALL=(type(C.wallBlock)=="string" and C.wallBlock~="") and C.wallBlock or nil
local LINE={side=C.lineWalls~=false,down=C.lineFloor~=false,up=C.lineCeiling~=false}
local WALLSTOCK=C.wallStock or 256
local SHAPE=C.shape
-- ===== Bloecke =====
local KEEPALL,KEEP=false,{}
do
    local ko=tostring(C.keepOres or ""):lower()
    if ko=="all" or ko=="alle" then KEEPALL=true
    else for word in ko:gmatch("[^,;%s]+") do KEEP[#KEEP+1]=word end end
end
local function isOre(n) return n:find("_ore",1,true)~=nil or n=="minecraft:ancient_debris" end
local function keptOre(n)
    if not isOre(n) then return false end
    if KEEPALL then return true end
    for _,k in ipairs(KEEP) do if n:find(k,1,true) then return true end end
    return false
end
local UNBREAKABLE={["minecraft:bedrock"]=true,["minecraft:barrier"]=true,["minecraft:end_portal_frame"]=true,
    ["minecraft:end_portal"]=true,["minecraft:nether_portal"]=true,["minecraft:reinforced_deepslate"]=true}
local function isTurtle(n) return n:find("computercraft:turtle",1,true)~=nil end
local function isLiquid(n)
    return n=="minecraft:water" or n=="minecraft:lava" or n=="minecraft:bubble_column"
        or n:find("flowing_",1,true)~=nil
end
local FILL={}
for _,n in ipairs({"cobblestone","cobbled_deepslate","stone","deepslate","dirt","netherrack","andesite","diorite",
    "granite","tuff","calcite","blackstone","basalt","smooth_basalt","end_stone"}) do
    FILL["minecraft:"..n]=true
end
local function isFill(n) return FILL[n]==true end
local function isWall(n) return WALL~=nil and n==WALL end
local function isContainer(n) return n:find("chest",1,true)~=nil or n:find("barrel",1,true)~=nil or n:find("shulker",1,true)~=nil end
local function isTool(n) return n:find("_pickaxe",1,true)~=nil end
-- Bloecke, die stehen bleiben (nicht abbauen, aussen herum)
local PROTECTED={};for _,n in ipairs(C.protectedBlocks or {}) do PROTECTED[n]=true end
local function stays(n) return UNBREAKABLE[n]==true or PROTECTED[n]==true or keptOre(n) end

-- ===== Form =====
-- Ebene i = 0 .. bh-1 (0 = Basis-Ebene), y = i nach oben bzw. -i nach unten.
-- x = 0 .. bx-1 zur Seite, z = 1 .. bz nach vorne. Basis = 0,0,0.
local bx,bz,bh
if SHAPE=="room" then bx,bz,bh=C.width,C.length,C.height
elseif SHAPE=="cylinder" then bx,bz,bh=C.width,C.width,C.height
elseif SHAPE=="sphere" then bx,bz,bh=C.width,C.width,C.width
else bx,bz,bh=C.width,C.width,math.ceil(C.width/2) end
local cx,cz=(bx-1)/2,(bz+1)/2
local R2=(C.width/2)^2
local function inside(x,i,z)
    if x<0 or x>=bx or z<1 or z>bz or i<0 or i>=bh then return false end
    if SHAPE=="room" then return true end
    local dx,dz=x-cx,z-cz
    if SHAPE=="cylinder" then return dx*dx+dz*dz<=R2 end
    local dy
    if SHAPE=="sphere" then dy=i-(bh-1)/2 else dy=i+(C.width%2==0 and 0.5 or 0) end
    return dx*dx+dy*dy+dz*dz<=R2
end
-- Zellen werden NICHT vorab in eine Liste geschrieben (bei 1024x1024 waeren das
-- Milliarden): Reihenfolge und "gehoert zur Form" werden bei Bedarf berechnet.
local S=1040
local function key(x,i,z) return (i*S+x)*S+z end
local function unkey(k) local z=k%S;local r=(k-z)/S;local x=r%S;return x,(r-x)/S,z end
local function layer(y) return DOWN and -y or y end
local function ylev(i) return DOWN and -i or i end
local BASE=key(0,0,0)
-- Zugang: von der Basis bis zur ersten Zelle der Form (bei runden Formen)
local ACC,ACCSET={},{}
do
    local x,i,z=0,0,1
    local xc,zc=math.floor(cx),math.floor(cz)
    local ic=SHAPE=="sphere" and math.floor((bh-1)/2) or 0
    for _=1,4096 do
        if inside(x,i,z) then break end
        local k=key(x,i,z)
        if not ACCSET[k] then ACC[#ACC+1]=k;ACCSET[k]=true end
        if x~=xc then x=x+(xc>x and 1 or -1)
        elseif i~=ic then i=i+(ic>i and 1 or -1)
        elseif z~=zc then z=z+(zc>z and 1 or -1)
        else break end
    end
end
local ACCESS=#ACC
-- Reihe z in Ebene i: zusammenhaengender Bereich x0..x1 (Formen sind konvex)
local function rowRange(i,z)
    if SHAPE=="room" then return 0,bx-1 end
    local dz=z-cz;local rem=R2-dz*dz
    if SHAPE~="cylinder" then
        local dy=SHAPE=="sphere" and (i-(bh-1)/2) or (i+(C.width%2==0 and 0.5 or 0))
        rem=rem-dy*dy
    end
    if rem<0 then return nil end
    local r=math.sqrt(rem)
    local x0,x1=math.max(0,math.ceil(cx-r)),math.min(bx-1,math.floor(cx+r))
    -- Rundungsfehler ausgleichen: exakt an inside() anpassen
    while x0<=x1 and not inside(x0,i,z) do x0=x0+1 end
    while x0>0 and inside(x0-1,i,z) do x0=x0-1 end
    while x1>=x0 and not inside(x1,i,z) do x1=x1-1 end
    while x1<bx-1 and inside(x1+1,i,z) do x1=x1+1 end
    if x1<x0 then return nil end
    return x0,x1
end
-- Zellen je Ebene (vorab nur die Summen, bh Zahlen)
local LCOUNT,LBEFORE={},{}
do
    local total=0
    for i=0,bh-1 do
        local n=0
        -- grosse runde Formen: zwischendurch kurz abgeben (sonst bricht CC nach ~7 s ab)
        if SHAPE~="room" and i%32==31 then os.queueEvent("toast_form");os.pullEvent("toast_form") end
        if SHAPE=="room" then n=bx*bz
        else for z=1,bz do local x0,x1=rowRange(i,z);if x0 then n=n+x1-x0+1 end end end
        LCOUNT[i],LBEFORE[i]=n,total;total=total+n
    end
end
-- Reihen einer Ebene (nur die aktuelle Ebene wird gemerkt)
local rowCache={}
local function rows(i)
    if rowCache.i==i then return rowCache.r end
    local r,before={},0
    for z=1,bz do
        local x0,x1=rowRange(i,z)
        if x0 then r[#r+1]={z=z,x0=x0,x1=x1,b=before};before=before+x1-x0+1 end
    end
    rowCache={i=i,r=r};return r
end
-- Schritt n -> Zelle. Schlangenlinie: gerade Reihen rueckwaerts, jede zweite
-- Ebene rueckwaerts (Ende der einen = Anfang der naechsten).
local function cellAt(n)
    if n<=ACCESS then return ACC[n] end
    local p=n-ACCESS-1
    local lo,hi=0,bh-1
    while lo<hi do local m=math.floor((lo+hi+1)/2);if LBEFORE[m]<=p then lo=m else hi=m-1 end end
    local i=lo;local q=p-LBEFORE[i]
    if i%2==1 then q=LCOUNT[i]-1-q end
    local r=rows(i)
    local a,c=1,#r
    while a<c do local m=math.floor((a+c+1)/2);if r[m].b<=q then a=m else c=m-1 end end
    local row=r[a];local o=q-row.b
    local x=row.z%2==0 and (row.x1-o) or (row.x0+o)
    return key(x,i,row.z)
end
-- gehoert die Zelle zum Plan (Form oder Zugang)?
local function inPlan(k)
    if ACCSET[k] then return true end
    local x,i,z=unkey(k)
    return inside(x,i,z)
end
local N=ACCESS+(LBEFORE[bh-1] or 0)+(LCOUNT[bh-1] or 0)
local SHAPE_NAMES={room="Quader",cylinder="Zylinder",sphere="Kugel",dome=DOWN and "Schale" or "Kuppel"}
local LAYOUT=table.concat({SHAPE,C.width,C.length,C.height,C.side,C.direction},":")

local w,round,idleHome,idleBase
local opts
opts={job="dig",cfg=cfg,section=C,stateFile="/toast_dig_state",args={...},cells=N,
    layout=LAYOUT,mirror=C.side=="left",
    tools=isTool,noTool="Keine Spitzhacke: Diamant-Spitzhacke in die Turtle legen",
    interval=0,readyText="START: Form ausheben | 1x: dasselbe (macht weiter, wo sie war)",
    extra=function() local s=w and w.st or {}
        return {shape=SHAPE,digDir=DOWN and "down" or "up",kept=s.kept or 0,sealed=s.sealed or 0,
            drained=s.drained or 0,fill=w and w.count(isFill) or 0,noFill=s.noFill,done=s.done,
            wallBlock=WALL,wall=WALL and w and w.count(isWall) or 0,lined=s.lined or 0,noWall=s.noWall} end,
    round=function() return round() end,
    idleHome=function() return idleHome() end,
    idleBase=function() return idleBase() end}
w=W.new(opts)
local st,run=w.st,w.run
if st.digLayout~=LAYOUT then st.digLayout=LAYOUT;st.idx=1;st.skip={};st.done=nil;w.save() end
st.idx=st.idx or 1;st.skip=type(st.skip)=="table" and st.skip or {}
if st.done then run.scanned=N;opts.readyText="FERTIG: Form komplett. START = nochmal pruefen, N = neuer Auftrag" end

-- ===== Inventar / Fuel =====
local function keep(name)
    if isTool(name) or common.MODEM_ITEMS[name] then return 4096 end
    if isWall(name) then return WALLSTOCK end
    if isFill(name) and (SEAL~="off" or DRAIN) then return 64 end
    if W.FUELS[name] and C.useCoal then return 64 end
    return 0
end
local function fuel() local f=turtle.getFuelLevel();if f=="unlimited" then return math.huge end;return f end
local function homeNeed() return (math.abs(st.x)+math.abs(st.y)+math.abs(st.z))*2+30 end
-- Fuel fuer hin + zurueck zur naechsten Stelle (grosse Formen: kann ueber fuelTarget liegen)
local function tripNeed()
    if st.done or (st.idx or 1)>N then return 0 end
    local x,i,z=unkey(cellAt(st.idx))
    return (x+i+z)*2+100
end
local function fuelGoal() return math.max(C.fuelTarget,tripNeed()) end
local function burnCoal(target)
    if not C.useCoal then return end
    for s=1,16 do
        local it=turtle.getItemDetail(s)
        if it and W.FUELS[it.name] then
            turtle.select(s)
            while fuel()<target and turtle.getItemCount(s)>0 do if not turtle.refuel(1) then break end end
        end
        if fuel()>=target then break end
    end
    turtle.select(1)
end
local function wallCount() return WALL and w.count(isWall) or 0 end
-- Kiste OBEN: Kohle (tanken) und Wandblock holen. Fremdes kommt am Ende zurueck.
local function supply()
    local goal=fuelGoal()
    burnCoal(goal)
    if not w.container(turtle.inspectUp) then return end
    local want=WALL and math.min(WALLSTOCK,math.max(0,w.freeSlots()-3)*64+wallCount()) or 0
    local back={}
    for _=1,30 do
        local needFuel=fuel()<goal
        local needWall=WALL~=nil and wallCount()<want
        if not needFuel and not needWall then break end
        if w.freeSlots()<=1 then break end
        local slot;for i=1,16 do if turtle.getItemCount(i)==0 then slot=i;break end end
        turtle.select(slot)
        if not turtle.suckUp() then break end
        local it=turtle.getItemDetail(slot)
        if it and W.FUELS[it.name] then
            while fuel()<goal and turtle.getItemCount(slot)>0 do if not turtle.refuel(1) then break end end
            if turtle.getItemCount(slot)>0 then back[#back+1]=slot end
        elseif not (it and isWall(it.name) and needWall) then back[#back+1]=slot end
    end
    for _,s in ipairs(back) do turtle.select(s);turtle.dropUp() end
    turtle.select(1)
end
local function base()
    local before=w.items()
    local ok,title,detail=w.unload(keep)
    st.total=(st.total or 0)+math.max(0,before-w.items())
    if not ok then return false,title,detail end
    supply()
    if fuel()<math.max(math.min(C.fuelTarget,(bx+bz+bh)*3+60),tripNeed()) then
        return false,"Treibstoff fehlt","Kohle / Holzkohle in die Kiste UEBER der Basis legen"
            ..(tripNeed()>C.fuelTarget and (" (braucht "..tripNeed().." Fuel fuer hin + zurueck)") or ".")
    end
    w.save()
    return true
end

-- ===== Bewegung =====
local INSPECT={forward=turtle.inspect,up=turtle.inspectUp,down=turtle.inspectDown}
local PLACE={forward=turtle.place,up=turtle.placeUp,down=turtle.placeDown}
local RAWDIG={forward=turtle.dig,up=turtle.digUp,down=turtle.digDown}
-- Abbauen; mit Chunkloader liegt evtl. das Modem an -> Spitzhacke anlegen, nochmal
local DIG={}
for k,f in pairs(RAWDIG) do DIG[k]=function()
    local ok,why=f()
    if not ok and tostring(why):find("No tool",1,true) and w.equipTool(isTool) then ok,why=f() end
    return ok,why
end end
local function placeFill(kind)
    local slot=w.find(isFill)
    if not slot then st.noFill=true;return false end
    turtle.select(slot)
    local ok=PLACE[kind]()
    turtle.select(1)
    if ok then st.noFill=nil end
    return ok
end
local MOPT={dig=true,attack=true,canDig=function(n) return not stays(n) and not isTurtle(n) end}
-- Eine Zelle weiter (Nachbar von hier). false,"keep" = Block bleibt stehen.
local function stepInto(nk)
    local nx,ni,nz=unkey(nk)
    local ny=ylev(ni)
    local kind
    if ny>st.y then kind="up" elseif ny<st.y then kind="down"
    else
        local d=nx>st.x and 1 or nx<st.x and 3 or nz>st.z and 0 or 2
        local ok,why=w.face(d);if not ok then return false,why end
        kind="forward"
    end
    local e,b=INSPECT[kind]()
    local solid=false
    if e then
        if stays(b.name) then return false,"keep",b.name end
        if isLiquid(b.name) then
            -- Unterwasser/Lava: Quelle mit einem Block fuellen und wieder abbauen
            if DRAIN and placeFill(kind) then pcall(DIG[kind]);st.drained=(st.drained or 0)+1 end
        else solid=true end
    end
    local ok,why=w.move(kind,MOPT)
    if not ok then
        local e2,b2=INSPECT[kind]()
        if e2 and stays(b2.name) then return false,"keep",b2.name end
        return false,why
    end
    if solid then st.harvested=(st.harvested or 0)+1 end
    return true
end
local DIRS6={{1,0,0},{-1,0,0},{0,0,1},{0,0,-1},{0,1,0},{0,-1,0}}
local function passable(k) return k==BASE or (not st.skip[k] and inPlan(k)) end
-- Kuerzester Weg durch die Form (nur Zellen der Form + Basis). A*-Suche:
-- auch in riesigen Formen schnell (prueft nur Felder in Richtung Ziel).
local function path(from,to)
    if from==to then return {} end
    local tx,ti,tz=unkey(to)
    local function dist(x,i,z) return math.abs(x-tx)+math.abs(i-ti)+math.abs(z-tz) end
    local heap,g,prev,closed={},{[from]=0},{},{}
    local function less(a,b) return a[1]<b[1] or (a[1]==b[1] and a[2]<b[2]) end
    local function push(e)
        heap[#heap+1]=e;local c=#heap
        while c>1 do local p=math.floor(c/2);if less(heap[c],heap[p]) then heap[c],heap[p]=heap[p],heap[c];c=p else break end end
    end
    local function pop()
        local top=heap[1];local last=table.remove(heap)
        if #heap>0 then
            heap[1]=last;local c=1
            while true do
                local l,r,m=2*c,2*c+1,c
                if heap[l] and less(heap[l],heap[m]) then m=l end
                if heap[r] and less(heap[r],heap[m]) then m=r end
                if m==c then break end
                heap[c],heap[m]=heap[m],heap[c];c=m
            end
        end
        return top
    end
    do local x,i,z=unkey(from);local h=dist(x,i,z);push({h,h,from}) end
    local n=0
    while #heap>0 do
        local e=pop();local k=e[3]
        if not closed[k] then
            closed[k]=true
            if k==to then
                local p={};local c=k
                while c~=from do table.insert(p,1,c);c=prev[c] end
                return p
            end
            n=n+1
            if n%500==0 then os.queueEvent("toast_weg");os.pullEvent("toast_weg") end
            if n>300000 then return nil end
            local x,i,z=unkey(k)
            for _,d in ipairs(DIRS6) do
                local nx,ni,nz=x+d[1],i+d[2],z+d[3]
                if nx>=0 and nx<S and nz>=0 and nz<S and ni>=0 then
                    local nk=key(nx,ni,nz)
                    if not closed[nk] and passable(nk) then
                        local ng=g[k]+1
                        if not g[nk] or ng<g[nk] then
                            g[nk]=ng;prev[nk]=k
                            local h=dist(nx,ni,nz)
                            push({ng+h,h,nk})
                        end
                    end
                end
            end
        end
    end
end
local function here() return key(st.x,layer(st.y),st.z) end
local function travel(tk)
    for _=1,64 do
        if here()==tk then return true end
        local p=path(here(),tk)
        if not p then return false,"unreach" end
        local replan=false
        for _,nk in ipairs(p) do
            if run.mode~="off" and not w.active() then return false,"stopped" end
            local ok,why,name=stepInto(nk)
            if not ok then
                if why~="keep" then return false,why end
                if not st.skip[nk] then
                    st.skip[nk]=true
                    if name and keptOre(name) then st.kept=(st.kept or 0)+1 end
                end
                if nk==tk then return false,"keep" end
                replan=true;break
            end
        end
        if not replan then return here()==tk,"unreach" end
    end
    return false,"unreach"
end
-- Eine Aussenseite mit dem Wandblock verkleiden: fremden Block abbauen, Wandblock
-- setzen. Erze (geschont), Grundgestein, Kisten und Turtles bleiben stehen.
-- false = kein Wandblock mehr dabei.
local ATTACK={forward=turtle.attack,up=turtle.attackUp,down=turtle.attackDown}
local function lineFace(kind)
    for _=1,10 do
        local e,b=INSPECT[kind]()
        if e and b.name==WALL then return true end
        if e and not isLiquid(b.name) then
            if stays(b.name) or isTurtle(b.name) or isContainer(b.name) then return true end
            if not DIG[kind]() then return true end
            st.harvested=(st.harvested or 0)+1
        else
            local slot=w.find(isWall)
            if not slot then st.noWall=true;return false end
            turtle.select(slot)
            local ok=PLACE[kind]()
            turtle.select(1)
            if ok then st.lined=(st.lined or 0)+1;st.noWall=nil;return true end
            pcall(ATTACK[kind]);sleep(0.2)
        end
    end
    return true
end
-- Waende: Nachbarn ausserhalb der Form verkleiden bzw. zubauen.
-- false = Wandblock fehlt (Turtle holt Nachschub und macht hier weiter).
local function sealAround()
    if SEAL=="off" and not WALL then return true end
    local x,i,z=st.x,layer(st.y),st.z
    local function need(e,b)
        if not e then return SEAL=="all" end
        return SEAL~="off" and isLiquid(b.name)
    end
    local function face(kind,lineIt)
        if WALL and lineIt then return lineFace(kind) end
        local e,b=INSPECT[kind]()
        if need(e,b) and placeFill(kind) then st.sealed=(st.sealed or 0)+1 end
        return true
    end
    local function outside(nk) return nk~=BASE and (st.skip[nk] or not inPlan(nk)) end
    for _,v in ipairs({{"up",1},{"down",-1}}) do
        local nk=key(x,layer(st.y+v[2]),z)
        if layer(st.y+v[2])<0 then nk=-1 end
        if nk==-1 or outside(nk) then
            if not face(v[1],LINE[v[1]]) then return false end
        end
    end
    for d=0,3 do
        local nx,nz=x+W.DX[d],z+W.DZ[d]
        local nk=(nx>=0 and nz>=0) and key(nx,i,nz) or -1
        if nk==-1 or outside(nk) then
            if w.face(d) then
                if not face("forward",LINE.side) then return false end
            end
        end
    end
    return true
end
local function goHome()
    if w.isHome() then return w.face(0) end
    w.status("Rueckkehr","Faehrt zur Basis.")
    local ok,why=travel(BASE)
    if not ok then return false,"Rueckweg: "..tostring(why) end
    return w.face(0)
end
idleHome=function()
    if w.isHome() and st.dir==0 then return true end
    return goHome()
end
idleBase=function() return w.unload(keep) end
local function resupply()
    w.status("Rueckkehr","Abladen / Tanken an der Basis.")
    local ok,why=goHome();if not ok then return false,why end
    local ok2,title,detail=base();if not ok2 then w.status(title,detail);return false,title end
    return true
end
round=function()
    if st.done then st.done=nil;st.idx=1;st.skip={};w.save() end
    opts.readyText="START: Form ausheben | 1x: dasselbe (macht weiter, wo sie war)"
    if w.isHome() then
        local ok,title,detail=base();if not ok then w.status(title,detail);w.fail(title);return false end
    end
    while st.idx<=N do
        if not w.active() then w.save();return false end
        if w.freeSlots()<C.freeSlots then
            local ok,why=resupply();if not ok then w.fail(why);return false end
        end
        if fuel()<homeNeed()+40 then
            burnCoal(fuelGoal())
            if fuel()<homeNeed()+40 then
                local ok,why=resupply();if not ok then w.fail(why);return false end
            end
        end
        local k=cellAt(st.idx)
        run.scanned=st.idx-1
        if not st.skip[k] then
            local _,ki=unkey(k)
            w.status(st.noWall and "Wandblock fehlt" or st.noFill and "Kein Fuellmaterial" or "Graebt",
                st.idx<=ACCESS and "Zugang zur Form" or
                ("Ebene "..(ki+1).."/"..bh.." ("..(DOWN and "runter" or "hoch").."), Block "..st.idx.."/"..N))
            local ok,why=travel(k)
            if ok and not sealAround() then
                -- Wandblock alle: zur Basis, aus der Kiste OBEN nachladen, hier weitermachen
                local okr,whyr=resupply();if not okr then w.fail(whyr);return false end
                if wallCount()==0 then
                    w.status("Wandblock fehlt",WALL.." in die Kiste UEBER der Basis legen.")
                    w.fail("Wandblock fehlt: "..WALL);return false
                end
                st.idx=st.idx-1
            elseif ok then
            elseif why=="stopped" then w.save();return false
            elseif why=="keep" or why=="unreach" then st.skip[k]=true
            else w.fail(why);return false end
        end
        st.idx=st.idx+1;w.saveSoon()
    end
    run.scanned=N
    local okh,whyh=goHome();if not okh then w.fail(whyh);return false end
    local ok,title,detail=base();if not ok then w.status(title,detail) end
    st.done=true;w.save()
    opts.readyText="FERTIG: Form komplett. START = nochmal pruefen, N = neuer Auftrag"
    w.finish()
    return true
end
pcall(w.equipTool,isTool)
w.start("TOAST AUSHUB",SHAPE_NAMES[SHAPE].." "..(SHAPE=="room" and (C.width.."x"..C.length.."x"..C.height)
    or SHAPE=="cylinder" and ("D"..C.width.." x "..C.height) or ("D"..C.width))..(DOWN and " runter" or " hoch"))
]======]
FILES["build_turtle.lua"]=[======[
-- Toast Control: Mobfarm-Bau (vor allem fuer Creeper / Schwarzpulver).
-- Die Turtle steht an der spaeteren Toetungsstelle und baut ueber sich:
--   * einen 1x1-Fallschacht (Hoehe build.drop, Standard 22 = Mobs ueberleben
--     mit ~1 Herz, die Mob-Turtle gibt den Rest)
--   * build.floors dunkle Spawn-Etagen (innen 17x17, Waende + Decke dicht),
--     in jeder 4 Wasserkanaele, die die Mobs ins Loch in der Mitte schwemmen
--   * Bruchsteinstufen in jeder 3. Reihe: keine Spinnen (wuerden im 1x1-Loch
--     haengen bleiben)
--   * build.creeperOnly: Falltueren oben an der Decke -> nur 1,81 Bloecke frei:
--     Creeper (1,7) passen, Zombies/Skelette/Hexen/Endermen nicht.
-- Kisten: UNTER der Turtle = Ausgabe (spaeter die Drops), HINTER der Turtle =
-- Material (Bruchstein/Stein/Erde, Wassereimer, Bruchsteinstufen, Falltueren, Kohle).
-- Fertig + Schwert im Inventar: die Turtle wird selbst zur Mob-Turtle (greift
-- nur nach oben an).
local common=dofile("/toast/toast_common.lua")
local cfg=common.load()
local C=cfg.build
local W=dofile("/toast/toast_worker.lua")
local F,D=C.floors,C.drop
local CREEPER=C.creeperOnly~=false
-- Im Berg/Gelaende: alle Luftfelder freiraeumen. Sonst (im Freien) wie ein
-- 3D-Drucker: Schicht fuer Schicht nur die Bahnen, wo ein Block hinkommt.
local TERRAIN=C.inTerrain==true
local R=8                      -- Laenge der Wasserkanaele (Wasser fliesst 8 Bloecke)
local OUT=R+1                  -- Aussenwand
local B0=D                     -- unterste Etage (Boden)
local TOP=B0+4*F               -- Dach

-- ===== Bloecke =====
local FILL={}
for _,n in ipairs({"cobblestone","cobbled_deepslate","stone","deepslate","dirt","netherrack","andesite","diorite",
    "granite","tuff","calcite","blackstone","basalt","smooth_basalt","end_stone","coarse_dirt","mossy_cobblestone",
    "stone_bricks","sandstone","polished_andesite","polished_diorite","polished_granite"}) do FILL["minecraft:"..n]=true end
local OKSOLID={["minecraft:grass_block"]=true,["minecraft:podzol"]=true,["minecraft:mycelium"]=true,
    ["minecraft:rooted_dirt"]=true,["minecraft:terracotta"]=true,["minecraft:obsidian"]=true}
local function isFill(n) return FILL[n]==true end
local function isSlab(n) return n:find("_slab",1,true)~=nil and not n:find("wooden",1,true) end
local function isTrap(n) return n:find("_trapdoor",1,true)~=nil end
local function isWaterBucket(n) return n=="minecraft:water_bucket" end
local function isBucket(n) return n=="minecraft:bucket" end
local function isLiquid(n) return n=="minecraft:water" or n=="minecraft:lava" or n:find("flowing_",1,true)~=nil end
local function isTool(n) return n:find("_pickaxe",1,true)~=nil end
local function isSword(n) return n:find("_sword",1,true)~=nil end
local function isContainer(n) return n:find("chest",1,true)~=nil or n:find("barrel",1,true)~=nil or n:find("shulker",1,true)~=nil end
local function isTurtle(n) return n:find("computercraft:turtle",1,true)~=nil end

-- ===== Bauplan =====
-- Koordinaten: Turtle (Toetungsstelle) = 0,0,0, y nach oben. Der Schacht steht
-- direkt ueber der Turtle (x=0,z=0); die Etagen sind um ihn herum zentriert.
local SOLID,AIR,SRC,SLAB="s","a","w","p"
local function target(x,y,z)
    local ax,az=math.abs(x),math.abs(z)
    if y>=1 and y<B0 then
        if x==0 and z==0 then return AIR end
        if ax+az==1 then return SOLID end
        return nil
    end
    if y<B0 or y>TOP or ax>OUT or az>OUT then return nil end
    if y==TOP then return SOLID end
    local k=(y-B0)%4                         -- 0 Boden, 1 Spawnflaeche, 2+3 Luft
    if k==0 then return (x==0 and z==0) and AIR or SOLID end
    if ax==OUT or az==OUT then return SOLID end
    if x==0 and z==0 then return AIR end
    local channel=x==0 or z==0
    if k==1 then
        if channel then return math.max(ax,az)==R and SRC or AIR end
        return SOLID
    end
    if k==2 and not channel and az%3==0 then return SLAB end
    return AIR
end
-- Schritte: {t=Art,x,y=Hoehe der Turtle,z}. "cell" bearbeitet den Block UNTER der Turtle
-- (und raeumt Luftfelder 2 darueber gleich mit frei).
-- Sparsam fahren:
--  * Luftfelder, die schon 2 Lagen tiefer von unten freigeraeumt wurden, werden
--    nicht noch einmal angefahren (im Freien = fast alle Luftfelder).
--  * Reihenfolge je Lage: immer zum naechstgelegenen offenen Feld (Ringe werden
--    als Runde gefahren statt quer durch den Raum).
--  * Zur naechsten Lage direkt hoch (nicht ueber die Mitte).
--  * Schacht: Turtle steht IM Schacht und setzt die 4 Waende durch Drehen.
local STEPS={}
local function add(t) STEPS[#STEPS+1]=t end
local VIS={}                       -- VIS[y]["x,z"] = Lage y wurde dort bearbeitet
local function k2(x,z) return x..","..z end
local last={x=0,z=0}
local function layer(y,skipCenter)
    local r=(y<B0) and 1 or OUT
    local cells={}
    for z=-r,r do for x=-r,r do
        local tg=target(x,y,z)
        if tg and not (skipCenter and x==0 and z==0) and (TERRAIN or tg~=AIR) then
            local covered=tg==AIR and VIS[y-2] and VIS[y-2][k2(x,z)]
            if not covered then cells[#cells+1]={x=x,z=z} end
        end
    end end
    VIS[y]={}
    local cx,cz=last.x,last.z
    while #cells>0 do
        local bi,bd=1,math.huge
        for i,c in ipairs(cells) do
            local d=math.abs(c.x-cx)+math.abs(c.z-cz)
            if d<bd then bi,bd=i,d end
        end
        local c=table.remove(cells,bi)
        add({t="cell",x=c.x,y=y+1,z=c.z});VIS[y][k2(c.x,c.z)]=true
        cx,cz=c.x,c.z
    end
    last={x=cx,z=cz}
end
local function shaft(y)
    add({t="wall4",x=0,y=y,z=0})
    VIS[y]={[k2(0,0)]=true}
    last={x=0,z=0}
end
local function water(b)
    -- im Kreis, beginnend bei der naechstgelegenen Quelle
    local P={{R,0},{0,R},{-R,0},{0,-R}}
    local bi,bd=1,math.huge
    for i,p in ipairs(P) do local d=math.abs(p[1]-last.x)+math.abs(p[2]-last.z);if d<bd then bi,bd=i,d end end
    local nxt=P[bi%4+1];local prv=P[(bi+2)%4+1]
    local dir=(math.abs(nxt[1]-last.x)+math.abs(nxt[2]-last.z))<=(math.abs(prv[1]-last.x)+math.abs(prv[2]-last.z)) and 1 or -1
    for k=0,3 do
        local p=P[(bi-1+dir*k)%4+1]
        add({t="water",x=p[1],y=b+2,z=p[2]});last={x=p[1],z=p[2]}
    end
end
-- Falltueren: Turtle faehrt in der Etage auf Hoehe b+2 (ueber den Spawnstellen)
-- und setzt sie nach oben an die Decke. Wege nur durch die Kanaele (x=0) und
-- die Spawnreihen (die Stufenreihen sind belegt).
local function traps(b)
    if not CREEPER then return end
    for _,sx in ipairs({1,-1}) do for _,sz in ipairs({1,-1}) do
        for _,pair in ipairs({{1,2},{4,5},{7,8}}) do
            for x=1,R do add({t="trap",x=sx*x,y=b+2,z=sz*pair[1],corr=true}) end
            for x=R,1,-1 do add({t="trap",x=sx*x,y=b+2,z=sz*pair[2],corr=true}) end
        end
    end end
end
for y=1,B0-1 do shaft(y) end
for k=0,F-1 do
    local b=B0+4*k
    layer(b)
    if k>0 then traps(b-4) end
    layer(b+1);water(b)
    layer(b+2);layer(b+3)
end
layer(TOP,true)
traps(B0+4*(F-1))
add({t="cap",x=0,y=TOP-1,z=0})
local N=#STEPS
-- hoechste schon gebaute Lage VOR jedem Schritt (darueber ist alles noch frei)
local HB={}
do local hb=0
    for k=1,N do
        HB[k]=hb
        local s=STEPS[k]
        local l=s.t=="cell" and s.y-1 or s.t=="wall4" and s.y or s.t=="water" and s.y-1 or s.t=="trap" and s.y+1 or s.t=="cap" and TOP or 0
        if l>hb then hb=l end
    end
end
-- Material je Art ab Schritt i
local function remaining(i)
    local n={fill=0,slab=0,trap=0,water=0}
    for k=i or 1,N do
        local s=STEPS[k]
        if s.t=="cell" then
            local tg=target(s.x,s.y-1,s.z)
            if tg==SOLID then n.fill=n.fill+1 elseif tg==SLAB then n.slab=n.slab+1 end
        elseif s.t=="trap" then n.trap=n.trap+1
        elseif s.t=="water" then n.water=n.water+1
        elseif s.t=="cap" then n.fill=n.fill+1
        elseif s.t=="wall4" then n.fill=n.fill+4 end
    end
    return n
end
local TOTAL=remaining(1)
local LAYOUT=table.concat({"mobfarm",F,D,CREEPER and "c" or "n",TERRAIN and "t" or "p"},":")

local w,round,idleHome,idleBase
local opts
opts={job="build",cfg=cfg,section=C,stateFile="/toast_build_state",args={...},cells=N,layout=LAYOUT,
    tools=isTool,noTool="Keine Spitzhacke: Diamant-Spitzhacke in die Turtle legen",
    interval=0,readyText="START: Mobfarm bauen (macht weiter, wo sie war)",
    extra=function() local s=w and w.st or {}
        return {floors=F,drop=D,creeperOnly=CREEPER,placed=s.placed or 0,done=s.done,
            need=TOTAL.fill,needSlab=TOTAL.slab,needTrap=TOTAL.trap,needWater=TOTAL.water,
            fill=w and w.count(isFill) or 0,slabs=w and w.count(isSlab) or 0,traps=w and w.count(isTrap) or 0,
            buckets=w and w.count(isWaterBucket) or 0,missing=s.missing,trapFail=s.trapFail,
            phase=s.phase} end,
    round=function() return round() end,
    idleHome=function() return idleHome() end,
    idleBase=function() return idleBase() end}
w=W.new(opts)
local st,run=w.st,w.run
if st.buildLayout~=LAYOUT then st.buildLayout=LAYOUT;st.idx=1;st.done=nil;w.save() end
st.idx=st.idx or 1
if st.done then run.scanned=N;opts.readyText="FERTIG: Mobfarm steht. Schwert ins Inventar -> wird zur Mob-Turtle" end

-- ===== Bewegung =====
local INSPECT={forward=turtle.inspect,up=turtle.inspectUp,down=turtle.inspectDown}
local PLACE={forward=turtle.place,up=turtle.placeUp,down=turtle.placeDown}
local RAWDIG={forward=turtle.dig,up=turtle.digUp,down=turtle.digDown}
local DIG={}
for k,f in pairs(RAWDIG) do DIG[k]=function()
    local ok,why=f()
    if not ok and tostring(why):find("No tool",1,true) and w.equipTool(isTool) then ok,why=f() end
    return ok,why
end end
local corridor=false        -- in der Etage nur durch Kanal + Spawnreihen fahren
local MOPT={dig=true,attack=true,canDig=function(n)
    if isContainer(n) or isTurtle(n) then return false end
    if corridor and (isSlab(n) or isTrap(n)) then return false end
    return true end}
local function fuel() local f=turtle.getFuelLevel();if f=="unlimited" then return math.huge end;return f end
local function line(axis,v)
    while (axis=="x" and st.x or st.z)~=v do
        local cur=axis=="x" and st.x or st.z
        local d=axis=="x" and (v>cur and 1 or 3) or (v>cur and 0 or 2)
        local ok,why=w.face(d);if not ok then return false,why end
        ok,why=w.move("forward",MOPT);if not ok then return false,why end
    end
    return true
end
local function blockedZ(z0,z1)
    local s=z1>z0 and 1 or -1
    for z=z0+s,z1,s do if z~=0 and math.abs(z)%3==0 then return true end end
    return false
end
-- waagrecht auf der aktuellen Hoehe
local function horizontal(x,z)
    if corridor and st.z~=z and st.x~=0 and blockedZ(st.z,z) then
        local ok,why=line("x",0);if not ok then return false,why end
    end
    if corridor then
        local ok,why=line("z",z);if not ok then return false,why end
        return line("x",x)
    end
    local ok,why=line("x",x);if not ok then return false,why end
    return line("z",z)
end
-- Hoehe wechseln immer durch die Mittelsaeule (die ist im ganzen Bau frei)
local function goTo(x,y,z,corr,climb)
    -- ueber allem Gebauten: direkt hier hoch (spart den Weg zur Mitte und zurueck)
    if climb and y>st.y then
        corridor=false
        while st.y<y do
            local ok,why=w.move("up",MOPT);if not ok then return false,why end
        end
    end
    if st.y~=y then
        local ok,why=horizontal(0,0);if not ok then return false,why end
        corridor=false
        while st.y~=y do
            ok,why=w.move(st.y<y and "up" or "down",MOPT);if not ok then return false,why end
        end
    end
    corridor=corr==true
    local ok,why=horizontal(x,z)
    return ok,why
end
local function homeNeed() return math.abs(st.x)+math.abs(st.y)+math.abs(st.z)+20 end

-- ===== Material =====
local function fuelGoal()
    -- bis zum naechsten Nachladen: grob Restschritte, mindestens fuelTarget
    return math.min(turtle.getFuelLimit and turtle.getFuelLimit() or 20000,math.max(C.fuelTarget,(N-st.idx)*2+TOP*2+200))
end
local function burn(target)
    for s=1,16 do
        local it=turtle.getItemDetail(s)
        if it and W.FUELS[it.name] then
            turtle.select(s)
            while fuel()<target and turtle.getItemCount(s)>0 do if not turtle.refuel(1) then break end end
        end
        if fuel()>=target then break end
    end
    turtle.select(1)
end
local function keep(name)
    if isTool(name) or isSword(name) or common.MODEM_ITEMS[name] then return 4096 end
    if isFill(name) or isSlab(name) or isTrap(name) or isWaterBucket(name) then return 4096 end
    if W.FUELS[name] then return 64 end
    return 0
end
-- Materialkiste HINTER der Turtle (Turtle schaut dabei nach hinten = "front").
-- Mit der Kisten-Peripherie wird das gewuenschte Item erst nach vorne (Slot 1)
-- geschoben, dann eingesaugt - so ist die Reihenfolge in der Kiste egal.
local function chestList()
    local ok,inv=pcall(peripheral.wrap,"front")
    if not ok or type(inv)~="table" or type(inv.list)~="function" then return nil end
    return inv
end
local function fetch(match,count)
    local got=0
    for _=1,40 do
        if got>=count then break end
        local slot;for i=1,16 do if turtle.getItemCount(i)==0 then slot=i;break end end
        if not slot then break end
        local skipSuck=false
        local inv=chestList()
        if inv then
            local okl,list=pcall(inv.list)
            if not okl or type(list)~="table" then break end
            local from
            for s,it in pairs(list) do if match(it.name) and (not from or s<from) then from=s end end
            if not from then break end
            if from~=1 then
                local parked
                if list[1] then
                    local size=inv.size and inv.size() or 27
                    local free;for s=2,size do if not list[s] then free=s;break end end
                    if free then pcall(inv.pushItems,"front",1,64,free)
                    else
                        -- Kiste randvoll: Slot 1 kurz in die Turtle nehmen, danach zuruecklegen
                        local tmp;for i=16,1,-1 do if turtle.getItemCount(i)==0 and i~=slot then tmp=i;break end end
                        if not tmp then break end
                        turtle.select(tmp);if not turtle.suck() then break end
                        parked=tmp
                    end
                end
                pcall(inv.pushItems,"front",from,64,1)
                if parked then
                    turtle.select(slot)
                    local okS=turtle.suck(math.min(64,count-got))
                    turtle.select(parked);turtle.drop()
                    turtle.select(slot)
                    local it=turtle.getItemDetail(slot)
                    if not (okS and it and match(it.name)) then break end
                    got=got+it.count;skipSuck=true
                end
            end
        end
        if not skipSuck then
            turtle.select(slot)
            if not turtle.suck(math.min(64,count-got)) then break end
            local it=turtle.getItemDetail(slot)
            if not it then break end
            if not match(it.name) then
                -- falsches Item (ohne Kisten-Peripherie): in die Ausgabekiste
                turtle.dropDown();if not inv then break end
            else got=got+it.count end
        end
    end
    turtle.select(1)
    return got
end
local function have(match) return w.count(match) end
-- An der Basis: abladen, leere Eimer zurueck, Material + Kohle holen
local function base()
    local ok,title,detail=w.unload(keep)
    if not ok then return false,title,detail end
    local need=remaining(st.idx)
    local okf,why=w.face(2);if not okf then return false,"Drehen",why end
    if not w.container(turtle.inspect) then w.face(0);return false,"Materialkiste fehlt","Kiste HINTER die Turtle stellen (Bruchstein, Wassereimer, Stufen, Falltueren, Kohle)." end
    -- leere Eimer zurueck in die Materialkiste
    for i=1,16 do local it=turtle.getItemDetail(i);if it and isBucket(it.name) then turtle.select(i);turtle.drop() end end
    -- zu viel Bruchstein dabei (beim Graben eingesammelt): zurueck in die Materialkiste,
    -- damit Platz bleibt (sonst faehrt sie mit vollem Inventar immer wieder heim)
    for i=16,1,-1 do
        if w.freeSlots()>=(TERRAIN and 6 or 3) then break end
        local it=turtle.getItemDetail(i)
        if it and isFill(it.name) then
            turtle.select(i)
            if not turtle.drop() then turtle.dropDown() end
        end
    end
    turtle.select(1)
    -- Kohle
    if fuel()<fuelGoal() and have(function(n) return W.FUELS[n]~=nil end)<16 then
        fetch(function(n) return W.FUELS[n]~=nil end,32);burn(fuelGoal())
    end
    -- Sonderteile fuer den naechsten Abschnitt zuerst (Eimer stapeln sich nicht)
    local nextSpecial
    for k=st.idx,N do local t=STEPS[k].t;if t=="water" or t=="trap" or (t=="cell" and target(STEPS[k].x,STEPS[k].y-1,STEPS[k].z)==SLAB) then nextSpecial=t=="cell" and "slab" or t;break end end
    if nextSpecial=="water" and have(isWaterBucket)<math.min(4,need.water) then fetch(isWaterBucket,math.min(4,need.water)-have(isWaterBucket)) end
    if nextSpecial=="slab" and have(isSlab)<math.min(64,need.slab) then fetch(isSlab,math.min(64,need.slab)-have(isSlab)) end
    if nextSpecial=="trap" and have(isTrap)<math.min(128,need.trap) then fetch(isTrap,math.min(128,need.trap)-have(isTrap)) end
    -- Rest mit Baumaterial auffuellen, aber Platz fuer Abraum lassen (sonst muss sie
    -- im Gelaende nach wenigen Bloecken wieder heim). Hoechstens 8 Stapel dabei.
    local stacks=math.max(0,w.freeSlots()-(TERRAIN and 5 or 2))
    local want=math.min(need.fill,8*64)-have(isFill)
    if want>0 and stacks>0 then fetch(isFill,math.min(stacks*64,want)) end
    w.face(0)
    burn(fuelGoal())
    if fuel()<math.min(fuelGoal(),homeNeed()+TOP*2+100) then
        return false,"Treibstoff fehlt","Kohle in die Kiste HINTER der Turtle legen."
    end
    w.save()
    return true
end
local function goHome()
    if w.isHome() then return w.face(0) end
    w.status("Rueckkehr","Faehrt zur Basis (Nachschub).")
    local ok,why=goTo(0,0,0,false);if not ok then return false,"Rueckweg: "..tostring(why) end
    return w.face(0)
end
-- Nachschub holen; fehlt etwas, an der Basis warten bis es da ist
local MISSING={fill="Baumaterial fehlt",slab="Stufen fehlen",trap="Falltueren fehlen",water="Wassereimer fehlen"}
local HINT={fill="Bruchstein/Stein/Erde",slab="Bruchsteinstufen",trap="Falltueren (Holz)",water="Wassereimer"}
local function resupply(kind)
    local ok,why=goHome();if not ok then return false,why end
    while true do
        if not w.active() then return false,"stopped" end
        local okb,title,detail=base()
        local match=({fill=isFill,slab=isSlab,trap=isTrap,water=isWaterBucket})[kind]
        if okb and (not kind or not match or have(match)>0) then st.missing=nil;return true end
        if okb then
            local need=remaining(st.idx)
            title=MISSING[kind];detail=HINT[kind].." in die Kiste HINTER der Turtle legen (noch "..(need[kind] or "?").." gebraucht)."
        end
        st.missing=title;w.status(title,detail)
        for _=1,20 do if not w.active() then return false,"stopped" end;sleep(0.5) end
    end
end

-- ===== Bauen =====
local function placeDown(match)
    local slot=w.find(match);if not slot then return false,"material" end
    turtle.select(slot);local ok=turtle.placeDown();turtle.select(1)
    if ok then st.placed=(st.placed or 0)+1 end
    return ok
end
local function clearDown(keepWater)
    for _=1,8 do
        local e,b=turtle.inspectDown()
        if not e then return true end
        if isLiquid(b.name) then
            if keepWater and (b.name=="minecraft:water" or b.name:find("flowing_water",1,true)) then return true end
            local slot=w.find(isFill);if not slot then return false,"material" end
            turtle.select(slot);turtle.placeDown();turtle.select(1)
            DIG.down()
        elseif isContainer(b.name) or isTurtle(b.name) then return true
        else
            if not DIG.down() then return false,"Nicht abbaubar: "..b.name end
        end
    end
    local e,b=turtle.inspectDown()
    if e and isLiquid(b.name) and not keepWater then return false,"Wasser/Lava nicht wegzubekommen" end
    return true
end
local clearUp
local function doCell(s)
    local tg=target(s.x,s.y-1,s.z)
    local e,b=turtle.inspectDown()
    if tg==SOLID then
        if not (e and (isFill(b.name) or OKSOLID[b.name])) then
            if e then local ok,why=clearDown();if not ok then return false,why end end
            if not w.find(isFill) then return false,"material" end
            local ok=placeDown(isFill)
            if not ok then return false,"Block nicht setzbar" end
        end
    elseif tg==SLAB then
        if not (e and isSlab(b.name) and (b.state or {}).type~="top") then
            if e then local ok,why=clearDown();if not ok then return false,why end end
            if not w.find(isSlab) then return false,"slab" end
            if not placeDown(isSlab) then return false,"Stufe nicht setzbar" end
            local e2,b2=turtle.inspectDown()
            if e2 and (b2.state or {}).type=="top" then DIG.down();return false,"Stufe landet oben statt unten" end
        end
    else
        -- Wasser im Kanal (auch fliessendes) beim Ausbessern stehen lassen
        local y=s.y-1
        local inChannel=y>=B0 and (y-B0)%4==1 and (s.x==0 or s.z==0) and not (s.x==0 and s.z==0)
        local ok,why=clearDown(tg==SRC or inChannel)
        if not ok then return false,why end
    end
    -- Luftfeld 2 weiter oben gleich mit freiraeumen (dann muss die Lage dort nicht nochmal hin)
    local ta=target(s.x,s.y+1,s.z)
    if TERRAIN and (ta==AIR or ta==SRC) then
        local ya=s.y+1
        clearUp(ta==SRC or (ya>=B0 and (ya-B0)%4==1 and (s.x==0 or s.z==0)))
    end
    return true
end
-- Feld 2 ueber der Turtle (naechste Lage) gleich mit freiraeumen
clearUp=function(keepWater)
    for _=1,8 do
        local e,b=turtle.inspectUp()
        if not e then return true end
        if isLiquid(b.name) then
            if keepWater and (b.name=="minecraft:water" or b.name:find("flowing_water",1,true)) then return true end
            local slot=w.find(isFill);if not slot then return true end
            turtle.select(slot);turtle.placeUp();turtle.select(1)
            DIG.up()
        elseif isContainer(b.name) or isTurtle(b.name) or isSlab(b.name) or isTrap(b.name) then return true
        elseif not DIG.up() then return true end
    end
    return true
end
-- Schacht: Turtle steht im Schacht und setzt die 4 Waende rundum (Drehen kostet kein Fuel)
local function doWall4(s)
    for k=0,3 do
        local d=(st.dir+k)%4
        if target(W.DX[d],s.y,W.DZ[d])==SOLID then
            local ok,why=w.face(d);if not ok then return false,why end
            local e,b=turtle.inspect()
            if not (e and (isFill(b.name) or OKSOLID[b.name])) then
                if e and not isLiquid(b.name) and not isContainer(b.name) and not isTurtle(b.name) then
                    if not DIG.forward() then return false,"Nicht abbaubar: "..b.name end
                end
                local slot=w.find(isFill);if not slot then return false,"material" end
                turtle.select(slot);local okp=turtle.place();turtle.select(1)
                if okp then st.placed=(st.placed or 0)+1 else return false,"Block nicht setzbar" end
            end
        end
    end
    return true
end
local function doWater(s)
    local e,b=turtle.inspectDown()
    if e and b.name=="minecraft:water" and tonumber((b.state or {}).level or 0)==0 then return true end
    if e and not isLiquid(b.name) then local ok,why=clearDown();if not ok then return false,why end end
    local slot=w.find(isWaterBucket);if not slot then return false,"water" end
    turtle.select(slot);local ok=turtle.placeDown();turtle.select(1)
    if not ok then return false,"Wasser nicht setzbar" end
    return true
end
local function doTrap(s)
    if st.trapFail then return true end
    local e,b=turtle.inspectUp()
    if e and isTrap(b.name) then return true end
    if e then return true end                -- unerwartet belegt: lassen
    local slot=w.find(isTrap);if not slot then return false,"trap" end
    turtle.select(slot);local ok=turtle.placeUp();turtle.select(1)
    if not ok then return false,"Falltuer nicht setzbar" end
    local e2,b2=turtle.inspectUp()
    if e2 and (b2.state or {}).half=="bottom" then
        -- haengt unten statt oben: wuerde den Creepern den Platz nehmen -> wieder weg
        DIG.up();st.trapFail=true;w.save()
        common.log("Mobfarm: Falltueren lassen sich nicht oben anbringen, ohne Falltueren weiter")
    else st.placed=(st.placed or 0)+1 end
    return true
end
local function doCap()
    local e,b=turtle.inspectUp()
    if e and (isFill(b.name) or OKSOLID[b.name]) then return true end
    local slot=w.find(isFill);if not slot then return false,"material" end
    turtle.select(slot);local ok=turtle.placeUp();turtle.select(1)
    if ok then st.placed=(st.placed or 0)+1 end
    return ok or false,"Dach nicht setzbar"
end
local DO={cell=doCell,water=doWater,trap=doTrap,cap=doCap,wall4=doWall4}
local PHASE=function(s)
    if s.y-1<B0 and s.t=="cell" then return "Schacht" end
    if s.t=="water" then return "Wasser" end
    if s.t=="trap" then return "Falltueren" end
    if s.t=="cap" or s.y-1>=TOP then return "Dach" end
    return "Etage "..(math.floor((s.y-1-B0)/4)+1).."/"..F
end
-- Mob-Turtle werden: Schwert anlegen, Aufgabe umstellen, neu starten
local function becomeMob()
    if not C.becomeMob or not st.done or not w.isHome() then return false end
    local slot=w.find(isSword);if not slot then return false end
    if not w.equipTool(isSword) then return false end
    w.unload(function(n) if isSword(n) or common.MODEM_ITEMS[n] then return 4096 end;return 0 end)
    local okc,raw=pcall(dofile,"/toast.config.lua")
    if not okc or type(raw)~="table" then return false end
    raw.job="mob";raw.mob=raw.mob or {}
    local m=common.withDefaults(raw).mob
    m.mode="farm";m.attack="up";raw.mob=m
    raw.label=nil
    local f=fs.open("/toast.config.lua","w");f.write(common.configText(raw));f.close()
    common.log("Mobfarm fertig: Turtle wird zur Mob-Turtle")
    error("TOAST_UPDATE",0)
end
round=function()
    if st.done then
        -- Farm steht schon: nicht nochmal durch die fertigen Etagen fahren
        w.status("Fertig","Mobfarm steht schon. Neu bauen: an der Turtle N (neuer Auftrag).")
        w.finish();becomeMob()
        return true
    end
    opts.readyText="START: Mobfarm bauen (macht weiter, wo sie war)"
    if w.isHome() then
        local ok=resupply(nil);if not ok then return false end
    end
    while st.idx<=N do
        if not w.active() then w.save();return false end
        local s=STEPS[st.idx]
        run.scanned=st.idx-1
        st.phase=PHASE(s)
        if w.freeSlots()==0 or fuel()<homeNeed()+math.abs(s.y-st.y)+40 then
            local ok,why=resupply(nil);if not ok then if why~="stopped" then w.fail(why) end;return false end
        end
        w.status("Baut",st.phase.." - Schritt "..st.idx.."/"..N)
        local ok,why=goTo(s.x,s.y,s.z,s.corr,st.y>HB[st.idx])
        if ok then ok,why=DO[s.t](s) end
        if ok then
            st.idx=st.idx+1;w.saveSoon()
        elseif why=="stopped" then w.save();return false
        elseif why=="material" or why=="slab" or why=="trap" or why=="water" then
            local okr,whyr=resupply(why=="material" and "fill" or why)
            if not okr then if whyr~="stopped" then w.fail(whyr) end;return false end
        else w.fail(why);return false end
    end
    run.scanned=N
    local okh,whyh=goHome();if not okh then w.fail(whyh);return false end
    w.unload(keep)
    st.done=true;st.phase="Fertig";w.save()
    opts.readyText="FERTIG: Mobfarm steht. Schwert ins Inventar -> wird zur Mob-Turtle"
    w.status("Fertig","Mobfarm steht. Schwert ins Inventar legen -> wird zur Mob-Turtle.")
    w.finish()
    becomeMob()
    return true
end
idleHome=function()
    if w.isHome() and st.dir==0 then return true end
    return goHome()
end
idleBase=function()
    if st.done then
        becomeMob()
        return true
    end
    return w.unload(keep)
end
pcall(w.equipTool,isTool)
w.start("TOAST MOBFARM-BAU",F.." Etage(n), Schacht "..D..(CREEPER and ", nur Creeper" or ""))
]======]
FILES["toast_gps.lua"]=[======[
-- Toast Control: GPS-Sender. Beantwortet GPS-Anfragen (gps locate) von Turtles,
-- Pockets und Computern mit den eigenen Koordinaten. Man braucht mindestens 4
-- GPS-Sender, die NICHT alle auf einer Hoehe/Ebene stehen.
-- Koordinaten: aus der Config (gps.x/y/z) oder - wenn schon andere GPS-Sender
-- laufen und gps.auto = true - beim Start selbst per GPS ermittelt.
local common=dofile("/toast/toast_common.lua")
local cfg=common.load();assert(cfg.role=="gps","GPS-Sender erforderlich.")
local G=cfg.gps
local CH=gps and gps.CHANNEL_GPS or 65534
local function wireless()
    local list={}
    for _,name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name)=="modem" then
            local m=peripheral.wrap(name)
            if m and m.isWireless and m.isWireless() then m.open(CH);list[name]=m end
        end
    end
    return list
end
local modems=wireless()
assert(next(modems),"Funk- oder Endermodem fehlt (Endermodem = unbegrenzte Reichweite).")
local x,y,z,source=G.x,G.y,G.z,"Config"
if G.auto and gps and gps.locate then
    print("Suche eigene Position per GPS ...")
    local ok,ax,ay,az=pcall(gps.locate,2)
    if ok and ax then
        x,y,z,source=math.floor(ax+0.5),math.floor(ay+0.5),math.floor(az+0.5),"GPS"
        if x~=G.x or y~=G.y or z~=G.z then
            -- gefundene Position merken (falls spaeter weniger Sender laufen)
            G.x,G.y,G.z=x,y,z
            pcall(function()
                local c=common.withDefaults(dofile("/toast.config.lua"));c.gps.x,c.gps.y,c.gps.z=x,y,z
                local f=fs.open("/toast.config.lua","w");f.write(common.configText(c));f.close()
            end)
        end
    end
end
local served,last,started=0,"-",os.clock()
common.refreshModems()       -- rednet fuer Meldung an die Zentrale und Update-Befehl
local function draw()
    local w,h=term.getSize()
    term.setBackgroundColor(colors.black);term.clear()
    local function line(yy,text,col)
        if yy>h then return end
        term.setCursorPos(1,yy);if term.isColor and term.isColor() then term.setTextColor(col or colors.white) end
        term.write(tostring(text):sub(1,w))
    end
    line(1,"TOAST GPS-SENDER v"..common.version.."  #"..os.getComputerID(),colors.cyan)
    line(3,"Position  X "..x.."  Y "..y.."  Z "..z,colors.lime)
    line(4,"Quelle    "..source,colors.lightGray)
    local n=0;for _ in pairs(modems) do n=n+1 end
    line(5,"Modems    "..n,colors.lightGray)
    line(7,"Anfragen  "..served)
    line(8,"Zuletzt   "..last,colors.lightGray)
    line(10,"Mind. 4 Sender, nicht alle auf einer Ebene.",colors.lightGray)
    line(11,"Q: beenden",colors.lightGray)
end
draw()
local timer=os.startTimer(2)
while true do
    local e,a,b,c,d,dist=os.pullEvent()
    if e=="modem_message" and b==CH and d=="PING" and dist then
        local m=modems[a] or peripheral.wrap(a)
        if m then pcall(m.transmit,c,CH,{x,y,z});served=served+1;last=(textutils.formatTime and textutils.formatTime(os.time(),true) or "jetzt") end
        draw()
    elseif e=="peripheral" or e=="peripheral_detach" then modems=wireless();draw()
    elseif e=="rednet_message" and common.isUpdateFor(cfg,a,b) then
        local ok,why=common.selfUpdate(nil,b.target)
        if not ok then common.log("Update: "..tostring(why)) end
    elseif e=="timer" and a==timer then
        cfg.gps.x,cfg.gps.y,cfg.gps.z,cfg.gps.set=x,y,z,true
        common.nodeBeacon(cfg,"gps",{gps=served})
        draw();timer=os.startTimer(10)
    elseif e=="char" and (a=="q" or a=="Q") then
        term.clear();term.setCursorPos(1,1);print("GPS-Sender beendet.");return
    end
end
]======]
FILES["toast_storage.lua"]=[======[
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
local function screenOf(name) for _,s in ipairs(screens) do if s.name==name then return s end end end
local function act(s,a)
    if not s or not a then return end
    s.ui.action(a);draw()
end
-- Drei Ablaeufe nebeneinander: Auslesen der Kisten blockiert sonst alles andere
-- (Peripherie-Aufrufe warten auf ihre Antwort und schlucken dabei Timer/Funk -
-- frueher ging dadurch das Lebenszeichen verloren und das Lager wurde "offline").
local function scanLoop()
    while true do
        sleep(C.interval)
        scan();draw()
    end
end
local function beaconLoop()
    while true do
        pcall(common.refreshModems);beacon()
        sleep(5)
    end
end
local function uiLoop()
    while true do
        local e,a,b,c,d,f=os.pullEvent()
        if gpsHost and gpsHost.event(e,a,b,c,d,f) then
            -- GPS-Anfrage beantwortet
        elseif e=="rednet_message" and common.isUpdateFor(cfg,a,b) then
            notice="Update wird installiert ...";draw()
            local ok,why=common.selfUpdate(nil,b.target)
            if not ok then notice="Update: "..tostring(why);common.log(notice);draw() end
        elseif e=="monitor_touch" then local s=screenOf(a);if s then act(s,s.ui.click(b,c)) end
        elseif e=="mouse_click" then local s=screenOf(nil);act(s,s.ui.click(b,c))
        elseif e=="mouse_scroll" then local s=screenOf(nil);act(s,a>0 and "down" or "up")
        elseif e=="char" then local s=screenOf(nil);act(s,s.ui.char(a))
        elseif e=="key" then local s=screenOf(nil);act(s,s.ui.key(keys.getName(a)))
        elseif e=="peripheral" or e=="peripheral_detach" or e=="monitor_resize" or e=="term_resize" then
            bind();draw()
        end
    end
end
parallel.waitForAny(scanLoop,beaconLoop,uiLoop)
]======]
-- TOAST CONTROL 3.17.5 – Ein-Datei-Installer (alle Programme sind hier eingebaut).
-- Start: wget run <link>            -> Update oder Komplett neu
--        wget run <link> clean      -> Komplett neu
--        wget run <link> farm|mining|tree|mob|repeater
-- Vor dem Schreiben wird ALLES Alte geloescht, damit nichts kollidiert.
local args={...}
local requested,clean
-- "auto": Update ohne Fragen (vom Update-Knopf der Zentrale ausgeloest).
-- Behaelt Config, Fortschritt und Autostart; startet nichts selbst.
local auto,internal=false,false
for _,a in ipairs(args) do
    a=a:lower()
    if a=="auto" then auto=true;clean=false
    elseif a=="intern" then internal=true
    elseif a=="clean" or a=="neu" then clean=true
    elseif a=="farm" or a=="mining" or a=="tree" or a=="mob" or a=="dig" or a=="build" or a=="repeater" then requested=a
    else error("Optional: farm / mining / repeater / clean / auto",0) end
end
local code=FILES
local common=assert(load(code["toast_common.lua"],"@toast_common.lua"))()
local ui=assert(load(code["toast_setup.lua"],"@toast_setup.lua"))().new(common)
local color=term.isColor and term.isColor()
local function fg(c) if color then term.setTextColor(c) end end
local function warn(s) fg(colors.orange);print(s);fg(colors.white) end
local hadStartup=fs.exists("/startup.lua") and (function() local f=fs.open("/startup.lua","r");local v=f.readAll();f.close();return v end)()
ui.header("Installation auf Geraet #"..os.getComputerID())
print("")
local newJob=false
if clean==nil then
    fg(colors.yellow);write("1 ");fg(colors.white);print("Update")
    ui.hint("  Einstellungen + Fortschritt bleiben")
    fg(colors.yellow);write("2 ");fg(colors.white);print("Komplett neu")
    ui.hint("  ALLES auf dem Geraet loeschen")
    if turtle and fs.exists("/toast.config.lua") then
        fg(colors.yellow);write("3 ");fg(colors.white);print("Neuer Auftrag")
        ui.hint("  nur neue Werte, alter Fortschritt weg")
    end
    print("")
    write("Auswahl [1]: ")
    local answer=read()
    clean=answer=="2"
    newJob=answer=="3" and turtle~=nil and fs.exists("/toast.config.lua")
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
for _,n in ipairs({"toast_farm_state","toast_mining_state","toast_tree_state","toast_mob_state","toast_dig_state","toast_control_state","toast_pocket_state"})do
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
-- Neues Geraet ohne Config: "auto" geht nicht ohne Angaben -> normale Einrichtung
if auto and not existing then
    if internal then error("Auto-Update: keine gueltige Config.",0) end
    auto=false
    warn("Noch nicht eingerichtet: normale Installation.")
    sleep(1)
end
if existing and not pcall(function()
    local copy=common.copy(existing);copy.role=((copy.role=="repeater" or copy.role=="info" or copy.role=="gps" or copy.role=="storage") and not turtle and not pocket) and copy.role or nil;common.load(copy) end) then
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
if not turtle and not pocket and c.role=="gps" and not requested then role="gps" end
if not turtle and not pocket and c.role=="storage" and not requested then role="storage" end
-- Neuer stationaerer Computer: Zentrale oder Repeater? Ohne Monitor ist Repeater vorgewaehlt.
if role=="controller" and not requested and (clean or not existing) then
    local monitor=peripheral.find("monitor")~=nil
    ui.header("Computer"..(monitor and " mit Monitor" or " ohne Monitor"))
    print("")
    fg(colors.yellow);write("1 ");fg(colors.white);print("Zentrale  (steuert alle Turtles)")
    fg(colors.yellow);write("2 ");fg(colors.white);print("Repeater  (leitet Funk weiter)")
    fg(colors.yellow);write("3 ");fg(colors.white);print("Infoscreen  (zeigt nur Infos/Stats)")
    fg(colors.yellow);write("4 ");fg(colors.white);print("GPS-Sender  (fuer Turtle-Koordinaten)")
    fg(colors.yellow);write("5 ");fg(colors.white);print("Lager  (Kisten: Fuellstand + Inhalt)")
    print("")
    while true do
        write("Auswahl ["..(monitor and "1" or "2").."]: ")
        local v=read()
        if v=="" then v=monitor and "1" or "2" end
        if v=="1" then break end
        if v=="2" then role="repeater";break end
        if v=="3" then role="info";break end
        if v=="4" then role="gps";break end
        if v=="5" then role="storage";break end
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
    fg(colors.yellow);write("1 ");fg(colors.white);print("Farm      (Feld, Hacke)")
    fg(colors.yellow);write("2 ");fg(colors.white);print("Mining    (Spitzhacke)")
    fg(colors.yellow);write("3 ");fg(colors.white);print("Holz      (Baeume, Axt)")
    fg(colors.yellow);write("4 ");fg(colors.white);print("Mobs      (Schwert)")
    fg(colors.yellow);write("5 ");fg(colors.white);print("Aushub    (Raum/Schacht/Kugel, Spitzh.)")
    fg(colors.yellow);write("6 ");fg(colors.white);print("Mobfarm   (baut Creeper-Farm, Spitzh.)")
    print("")
    while true do
        write("Aufgabe: ")
        local answer=read():lower()
        if answer=="1" or answer=="farm" or answer=="f" then return "farm" end
        if answer=="2" or answer=="mining" or answer=="m" then return "mining" end
        if answer=="3" or answer=="tree" or answer=="holz" or answer=="h" then return "tree" end
        if answer=="4" or answer=="mob" or answer=="mobs" then return "mob" end
        if answer=="5" or answer=="dig" or answer=="aushub" or answer=="a" then return "dig" end
        if answer=="6" or answer=="build" or answer=="mobfarm" or answer=="bau" then return "build" end
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
    elseif role~="repeater" and role~="gps" and not source then
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
local show=clean or not existing or requested or newJob
if not show and not auto then
    ui.header("Update")
    print("")
    show=ui.yesno("Einstellungen ansehen/aendern?",false)
end
while true do
    if show then ui.run(c,{role=role,job=job,installer=true,newJob=newJob and role=="turtle"}) end
    local ok,why=pcall(function() common.load(common.copy(c)) end)
    if ok then break end
    if auto then error("Auto-Update: Config ungueltig: "..tostring(why),0) end
    ui.header("Einstellung ungueltig");warn(tostring(why));sleep(2);show=true
end
local resetProgress
if newJob and role=="turtle" then resetProgress=ui.newJob(job)
else resetProgress=not clean and before~=ui.layoutKey(c,job) and ui.confirmReset(job) end
common.load(c)
local names={"toast.lua","toast_common.lua","toast_setup.lua"}
if role=="controller" then
    for _,name in ipairs({"toast_control.lua","toast_model.lua","toast_ui.lua"})do names[#names+1]=name end
elseif role=="pocket" then names[#names+1]="toast_pocket.lua";names[#names+1]="toast_ui.lua"
elseif role=="info" then names[#names+1]="toast_info.lua";names[#names+1]="toast_ui.lua"
elseif role=="gps" then names[#names+1]="toast_gps.lua"
elseif role=="storage" then names[#names+1]="toast_storage.lua";names[#names+1]="toast_ui.lua"
elseif role=="turtle" then
    -- Alle Turtle-Programme: Aufgabe spaeter ohne Neuinstallation wechselbar
    for _,n in ipairs({"farm_turtle.lua","farm_common.lua","mine_turtle.lua","mine_common.lua",
        "tree_turtle.lua","mob_turtle.lua","dig_turtle.lua","build_turtle.lua","toast_worker.lua"}) do names[#names+1]=n end
else names[#names+1]="repeater.lua" end
for _,name in ipairs(names)do assert(code[name] and load(code[name],"@"..name),"Installer beschaedigt: "..name) end
if role=="turtle" and (job=="farm" or job=="mining") then
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
print((role=="turtle" and ("Turtle / "..(common.JOB_NAMES[job] or job))
    or ({controller="Zentrale",pocket="Pocket",repeater="Repeater",info="Infoscreen",gps="GPS-Sender",storage="Lager"})[role])..(c.name~="" and (" / "..c.name) or ""))
if role~="controller" and role~="repeater" and role~="gps" then print("Zentrale #"..c.controllerId) end
print(clean and "Komplett neu installiert." or "Update: Einstellungen behalten.")
if resetProgress then print("Neuer Auftrag: alter Fortschritt geloescht.") end
ui.hint("Spaeter aendern: toast.lua config")
local checked=common.load()
assert(checked.role==role,"role passt nicht zum erkannten Geraet.")
if role=="turtle" and (checked.job=="farm" or checked.job=="mining") then
    local prefix=checked.job=="farm" and "farm" or "mine"
    dofile("/toast/"..prefix.."_common.lua").load(common.workerConfig(checked))
end
print("")
if auto then
    -- Autostart wie vorher
    if hadStartup then local f=fs.open("/startup.lua","w");f.write(hadStartup);f.close() end
    -- Vom Update-Knopf (laufendes Programm startet sich selbst neu): fertig.
    -- Von Hand ("wget run ... auto"): Toast gleich wieder starten.
    if internal or not shell then return true end
    print("Starte Toast ...")
    shell.run("/toast.lua")
    return true
end
if ui.yesno("Autostart einrichten?",true) then
    local f=assert(fs.open("/startup.lua","w"));f.write('shell.run("/toast.lua")\n');f.close()
end
if ui.yesno("Jetzt starten?",true) then shell.run("/toast.lua") end
