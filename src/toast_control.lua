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
