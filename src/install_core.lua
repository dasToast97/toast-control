-- TOAST CONTROL 3.9.1 – Ein-Datei-Installer (alle Programme sind hier eingebaut).
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
    elseif a=="farm" or a=="mining" or a=="tree" or a=="mob" or a=="dig" or a=="repeater" then requested=a
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
    print("")
    while true do
        write("Aufgabe: ")
        local answer=read():lower()
        if answer=="1" or answer=="farm" or answer=="f" then return "farm" end
        if answer=="2" or answer=="mining" or answer=="m" then return "mining" end
        if answer=="3" or answer=="tree" or answer=="holz" or answer=="h" then return "tree" end
        if answer=="4" or answer=="mob" or answer=="mobs" then return "mob" end
        if answer=="5" or answer=="dig" or answer=="aushub" or answer=="a" then return "dig" end
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
        "tree_turtle.lua","mob_turtle.lua","dig_turtle.lua","toast_worker.lua"}) do names[#names+1]=n end
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
