package.path="/home/claude/toast/test/?.lua;"..package.path
local Sim=require("sim")
local pass,failc=0,0
local function check(name,cond,info)
    if cond then pass=pass+1;print("  PASS "..name) else failc=failc+1;print("  FAIL "..name.."  "..tostring(info or "")) end
end
-- Eigenes Startprogramm: nur der Live-Funk (TC.live) mit einem Schein-Status
local PROG=[[
local common=dofile("/toast/toast_common.lua")
local R=_G.LIVE_REC
local snap={kind="status",status="A",x=0}
local contact=0
local right=R.gear and "minecraft:diamond_pickaxe" or "modem"
local realType=peripheral.getType
peripheral.getType=function(s) if s=="right" then return right=="modem" and "modem" or nil end;return realType(s) end
local gear=R.gear and {other="right",radio=function() right="modem";R.swaps=R.swaps+1;return true end} or nil
local L
L=common.live({snapshot=function() local t={};for k,v in pairs(snap) do t[k]=v end;t.contactAge=math.floor(os.clock());return t end,
    gear=gear,every=3,contact=function() return contact end,
    transmit=function(s) R.sent[#R.sent+1]={t=os.clock(),status=s.status,window=s.window}
        -- Zentrale antwortet sofort auf ein Funkfenster
        if s.window then R.windows=R.windows+1;local t0=os.clock();R.pendingReply=t0+0.05 end end,
    onWindow=function(ok) R.windowOk[#R.windowOk+1]=ok end})
local function zentrale() while true do if R.pendingReply and os.clock()>=R.pendingReply then contact=os.clock();R.pendingReply=nil end;sleep(0.05) end end
local function work()
    local t0=os.clock()
    while os.clock()-t0<30 do
        local a=os.clock();L.point();local d=os.clock()-a;if d>R.maxWindow then R.maxWindow=d end
        if right=="modem" and R.gear then sleep(0.1);right="minecraft:diamond_pickaxe" end   -- naechster Abbau: Werkzeug zurueck
        if os.clock()>=5.05 and snap.status=="A" then snap.status="B";R.changeAt=os.clock() end
        if os.clock()>=12.02 and snap.x==0 then snap.x=1;R.change2=os.clock() end
        sleep(0.5)
    end
end
parallel.waitForAny(L.loop,work,zentrale)
]]
local function run(gear)
    local S=Sim.new({config=[[return {role="turtle",job="dig",controllerId=4}]]})
    S.files["/toast.lua"]=PROG;S.liveStep=0.2
    S.polling=false
    local R={sent={},gear=gear,swaps=0,windows=0,windowOk={},maxWindow=0}
    local env=Sim.env
    Sim.env=function(S2) local G=env(S2);G.LIVE_REC=R;G._G=G
        G.parallel=G.parallel or {}
        return G end
    Sim.run(S,40);Sim.env=env
    return R,S
end
print("L1 Ohne Chunkloader: Aenderung geht sofort raus, sonst alle 2 s")
local R,S=run(false)
local firstB;for _,m in ipairs(R.sent) do if m.status=="B" then firstB=m.t;break end end
check("Ergebnis",S.result==nil or S.result=="ended",S.result)
check("Statuswechsel nach <= 0,4 s gesendet",firstB and R.changeAt and firstB-R.changeAt<=0.4,firstB and R.changeAt and (firstB-R.changeAt))
local maxGap=0;for i=2,#R.sent do maxGap=math.max(maxGap,R.sent[i].t-R.sent[i-1].t) end
check("Lebenszeichen mindestens alle 2,2 s",maxGap<=2.25,maxGap)
check("nicht dauernd senden (ohne Aenderung ~alle 2 s)",#R.sent<=25,#R.sent)
print(("    %d Nachrichten in 30 s, Reaktion %.2f s"):format(#R.sent,firstB-R.changeAt))
print("L2 Mit Chunkloader (Werkzeug statt Modem): kurze Funkfenster alle ~3 s")
R,S=run(true)
check("Ergebnis",S.result==nil or S.result=="ended",S.result)
check("Funkfenster kommen (mind. 7 in 30 s)",R.windows>=7,R.windows)
check("ein Fenster dauert hoechstens 0,25 s (Zentrale antwortet sofort)",R.maxWindow<=0.25,R.maxWindow)
local allOk=true;for _,ok in ipairs(R.windowOk) do if not ok then allOk=false end end
check("jedes Fenster bekam Antwort",allOk and #R.windowOk>0,#R.windowOk)
firstB=nil;for _,m in ipairs(R.sent) do if m.status=="B" then firstB=m.t;break end end
check("Statuswechsel spaetestens nach ~3,5 s da",firstB and firstB-R.changeAt<=3.6,firstB and (firstB-R.changeAt))
print(("    %d Fenster, laengstes %.2f s, Reaktion %.2f s"):format(R.windows,R.maxWindow,(firstB or 0)-(R.changeAt or 0)))
print("L3 Zentrale: antwortet sofort aufs Funkfenster, schickt offene Befehle gleich, reicht Aenderungen sofort weiter")
do
    local S3=Sim.new({config=""});local G=Sim.env(S3)
    for _,n in ipairs({"toast_common.lua","toast_model.lua"}) do S3.files["/toast/"..n]=io.open("/home/claude/toast/"..n):read("a") end
    G.os.getComputerID=function() return 4 end;G.turtle=nil
    local sent={};G.rednet.send=function(id,msg,p) sent[#sent+1]={id=id,msg=msg,p=p};return true end
    G.rednet.broadcast=function() end
    local common=G.dofile("/toast/toast_common.lua")
    local cfg=common.load({role="controller",controllerId=4})
    local model=G.dofile("/toast/toast_model.lua").new(cfg)
    local P="toast.mine.v1"
    local function status(extra) local b={kind="status",version=2,id=12,status="Abbau",ack=0,controllerId=4};for k,v in pairs(extra or {}) do b[k]=v end;return b end
    check("Status angenommen",model.ingest(12,status(),P))
    -- Pocket koppeln (hello)
    model.remote(30,{kind="hello",role="pocket",version=1,controllerId=4,info={role="pocket",name="P"}},common.remoteProtocol)
    sent={}
    model.ingest(12,status({window=true}),P)
    local poll=false;for _,m in ipairs(sent) do if m.id==12 and m.msg.kind=="poll" then poll=true end end
    check("Funkfenster: sofort Antwort an die Turtle",poll)
    model.command("start",12);sent={}
    S3.T=S3.T+1
    model.ingest(12,status({window=true}),P)
    local cmd=false;for _,m in ipairs(sent) do if m.id==12 and m.msg.kind=="command" and m.msg.action=="start" then cmd=true end end
    check("offener Befehl geht beim naechsten Status sofort raus",cmd)
    sent={};S3.T=S3.T+1
    model.ingest(12,status({status="Rueckkehr"}),P)
    check("Delta an Pocket",model.flush())
    local d;for _,m in ipairs(sent) do if m.id==30 and m.msg.kind=="fleetdelta" then d=m.msg end end
    check("Delta enthaelt Turtle 12 mit neuem Status",d and d.entries[12] and d.entries[12].data.status=="Rueckkehr",d and "da" or "fehlt")
    check("nichts Neues -> kein Delta",not model.flush())
    -- Pocket-Seite: einmischen
    local fleet={ids={12},entries={[12]={job="mining",label="M",online=true,data={status="Abbau"}}}}
    check("Pocket uebernimmt Delta",common.mergeDelta(fleet,d,256) and fleet.entries[12].data.status=="Rueckkehr")
    local d2={entries={[15]={job="farm",label="F",online=true,data={status="Ernte"}}}}
    common.mergeDelta(fleet,d2,256)
    check("neue Turtle per Delta eingereiht",#fleet.ids==2 and fleet.ids[2]==15)
    check("Unsinn wird ignoriert",common.mergeDelta(fleet,{entries={[16]={job="hack",online="ja"}}},256) and fleet.entries[16]==nil)
end
print(pass.." bestanden, "..failc.." fehlgeschlagen")
if failc>0 then os.exit(1) end
