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
    if cfg.role=="turtle" and (cfg.job=="tree" or cfg.job=="mob" or cfg.job=="dig") then
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
    local program=({controller="toast_control.lua",pocket="toast_pocket.lua",repeater="repeater.lua",info="toast_info.lua",gps="toast_gps.lua"})[cfg.role]
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
    if newJob then ui.newJob(job)
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
