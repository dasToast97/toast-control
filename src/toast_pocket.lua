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
local function loop()
    poll();draw();local timer=os.startTimer(cfg.network.pollInterval)
    while true do
        local e,a,b,c=os.pullEvent()
        if e=="rednet_message" and a==cfg.controllerId and c==common.remoteProtocol and type(b)=="table"
            and b.kind=="fleet" and b.version==1 and b.controllerId==cfg.controllerId and validFleet(b.fleet) then
            fleet,seen=b.fleet,os.clock();serial=math.max(serial,common.number(b.ack))
            if pending and common.number(b.ack)>=pending.message.serial then pending=nil end
            notice=pending and "Warte auf Zentrale..." or tostring(b.notice or "Verbunden");draw()
        elseif e=="rednet_message" and a==cfg.controllerId and c==common.remoteProtocol and type(b)=="table"
            and b.kind=="update" and b.controllerId==cfg.controllerId then
            notice="Update wird installiert ...";draw()
            local ok,why=common.selfUpdate()
            if not ok then notice="Update fehlgeschlagen: "..tostring(why);draw() end
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
