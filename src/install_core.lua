-- TOAST CONTROL 2.2 – Ein-Datei-Installer (alle Programme sind hier eingebaut).
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
if clean or not existing or requested or configChanged then
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
