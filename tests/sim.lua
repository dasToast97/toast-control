-- Mini-CraftOS-Simulator fuer Toast-Turtles: Welt, fs, Timer, rednet, Supervisor.
local SRC=arg[1] or "/home/claude/toast/"
local function readReal(p)local f=assert(io.open(p,"rb"));local s=f:read("a");f:close();return s end
local Sim={}
function Sim.new(opts)
    local S={T=0,timers={},nextTimer=1,queue={},files={},world={},inv={},sel=1,log={},sent={},
        p={x=0,y=0,z=0,dir=0},tool=opts.tool~=false,fuel=opts.fuel or 5000,mobs=0,crashAtMove=nil,moves=0,chestBelow=0,coal=opts.coal or 640,
        input=opts.input or {},polling=true,actions=opts.actions or {}}
    -- Dateien
    for _,n in ipairs({"toast.lua"})do S.files["/"..n]=readReal(SRC..n)end
    for _,n in ipairs({"toast_common.lua","mine_turtle.lua","farm_turtle.lua"})do S.files["/toast/"..n]=readReal(SRC..n)end
    S.files["/toast/mine_common.lua"]=readReal(SRC.."test/mine_common.lua")
    S.files["/toast/farm_common.lua"]=readReal(SRC.."test/farm_common.lua")
    S.files["/toast.config.lua"]=opts.config
    -- Welt: true = Stein, sonst Name. Default Stein; Basisblock frei.
    local function key(x,y,z)return x..","..y..","..z end
    S.key=key
    S.world[key(0,0,0)]=false
    S.world[key(0,1,0)]="minecraft:chest"     -- unten Ausgabe
    S.world[key(0,-1,0)]="minecraft:chest"    -- oben Kohle
    if opts.world then opts.world(S) end
    local function block(x,y,z)
        local b=S.world[key(x,y,z)]
        if b==nil then b=opts.default;if b==nil then b="minecraft:stone" end end
        return b or nil
    end
    S.block=block
    local DX,DZ={[0]=0,1,0,-1},{[0]=1,0,-1,0}
    local function front(kind)
        local p=S.p
        if kind=="up" then return p.x,p.y-1,p.z elseif kind=="down" then return p.x,p.y+1,p.z end
        return p.x+DX[p.dir],p.y,p.z+DZ[p.dir]
    end
    local function add(name,n)
        for i=1,16 do local it=S.inv[i];if it and it.name==name and it.count<64 then local k=math.min(n,64-it.count);it.count=it.count+k;n=n-k;if n==0 then return true end end end
        for i=1,16 do if not S.inv[i] then S.inv[i]={name=name,count=math.min(64,n)};n=n-math.min(64,n);if n==0 then return true end end end
        return n==0
    end
    local function inspect(kind)return function()
        local b=block(front(kind));if not b then return false,"No block" end
        local st={};if b=="minecraft:wheat_ripe" then return true,{name="minecraft:wheat",state={age=7}} end
        return true,{name=b,state=st}
    end end
    local function dig(kind)return function()
        local x,y,z=front(kind);local b=block(x,y,z);if not b then return false,"Nothing to dig" end
        if not S.tool then return false,"No tool to dig with" end
        if b=="minecraft:bedrock" then return false,"Unbreakable block detected" end
        if b:find("lava",1,true) or b:find("water",1,true) then return false,"Nothing to dig here" end
        S.world[key(x,y,z)]=false;add(b=="minecraft:stone" and "minecraft:cobblestone" or b,1);return true
    end end
    local function mv(kind)return function()
        if S.fuel<=0 then return false,"Out of fuel" end
        local x,y,z=front(kind)
        local bb=block(x,y,z)
        if bb and not bb:find("lava",1,true) and not bb:find("water",1,true) then return false,"Movement obstructed" end
        if S.mobs>0 and kind=="forward" then S.mobs=S.mobs-1;return false,"Movement obstructed" end
        S.p.x,S.p.y,S.p.z=x,y,z;S.fuel=S.fuel-1;S.moves=S.moves+1
        if S.crashAtMove and S.moves==S.crashAtMove then S.crashAtMove=nil;error("SIMULIERTER SERVERSTOPP",0) end
        return true
    end end
    S.turtle={
        forward=mv("forward"),up=mv("up"),down=mv("down"),
        turnLeft=function()S.p.dir=(S.p.dir+3)%4;return true end,
        turnRight=function()S.p.dir=(S.p.dir+1)%4;return true end,
        inspect=inspect("forward"),inspectUp=inspect("up"),inspectDown=inspect("down"),
        dig=dig("forward"),digUp=dig("up"),digDown=dig("down"),
        attack=function()return false end,attackUp=function()return false end,attackDown=function()return false end,
        getFuelLevel=function()return S.fuel end,getFuelLimit=function()return 20000 end,
        select=function(i)S.sel=i;return true end,
        getItemCount=function(i)i=i or S.sel;return S.inv[i] and S.inv[i].count or 0 end,
        getItemSpace=function(i)i=i or S.sel;return S.inv[i] and 64-S.inv[i].count or 64 end,
        getItemDetail=function(i)i=i or S.sel;local it=S.inv[i];return it and {name=it.name,count=it.count} end,
        dropDown=function(n)local it=S.inv[S.sel];if not it then return false end
            if block(S.p.x,S.p.y+1,S.p.z)~="minecraft:chest" then return false end
            n=math.min(n or it.count,it.count);it.count=it.count-n;S.chestBelow=S.chestBelow+n
            if it.count==0 then S.inv[S.sel]=nil end;return true end,
        dropUp=function(n)local it=S.inv[S.sel];if not it then return false end
            n=math.min(n or it.count,it.count);it.count=it.count-n;S.coal=S.coal+n;if it.count==0 then S.inv[S.sel]=nil end;return true end,
        drop=function()S.inv[S.sel]=nil;return true end,
        suckUp=function(n)n=math.min(n or 64,64,S.coal);if n<=0 then return false end
            if S.inv[S.sel] then return false end;S.inv[S.sel]={name="minecraft:coal",count=n};S.coal=S.coal-n;return true end,
        suck=function()return false end,
        refuel=function(n)local it=S.inv[S.sel];if not it or it.name~="minecraft:coal" then return false end
            n=math.min(n or it.count,it.count);it.count=it.count-n;S.fuel=S.fuel+80*n;if it.count==0 then S.inv[S.sel]=nil end;return true end,
        placeDown=function()return false end,
        equipLeft=function()local it=S.inv[S.sel];if not it or not it.name:find("pickaxe") then return false end
            S.inv[S.sel]=nil;S.tool=true;return true end,
        equipRight=function()return false end,digDownCrop=nil,
    }
    return S
