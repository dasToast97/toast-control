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
local AUTO={next=os.clock()+60,url=nil,every=300}
local function checkVersion()
    if cfg.autoUpdate==false or not http or not http.request or AUTO.url or os.clock()<AUTO.next or model.selfUpdateAt then return end
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
    local cmd=ui.action(a);if cmd then model.command(cmd,ui.target())end;draw()
end
local quit=false
local function loop()
    rednet.host(common.protocol,"toast-"..cfg.controllerId)
    model.tick();draw()
    local timer=os.startTimer(cfg.network.pollInterval)
    local frame=os.startTimer(0.25)
    -- Automatisches Update: kurz nach dem Start und dann alle updateEvery Minuten
    local upTimer=cfg.autoUpdate and os.startTimer(30) or nil
    while true do
        local e,a,b,c,d,f=os.pullEvent()
        if gpsHost and gpsHost.event(e,a,b,c,d,f) then
            -- GPS-Anfrage beantwortet
        elseif e=="rednet_message" then
            if model.ingest(a,b,c) or model.remote(a,b,c) then dirty=true end
        elseif e=="timer" and a==timer then model.tick();checkVersion();dirty=true;timer=os.startTimer(cfg.network.pollInterval)
        elseif e=="http_success" and AUTO.url and a==AUTO.url then
            AUTO.url=nil
            local remote=b and b.readAll and b.readAll() or "";pcall(b.close)
            remote=remote:match("[%d%.]+")
            if remote and common.newer(remote,common.version) then
                common.log("Neue Version "..remote.." gefunden, Update fuer alle")
                model.command("update","all")
                model.notice="Neue Version "..remote..": Update fuer alle gestartet"
                dirty=true
            end
        elseif e=="http_failure" and AUTO.url and a==AUTO.url then AUTO.url=nil
        elseif e=="timer" and a==upTimer then
            upTimer=os.startTimer(cfg.updateEvery*60)
            if not model.selfUpdateAt then
                local ok,remote=pcall(common.remoteVersion)
                if ok and remote and common.newer(remote,common.version) then
                    common.log("Neue Version "..remote.." gefunden, Update fuer alle")
                    model.command("update","all")
                    model.notice="Neue Version "..remote..": Update fuer alle laeuft ..."
                    dirty=true
                end
            end
        elseif e=="timer" and a==frame and model.selfUpdateAt and (os.clock()>=model.selfUpdateAt or (model.waiting()==0 and os.clock()>=model.selfUpdateAt-20)) then
            -- Alle Geraete haben das Update bekommen (oder Zeit um): jetzt die Zentrale selbst
            model.selfUpdateAt=nil
            model.notice="Zentrale installiert Update ...";draw()
            local ok,why=common.selfUpdate()
            if not ok then model.notice="Update fehlgeschlagen: "..tostring(why);common.log("Update: "..tostring(why)) end
            frame=os.startTimer(0.25)
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
