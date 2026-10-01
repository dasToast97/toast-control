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
