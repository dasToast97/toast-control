local common=dofile("/toast/toast_common.lua")
local M={}
function M.new(cfg)
    local m={entries={},pending={},notice="Warte auf Geraete...",config=cfg}
    local PATH="/toast_control_state"
    local s=common.readState(PATH)
    local serial=common.serial(s.serial) and s.serial or 0
    local devices,pockets,remote={}, {}, {}
    m.nodes={}           -- Netzgeraete: [id]={role,label,data,seen}
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
        local nids,nentries={},{}
        for id,n in pairs(m.nodes) do nids[#nids+1]=id end
        table.sort(nids)
        for _,id in ipairs(nids) do local n=m.nodes[id]
            nentries[id]={role=n.role,label=n.label,online=os.clock()-n.seen<30,data=n.data} end
        return {ids=ids,entries=entries,nodes={ids=nids,entries=nentries}}
    end
    local function node(id,info)
        if type(info)~="table" then return end
        local role=info.role
        if not ({repeater=true,gps=true,info=true,pocket=true})[role] then return end
        local n=0;for _ in pairs(m.nodes) do n=n+1 end
        if not m.nodes[id] and n>=128 then return end
        m.nodes[id]={role=role,label=common.label(info.name),seen=os.clock(),
            data={toast=tostring(info.toast or "?"),pos=type(info.pos)=="table" and info.pos or nil,stats=type(info.stats)=="table" and info.stats or nil}}
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
        if target~="all" and not common.job(target) and not (common.id(target) and devices[target]) then return false end
        if action=="update" then return m.startUpdate(common.id(target) and target or nil) end
        local changed={}
        local always=action=="stop" or action=="reset"
        for id,d in pairs(devices) do
            local e=m.entries[id]
            if matches(id,d,target) and (always or (m.online(id) and not e.data.recovery)) then
                serial=math.max(serial+1,os.epoch("utc"),e and common.number(e.data.ack)+1 or 0)
                m.pending[id]={message={kind="command",action=action,serial=serial},at=os.clock(),job=d.job,
                    ttl=action=="update" and 180 or nil}
                changed[#changed+1]=id
            end
        end
        if #changed==0 then m.notice="Kein erreichbares Ziel / Position unklar";return false end
        save()
        for _,id in ipairs(changed)do local p=m.pending[id];dispatch(id,p.message,p.job) end
        local names={start="Start",stop="Stopp",once="Einmal",reset="Reset"}
        m.notice=(names[action] or action).." an "..#changed.." Turtle"..(#changed>1 and "s" or "").." gesendet ..."
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
        -- Repeater / GPS-Sender melden sich per Rundfunk
        if b.kind=="node" and protocol==common.remoteProtocol and (b.controllerId==0 or b.controllerId==cfg.controllerId) then
            node(id,b.info);return true
        end
        if b.kind=="hello" and type(b.info)=="table" then node(id,b.info) end
        if not pockets[id] then
            if not (cfg.autoPairPockets and protocol==common.remoteProtocol and b.kind=="hello"
                and b.version==1 and (b.role=="pocket" or b.role=="info") and b.controllerId==cfg.controllerId) then return false end
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
            if os.clock()-p.at>=(p.ttl or cfg.network.commandTimeout) then m.pending[id]=nil;expired=expired+1
            else waiting=waiting+1;dispatch(id,p.message,p.job) end
        end
        if expired>0 then m.notice="Keine Antwort von "..expired.." Turtle"..(expired>1 and "s" or "").." (Funk/Chunk?)"
        elseif waiting==0 and m.notice:find("gesendet ...",1,true) then m.notice="Befehl bestaetigt" end
        for id in pairs(pockets)do m.reply(id)end
    end
    function m.waiting()local n=0;for _ in pairs(m.pending)do n=n+1 end;return n end
    -- ===== Update aller Geraete =====
    -- Rueckmeldung: jedes Geraet meldet nach dem Neustart seine Version (Status,
    -- Hello, Beacon). Fertig = Version ist die neue. Die Zentrale wartet nur,
    -- bis alle fertig sind (hoechstens 3 min), statt pauschal.
    local function versionOf(id)
        local e=m.entries[id];if e and e.data and e.data.toast then return tostring(e.data.toast) end
        local n=m.nodes[id];if n and n.data then return n.data.toast end
    end
    local function nodeOnline(id) local n=m.nodes[id];return n and os.clock()-n.seen<30 end
    function m.startUpdate(only,version)
        local run={at=os.clock(),ids={},before={},target=version}
        local count=0
        for id,d in pairs(devices) do
            if only==nil or only==id then
                local e=m.entries[id]
                serial=math.max(serial+1,os.epoch("utc"),e and common.number(e.data.ack)+1 or 0)
                m.pending[id]={message={kind="command",action="update",serial=serial},at=os.clock(),job=d.job,ttl=180}
                dispatch(id,m.pending[id].message,d.job)
                if m.online(id) then run.ids[#run.ids+1]=id;run.before[id]=versionOf(id) end
                count=count+1
            end
        end
        local targets={}
        for pid in pairs(pockets) do targets[pid]=true end
        for nid,nd in pairs(m.nodes) do if nd.role=="repeater" or nd.role=="gps" then targets[nid]=true end end
        for nid in pairs(targets) do
            if only==nil or only==nid then
                serial=serial+1;count=count+1
                send(nid,{kind="update",version=1,controllerId=cfg.controllerId,serial=serial},common.remoteProtocol)
                if nodeOnline(nid) then run.ids[#run.ids+1]=nid;run.before[nid]=versionOf(nid) end
            end
        end
        save()
        if only==nil then
            m.updateRun=run
            m.notice="Update an "..count.." Geraete gesendet ..."
        end
        return true
    end
    -- done, total, fertig?
    function m.updateStatus()
        local r=m.updateRun;if not r then return nil end
        local done=0
        for _,id in ipairs(r.ids) do
            local v=versionOf(id)
            if v and ((r.target and v==r.target) or (not r.target and v~=r.before[id])) then done=done+1 end
        end
        return done,#r.ids
    end
    -- Nachzuegler (waren offline oder neu): aeltere Version als die Zentrale -> einzeln updaten
    m.healAt={}
    function m.heal()
        if m.updateRun then return end
        local function check(id,online)
            local v=versionOf(id)
            if online and v and v~="?" and common.newer(common.version,v) and os.clock()-(m.healAt[id] or -1e9)>300 then
                m.healAt[id]=os.clock();m.startUpdate(id)
            end
        end
        for id in pairs(devices) do check(id,m.online(id)) end
        for id,n in pairs(m.nodes) do if n.role=="repeater" or n.role=="gps" or pockets[id] then check(id,nodeOnline(id)) end end
    end
    return m
end
return M
