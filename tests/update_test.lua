package.path="/home/claude/toast/test/?.lua;"..package.path
local Sim=require("sim")
local pass,failc=0,0
local function check(name,cond,info)
    if cond then pass=pass+1;print("  PASS "..name) else failc=failc+1;print("  FAIL "..name.."  "..tostring(info or "")) end
end
local function tail(S,n)local t={}for i=math.max(1,#S.log-(n or 8)),#S.log do t[#t+1]=S.log[i]end;return table.concat(t," | ")end
local SRC=io.open("/home/claude/toast/toast_install.lua"):read("a")
local CFG=[[return {role="turtle",job="mining",controllerId=4,name="Mine U",
  network={pollInterval=1,staleAfter=15,commandTimeout=10,maxDevices=256},
  mine={length=12,height=3,tunnels=2,gap=1,side="right",fuelTarget=200,radioTimeout=10,freeSlots=2,digRetries=16,protectedBlocks={}}}]]
print("U1 Update-Knopf waehrend die Mine arbeitet -> installiert, macht weiter")
local S=Sim.new({config=CFG,actions={
    {t=2,fn=function(S)Sim.cmd(S,"start",10)end},
    {t=4,fn=function(S)S.stepsBefore=S.moves;table.insert(S.queue,table.pack("rednet_message",4,{kind="command",action="update",serial=11},S.protocol)) end}}})
S.protocol="toast.mine.v1"
S.files["/startup.lua"]='shell.run("/toast.lua")\n'
S.files["/meine_notiz.txt"]="alt"
S.httpCalls=0
local orig=Sim.env
Sim.env=function(S2) local G=orig(S2);G.http={get=function(url) S2.httpCalls=S2.httpCalls+1;S2.url=url;return {readAll=function()return SRC end,close=function()end} end}
    G.term.isColor=function()return true end;G.peripheral.find=G.peripheral.find;return G end
Sim.run(S,800)
Sim.env=orig
local st=load("return "..S.files["/toast_mining_state"])()
local cfg=load(S.files["/toast.config.lua"])()
local log=table.concat(S.log," | ")
check("Download von GitHub",S.httpCalls==1 and S.url:find("raw.githubusercontent.com/dasToast97/toast%-control/main/install.lua"),S.url)
check("installiert + neu gestartet",log:find("Update fertig",1,true)~=nil,tail(S))
check("Config behalten",cfg.name=="Mine U" and cfg.mine.length==12)
check("Autostart behalten",S.files["/startup.lua"]=='shell.run("/toast.lua")\n')
check("Mine nach Update fertig",st.next and st.next>24 and S.last and S.last.status=="Fertig",tostring(st.next).." "..tail(S))
check("Position stimmt",S.p.x==st.x and S.p.y==st.y and S.p.z==st.z and S.p.x==0 and S.p.z==0,S.p.x..","..S.p.z)
check("hat schon vor dem Update gearbeitet",(S.stepsBefore or 0)>0,S.stepsBefore)

print("U2 Zentrale: Update-Befehl an Turtles + Pockets, Zentrale danach selbst")
S=Sim.new({config=""});local G=Sim.env(S)
for _,n in ipairs({"toast_common.lua","toast_model.lua","toast_ui.lua"})do S.files["/toast/"..n]=io.open("/home/claude/toast/"..n):read("a")end
G.os.getComputerID=function()return 4 end;G.turtle=nil
local cfg=G.dofile("/toast/toast_common.lua").load({role="controller",controllerId=4})
local model=G.dofile("/toast/toast_model.lua").new(cfg)
model.ingest(12,{kind="status",version=2,id=12,status="Abbau",ack=0,total=5,mode="auto"},"toast.mine.v1")
model.ingest(5,{kind="status",version=2,id=5,status="Bereit",ack=0,total=9,mode="off"},"toast.farm.v2")
model.remote(30,{kind="hello",role="pocket",version=1,controllerId=4},"toast.control.remote.v1")
S.sent={}
check("Befehl angenommen",model.command("update","farm"))
local toTurtle,toPocket=0,0
for _,m in ipairs(S.sent) do
  if m.msg.kind=="command" and m.msg.action=="update" then toTurtle=toTurtle+1 end
  if m.msg.kind=="update" and m.id==30 then toPocket=toPocket+1 end
end
check("an beide Turtles (Ziel immer alle)",toTurtle==2,toTurtle)
check("an das Pocket",toPocket==1,toPocket)
check("Zentrale verfolgt Update-Lauf",model.updateRun~=nil)
local UI=G.dofile("/toast/toast_ui.lua")
local ui=UI.new({getSize=function()return 39,19 end,isColor=function()return true end,setBackgroundColor=function()end,setTextColor=function()end,clear=function()end,setCursorPos=function()end,write=function()end},cfg)
ui.draw(model.fleet(),true,"")
check("Update-Knopf oben",ui.click(9,1)=="update")
check("1x tippen = Nachfrage",ui.action("update")==nil)
check("2x tippen = Update",ui.action("update")=="update")

print("U3 Netzgeraete: Repeater meldet sich, bekommt Update")
model.remote(40,{kind="node",version=1,controllerId=0,info={role="repeater",name="Turm",toast="3.0",pos={x=1,y=2,z=3},stats={repeated=5}}},"toast.control.remote.v1")
model.remote(41,{kind="node",version=1,controllerId=99,info={role="gps",name="fremd"}},"toast.control.remote.v1")
local f=model.fleet()
check("Repeater in der Netz-Liste",f.nodes and f.nodes.entries[40] and f.nodes.entries[40].role=="repeater" and f.nodes.entries[40].data.pos.x==1)
check("fremde Zentrale ignoriert",f.nodes.entries[41]==nil)
model.updateRun=nil;S.sent={}
model.command("update","all")
local toRep=0;for _,m in ipairs(S.sent) do if m.id==40 and m.msg.kind=="update" then toRep=toRep+1 end end
check("Update an Repeater",toRep==1,toRep)

print("U3b Rueckmeldung: fertig, sobald alle die neue Version melden")
model.updateRun.target="9.9"
local d0,t0=model.updateStatus()
check("Lauf zaehlt Turtles + Repeater",t0==3 and d0==0,tostring(d0).."/"..tostring(t0))
model.ingest(12,{kind="status",version=2,id=12,status="Abbau",ack=0,total=5,mode="auto",toast="9.9"},"toast.mine.v1")
model.ingest(5,{kind="status",version=2,id=5,status="Bereit",ack=0,total=9,mode="off",toast="9.9"},"toast.farm.v2")
local d1,t1=model.updateStatus()
check("2 von 3 fertig",d1==2 and t1==3,tostring(d1).."/"..tostring(t1))
model.remote(40,{kind="node",version=1,controllerId=0,info={role="repeater",name="Turm",toast="9.9"}},"toast.control.remote.v1")
local d2,t2=model.updateStatus()
check("alle fertig -> kein Warten",d2==3 and t2==3,tostring(d2).."/"..tostring(t2))
model.updateRun=nil
model.ingest(5,{kind="status",version=2,id=5,status="Bereit",ack=0,total=9,mode="off",toast="1.0"},"toast.farm.v2")
S.sent={};model.heal()
local healed=0;for _,m in ipairs(S.sent) do if m.id==5 and m.msg.action=="update" then healed=healed+1 end end
check("Nachzuegler mit alter Version wird nachgeholt",healed==1,healed)

print("U4 Repeater-Programm: Meldung an Zentrale + Update per Funk")
S=Sim.new({config=[[return {role="repeater",name="Turm",gps={host=true,set=true,x=5,y=80,z=9,auto=false}}]]})
S.files["/toast/repeater.lua"]=io.open("/home/claude/toast/repeater.lua"):read("a")
S.files["/startup.lua"]='shell.run("/toast.lua")\n'
S.polling=false
local orig2=Sim.env
Sim.env=function(S2) local G=orig2(S2);G.turtle=nil;G.os.getComputerID=function()return 40 end
    G.term.isColor=function()return true end;G.os.pullEventRaw=G.os.pullEvent
    G.http={get=function() S2.dl=(S2.dl or 0)+1;return {readAll=function()return SRC end,close=function()end} end}
    G.rednet.broadcast=function(msg,p) S2.beacons=(S2.beacons or 0)+1;S2.lastBeacon=msg end
    G.peripheral.getNames=function()return {"top"} end
    G.peripheral.getType=function(n)return n=="top" and "modem" or nil end
    G.peripheral.find=function(t,fl) if t=="modem" then local m={isWireless=function()return true end,_side="top"};if not fl or fl("top",m) then return m end end end
    G.peripheral.wrap=function(n) if n=="top" then return {isWireless=function()return true end,open=function()end,close=function()end,isOpen=function()return false end,transmit=function()end} end end
    return G end
S.actions={{t=25,fn=function(S) table.insert(S.queue,table.pack("rednet_message",4,{kind="update",version=1,controllerId=4,serial=5},"toast.control.remote.v1")) end}}
Sim.run(S,60)
Sim.env=orig2
local rlog=table.concat(S.log," | ")
check("meldet sich (Beacon)",(S.beacons or 0)>=1 and S.lastBeacon.info.role=="repeater" and S.lastBeacon.info.pos.x==5,S.beacons)
check("Update geladen + neu gestartet",S.dl==1 and rlog:find("Update fertig",1,true)~=nil,tostring(S.dl).." "..rlog:sub(-300))
check("bleibt Repeater",load(S.files["/toast.config.lua"])().role=="repeater")
print("U9 GitHub liefert noch die alte Datei -> nicht installieren")
do
  local S9=Sim.new({config=""});local G9=Sim.env(S9);G9.turtle=nil
  S9.files["/toast/toast_common.lua"]=io.open("/home/claude/toast/toast_common.lua"):read("a")
  local gets=0
  G9.http={get=function() gets=gets+1;local body="-- TOAST CONTROL 3.4.1 alt\n"..string.rep("-- x\n",400)
    return {readAll=function() return body end,close=function() end} end}
  G9.sleep=function() end
  local c9=G9.dofile("/toast/toast_common.lua")
  local ok,why=c9.selfUpdate(nil,"9.9")
  check("alte Datei abgelehnt",ok==false and tostring(why):find("3.4.1",1,true)~=nil,why)
  check("3x versucht",gets==3,gets)
end
print(pass.." bestanden, "..failc.." fehlgeschlagen")
