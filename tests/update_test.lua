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
check("Zentrale plant eigenes Update",model.selfUpdateAt~=nil)
local UI=G.dofile("/toast/toast_ui.lua")
local ui=UI.new({getSize=function()return 39,19 end,isColor=function()return true end,setBackgroundColor=function()end,setTextColor=function()end,clear=function()end,setCursorPos=function()end,write=function()end},cfg)
ui.draw(model.fleet(),true,"")
check("Update-Knopf oben",ui.click(9,1)=="update")
check("1x tippen = Nachfrage",ui.action("update")==nil)
check("2x tippen = Update",ui.action("update")=="update")
print(pass.." bestanden, "..failc.." fehlgeschlagen")
