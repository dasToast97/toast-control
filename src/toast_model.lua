local common=dofile("/toast/toast_common.lua")
local M={}
function M.new(cfg)
    local m={entries={},pending={},notice="Warte auf Geraete...",config=cfg}
    local PATH="/toast_control_state"
    local s=common.readState(PATH)
    local serial=common.serial(s.serial) and s.serial or 0
    local devices,pockets,remote={}, {}, {}
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
    function m.fleet(scope)
        local ids,entries={},{}
        for id,d in pairs(devices) do if scope==nil or scope=="all" or d.job==scope then ids[#ids+1]=id end end
        table.sort(ids)
        for _,id in ipairs(ids)do
            local e=m.entries[id];local d=devices[id]
            entries[id]={job=d.job,label=d.label,online=m.online(id),data=e and e.data or nil,pending=m.pending[id]~=nil}
        end
        return {ids=ids,entries=entries}
    end
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
        if pending and common.number(b.ack)>=pending.message.serial then m.pending[id]=nil end
        if changed then save() end
        return true
    end
    local function matches(id,d,target)
        return target=="all" or target==id or target==d.job
    end
    function m.command(action,target)
        if not common.actions[action] then return false end
        if target~="all" and target~="farm" and target~="mining" and not (common.id(target) and devices[target]) then return false end
        local changed={}
        local always=action=="stop" or action=="reset"
        for id,d in pairs(devices) do
            local e=m.entries[id]
            if matches(id,d,target) and (always or (m.online(id) and not e.data.recovery)) then
                serial=math.max(serial+1,os.epoch("utc"),e and common.number(e.data.ack)+1 or 0)
                m.pending[id]={message={kind="command",action=action,serial=serial},at=os.clock(),job=d.job}
                changed[#changed+1]=id
            end
        end
        if #changed==0 then m.notice="Kein erreichbares Ziel / Position unklar";return false end
        save()
        for _,id in ipairs(changed)do local p=m.pending[id];dispatch(id,p.message,p.job) end
        m.notice=string.upper(action)..": "..#changed.." Turtle(s), warte auf ACK"
        return true
    end
    local function key(id,protocol)return protocol..":"..id end
    function m.reply(id,protocol)
        protocol=protocol or common.remoteProtocol
        local scope="all";for j,p in pairs(common.legacyRemote)do if p==protocol then scope=j end end
        local f=m.fleet(scope);local labels={}
        for _,tid in ipairs(f.ids)do labels[tid]=f.entries[tid].label end
        send(id,{kind="fleet",version=protocol==common.remoteProtocol and 1 or 2,
            controllerId=cfg.controllerId,fleet=f,labels=labels,ack=remote[key(id,protocol)] or 0,notice=m.notice},protocol)
    end
    function m.remote(id,b,protocol)
        local scope="all";local valid=protocol==common.remoteProtocol
        for j,p in pairs(common.legacyRemote)do if p==protocol then scope=j;valid=true end end
        if not valid or not common.id(id) or id==cfg.controllerId or devices[id] or type(b)~="table" then return false end
        if not pockets[id] then
            if not (cfg.autoPairPockets and protocol==common.remoteProtocol and b.kind=="hello"
                and b.version==1 and b.role=="pocket" and b.controllerId==cfg.controllerId) then return false end
            local n=0;for _ in pairs(pockets)do n=n+1 end
            if n>=64 then return false end
            pockets[id]=true;save()
        end
        if b.kind=="command" and common.serial(b.serial) and b.serial>(remote[key(id,protocol)] or 0) then
            local target=b.target
            if scope~="all" then
                if target=="all" then target=scope
                elseif not devices[target] or devices[target].job~=scope then m.reply(id,protocol);return true end
            end
            if m.command(b.action,target) then remote[key(id,protocol)]=b.serial;save() end
        end
        m.reply(id,protocol);return true
    end
    function m.tick()
        common.refreshModems()
        for id,d in pairs(devices)do dispatch(id,{kind="poll"},d.job)end
        if cfg.autoDiscover then for _,p in pairs(common.workerProtocols)do pcall(rednet.broadcast,{kind="poll"},p)end end
        local waiting,expired=0,0
        for id,p in pairs(m.pending)do
            if os.clock()-p.at>=cfg.network.commandTimeout then m.pending[id]=nil;expired=expired+1
            else waiting=waiting+1;dispatch(id,p.message,p.job) end
        end
        if expired>0 then m.notice="Befehl nicht bestaetigt: "..expired
        elseif waiting==0 and m.notice:find("warte auf ACK",1,true) then m.notice="Befehl von Turtle(s) bestaetigt" end
        for id in pairs(pockets)do m.reply(id)end
    end
    function m.waiting()local n=0;for _ in pairs(m.pending)do n=n+1 end;return n end
    return m
end
return M
