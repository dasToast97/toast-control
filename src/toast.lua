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
    if cfg.role=="turtle" and (cfg.job=="tree" or cfg.job=="mob") then
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
