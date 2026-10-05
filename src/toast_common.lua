local M={
    version="3.17.0",
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
    build={floors=2,drop=22,creeperOnly=true,becomeMob=true,fuelTarget=2000,radioTimeout=0},
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
    assert(type(b.creeperOnly)=="boolean" and type(b.becomeMob)=="boolean","build.creeperOnly/becomeMob: true oder false.")
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
        while os.clock()-t0<0.6 and (o.contact() or 0)<t0 do sleep(0.05) end
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
    build={"floors","drop","creeperOnly"}}
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
-- Werkzeug-Namen (links/rechts) fuer die Fernsteuerung
local function equipped(side)
    local fn=turtle and (side=="left" and turtle.getEquippedLeft or turtle.getEquippedRight)
    if fn then local ok,it=pcall(fn);if ok and type(it)=="table" and it.name then return it.name end end
    local t=peripheral.getType(side)
    return t
end
-- Zusatzwerte im Status, solange ferngesteuert wird
function M.manualInfo(run,snap)
    if not (run.manual or run.manualMsg) then return end
    snap.manual=run.manual==true;snap.mMsg=run.manualMsg
    if run.manual and turtle then
        local function look(fn) local ok,e,b=pcall(fn);if ok and e and type(b)=="table" then return b.name end;return "Luft" end
        snap.mFront=look(turtle.inspect);snap.mUp=look(turtle.inspectUp);snap.mDown=look(turtle.inspectDown)
        snap.mLeft=equipped("left");snap.mRight=equipped("right")
    end
end
-- Empfang + Ausfuehrung. o = {cfg,job,st,run,save,transmit(msg),ops={op=fn},atHome,stopped}
-- handle(b) im Funk-Ablauf aufrufen; loop() als eigenen Ablauf mitlaufen lassen
-- (fuehrt die Schritte aus, damit der Funk dabei nicht blockiert).
function M.remoteControl(o)
    local R={queue={}}
    local NAMES={forward="Vor",back="Zurueck",up="Hoch",down="Runter",left="Links drehen",right="Rechts drehen",
        dig="Abbauen vorne",digUp="Abbauen oben",digDown="Abbauen unten",attack="Angriff vorne",attackUp="Angriff oben",
        attackDown="Angriff unten",place="Setzen vorne",placeUp="Setzen oben",placeDown="Setzen unten"}
    local function sendConfig(ok,msg)
        local okc,raw=pcall(dofile,"/toast.config.lua")
        local c=okc and type(raw)=="table" and M.withDefaults(raw) or o.cfg
        local cf=M.remoteConfig(c)
        pcall(o.transmit,{kind="config",version=1,id=os.getComputerID(),config=cf,ok=ok,msg=msg})
    end
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
            else run.manual=true;run.manualMsg="Fernsteuerung an" end
        elseif op=="manual_off" then run.manual=nil;run.manualMsg="Fernsteuerung aus - faehrt zur Basis"
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