end
-- Serialisierung wie textutils
local function ser(v,ind)
    ind=ind or ""
    if type(v)=="table" then
        local out={"{"}
        for k,x in pairs(v) do
            local kk=type(k)=="string" and k:match("^[%a_][%w_]*$") and k or "["..ser(k).."]"
            out[#out+1]=ind.."  "..kk.." = "..ser(x,ind.."  ")..","
        end
        out[#out+1]=ind.."}";return table.concat(out,"\n")
    elseif type(v)=="string" then return string.format("%q",v)
    elseif type(v)=="number" then if v%1==0 and math.abs(v)<2^53 then return string.format("%d",v) end return tostring(v)
    else return tostring(v) end
end
function Sim.env(S)
    local G={}
    local function fsopen(path,mode)
        if mode=="r" then local d=S.files[path];if not d then return nil end
            return {readAll=function()return d end,close=function()end} end
        local buf=mode=="a" and (S.files[path] or "") or ""
        if mode=="w" then S.files[path]="" end
        return {write=function(s)buf=buf..tostring(s)end,writeLine=function(s)buf=buf..tostring(s).."\n"end,
            close=function()S.files[path]=buf end}
    end
    G.fs={open=fsopen,exists=function(p)return S.files[p]~=nil end,delete=function(p)S.files[p]=nil end,
        move=function(a,b)S.files[b]=S.files[a];S.files[a]=nil end,makeDir=function()end,
        getSize=function(p)return #(S.files[p] or "")end,copy=function(a,b)S.files[b]=S.files[a]end,isDir=function()return false end}
    G.textutils={serialize=function(t)return ser(t)end,unserialize=function(s)local f=load("return "..s,"u","t",{});if not f then return nil end;local ok,v=pcall(f);return ok and v or nil end}
    G.os={clock=function()return S.T end,epoch=function()return 1700000000000+math.floor(S.T*1000)end,
        getComputerID=function()return 7 end,getComputerLabel=function()return nil end,date=function()return "SIM" end,
        startTimer=function(t)local id=S.nextTimer;S.nextTimer=id+1;S.timers[id]=S.T+t;return id end,
        pullEventRaw=function(f)return coroutine.yield(f)end}
    G.os.pullEvent=function(f)local ev=table.pack(coroutine.yield(f));if ev[1]=="terminate" then error("Terminated",0)end;return table.unpack(ev,1,ev.n)end
    G.sleep=function(t)local id=G.os.startTimer(t);repeat local _,p=G.os.pullEvent("timer") until p==id end
    G.turtle=S.turtle;G.pocket=nil
    G.peripheral={find=function(t,f)if t=="modem" then local m={isWireless=function()return true end};if not f or f("back",m) then return m end end end,
        getName=function()return "back"end,getType=function(side)return side=="right" and "modem" or nil end}
    G.rednet={open=function()end,send=function(id,msg,p)S.sent[#S.sent+1]={id=id,msg=msg,p=p};S.last=msg;return true end,
        broadcast=function()end,host=function()end,unhost=function()end,lookup=function()end}
    G.term={clear=function()end,setCursorPos=function()end,getSize=function()return 39,13 end,
        setBackgroundColor=function()end,setTextColor=function()end,write=function()end}
    G.colors=setmetatable({},{__index=function()return 1 end})
    G.keys={q=16,left=203,right=205}
    G.print=function(...)local t={}for i=1,select("#",...)do t[#t+1]=tostring(select(i,...))end;S.log[#S.log+1]=table.concat(t," ")end
    G.write=G.print;G.printError=function(s)S.log[#S.log+1]="ERR "..tostring(s)end
    G.read=function()return table.remove(S.input,1) or "" end
    for _,k in ipairs({"assert","error","pairs","ipairs","pcall","select","setmetatable","getmetatable","tonumber","tostring","type","next","rawget","rawset","load","math","string","table","coroutine"})do G[k]=_G[k]end
    G._G=G;G._ENV=G
    G.load=function(chunk,name,mode,e)return load(chunk,name,mode or "t",e or G)end
    G.loadfile=function(path,mode,env)local d=S.files[path];if not d then return nil,"not found "..path end;return load(d,"@"..path,"t",env or G)end
    G.dofile=function(path)local f=assert(G.loadfile(path,"t",G));return f()end
    -- CC parallel
    G.parallel={waitForAll=function(...)
        local fns={...};local cos,filters={},{}
        for i,f in ipairs(fns)do cos[i]=coroutine.create(f)end
        local ev={n=0}
        while true do
            local alive=0
            for i,co in ipairs(cos)do
                if coroutine.status(co)~="dead" then
                    if filters[i]==nil or filters[i]==ev[1] or ev[1]=="terminate" then
                        local r=table.pack(coroutine.resume(co,table.unpack(ev,1,ev.n)))
                        if not r[1] then error(r[2],0) end
                        filters[i]=r[2]
                    end
                    if coroutine.status(co)~="dead" then alive=alive+1 end
                end
            end
            if alive<#cos and false then end
            local done=true;for _,co in ipairs(cos)do if coroutine.status(co)~="dead" then done=false end end
            if done then return end
            ev=table.pack(coroutine.yield())
        end
    end}
    G.shell={run=function()end}
    return G
end
-- Hauptschleife: fuehrt toast.lua aus, liefert Timer, Polls und geplante Aktionen.
function Sim.run(S,limit,args)
    local G=Sim.env(S)
    local main=coroutine.create(function()
        local f=assert(G.loadfile("/toast.lua","t",G));return f(table.unpack(args or {}))
    end)
    local nextPoll=1
    local ev={n=0};local filter
    while S.T<limit do
        if filter==nil or filter==ev[1] or ev[1]=="terminate" then
            local r=table.pack(coroutine.resume(main,table.unpack(ev,1,ev.n)))
            if not r[1] then S.result="error: "..tostring(r[2]);return S end
            if coroutine.status(main)=="dead" then S.result="ended";return S end
            filter=r[2]
        end
        -- geplante Aktionen
        if #S.queue>0 then ev=table.remove(S.queue,1)
        else
            local best,bt=nil,math.huge
            for id,t in pairs(S.timers)do if t<bt then best,bt=id,t end end
            local nextAct=S.actions[1] and S.actions[1].t or math.huge
            local tgt=math.min(bt,S.polling and nextPoll or math.huge,nextAct)
            if tgt==math.huge then S.result="stuck";return S end
            S.T=math.max(S.T,tgt)
            if S.actions[1] and S.actions[1].t<=S.T then
                local a=table.remove(S.actions,1);a.fn(S)
                ev={n=0,"sim_noop"}
            elseif S.polling and nextPoll<=S.T then
                nextPoll=nextPoll+1
                ev=table.pack("rednet_message",4,{kind="poll"},S.protocol)
            else
                S.timers[best]=nil;ev=table.pack("timer",best)
            end
        end
    end
    S.result="timeout";return S
end
function Sim.cmd(S,action,serial)
    table.insert(S.queue,table.pack("rednet_message",4,{kind="command",action=action,serial=serial},S.protocol))
end
return Sim
