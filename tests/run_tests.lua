package.path="/home/claude/toast/test/?.lua;"..package.path
local Sim=require("sim")
local pass,failc=0,0
local function check(name,cond,info)
    if cond then pass=pass+1;print("  PASS "..name) else failc=failc+1;print("  FAIL "..name.."  "..tostring(info or "")) end
end
local function mineConfig(extra)
    return [[return {role="auto",job="mining",controllerId=4,label="Test",autoDiscover=true,autoPairPockets=true,
    devices={},pocketIds={},display={monitor="auto",textScale=0.5,pageSize=0},
    network={pollInterval=1,staleAfter=15,commandTimeout=10,maxDevices=256},
    ]]..(extra or "")..[[
    farm={width=3,length=3,crop="wheat",interval=5,seedReserve=16,radioTimeout=10,water={}},
    mine={length=4,height=2,tunnels=2,gap=1,fuelTarget=100,radioTimeout=10,freeSlots=2,digRetries=16,
      protectedBlocks={}}}]]
end
local function state(S,file)
    local s=S.files[file or "/toast_mining_state"];return s and load("return "..s)() or {}
end
local function tail(S,n)local t={}for i=math.max(1,#S.log-(n or 6)),#S.log do t[#t+1]=S.log[i]end;return table.concat(t," | ")end

print("T1 Mining normal")
local S=Sim.new({config=mineConfig(),actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end}}})
S.protocol="toast.mine.v1";Sim.run(S,400)
local st=state(S)
check("alle Gaenge fertig",st.next==9,st.next)
check("zu Hause",S.p.x==0 and S.p.y==0 and S.p.z==0,S.p.x..","..S.p.y..","..S.p.z)
check("Beute abgeliefert",S.chestBelow>0,S.chestBelow)
check("Status Fertig",S.last and S.last.status=="Fertig",S.last and S.last.status)

print("T2 Absturz mitten in der Bewegung -> Auto-Neustart + Fortsetzen")
S=Sim.new({config=mineConfig(),actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end}}})
S.protocol="toast.mine.v1";S.crashAtMove=9;Sim.run(S,400)
st=state(S)
check("Absturz geloggt",(S.files["/toast/fehler.log"] or ""):find("SIMULIERTER",1,true)~=nil)
check("nach Neustart fertig",st.next==9,st.next.." "..tail(S))
check("Position stimmt mit Welt",S.p.x==st.x and S.p.y==st.y and S.p.z==st.z,S.p.x..","..S.p.z.." vs "..tostring(st.x)..","..tostring(st.z))
check("kein Recovery-Stopp",not (S.last and S.last.recovery))

print("T3 Mob blockiert kurz")
S=Sim.new({config=mineConfig(),actions={{t=2,fn=function(S)Sim.cmd(S,"start",10);S.mobs=3 end}}})
S.protocol="toast.mine.v1";Sim.run(S,400);st=state(S)
check("trotz Mob fertig",st.next==9,st.next)
check("kein Fehler",S.last and not S.last.fault,S.last and S.last.fault)

print("T4 Weg lange blockiert -> Fehler -> automatischer neuer Versuch")
S=Sim.new({config=mineConfig(),actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end},
    {t=4,fn=function(S)S.mobs=20 end}}})
S.protocol="toast.mine.v1";
local sawFault=false
local orig=S.turtle.forward
S.turtle.forward=function()local r,w=orig();return r,w end
S.actions[#S.actions+1]={t=40,fn=function(S)sawFault=S.last and S.last.fault~=nil end}
Sim.run(S,600);st=state(S)
check("Fehler wurde gemeldet",sawFault)
check("nach Retry fertig",st.next==9,st.next.." "..tostring(S.last and S.last.status))

print("T5 Lava + Wasser + Kiste im Weg -> wird durchfahren/abgebaut")
S=Sim.new({config=mineConfig(),world=function(S)S.world[S.key(0,0,3)]="minecraft:lava";S.world[S.key(0,-1,2)]="minecraft:water"
    S.world[S.key(2,0,2)]="minecraft:chest" end,actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end}}})
S.protocol="toast.mine.v1";Sim.run(S,400);st=state(S)
check("trotz Lava/Wasser/Kiste fertig",st.next==9 and not (S.last and S.last.fault),st.next.." "..tostring(S.last and S.last.fault))
check("Kiste abgebaut",S.world[S.key(2,0,2)]==false)

print("T5b Bedrock -> kein Auto-Retry, RESET loescht Fehler")
S=Sim.new({config=mineConfig(),world=function(S)S.world[S.key(0,0,3)]="minecraft:bedrock" end,
    actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end}}})
S.protocol="toast.mine.v1"
local bedStatus,afterReset
S.actions[#S.actions+1]={t=80,fn=function(S)bedStatus=S.last and S.last.fault end}
S.actions[#S.actions+1]={t=81,fn=function(S)Sim.cmd(S,"reset",11)end}
S.actions[#S.actions+1]={t=90,fn=function(S)afterReset=S.last end}
Sim.run(S,95);st=state(S)
check("Bedrock-Fehler bleibt (kein Retry)",bedStatus and bedStatus:find("bedrock",1,true)~=nil,bedStatus)
check("RESET: Fehler weg + Bereit",afterReset and afterReset.fault==nil and afterReset.status=="Bereit",afterReset and afterReset.status)
check("RESET: zu Hause",S.p.x==0 and S.p.z==0)

print("T5c Andere Turtle im Weg wird nicht abgebaut")
S=Sim.new({config=mineConfig(),world=function(S)S.world[S.key(0,0,2)]="computercraft:turtle_normal" end,
    actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end}}})
S.protocol="toast.mine.v1"
local tStatus;S.actions[#S.actions+1]={t=60,fn=function(S)tStatus=S.last and S.last.fault end}
Sim.run(S,61)
check("Turtle geschuetzt",S.world[S.key(0,0,2)]=="computercraft:turtle_normal" and tStatus and tStatus:find("Geschuetzt",1,true),tStatus)

print("T5d Keine Spitzhacke -> klare Meldung; Spitzhacke ins Inventar -> legt sie selbst an")
S=Sim.new({config=mineConfig(),tool=false,actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end}}})
S.protocol="toast.mine.v1"
local noTool;S.actions[#S.actions+1]={t=20,fn=function(S)noTool=S.last and S.last.fault end}
S.actions[#S.actions+1]={t=21,fn=function(S)S.inv[5]={name="minecraft:diamond_pickaxe",count=1} end}
Sim.run(S,600);st=state(S)
check("Meldung Keine Spitzhacke",noTool and noTool:find("Keine Spitzhacke",1,true),noTool)
check("nach Einlegen automatisch fertig",st.next==9 and S.tool,st.next)
check("Spitzhacke nicht in Kiste abgeladen",S.tool)

print("T5e Spitzhacke liegt beim Start im Inventar -> wird angelegt")
S=Sim.new({config=mineConfig(),tool=false,actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end}}})
S.inv[1]={name="minecraft:diamond_pickaxe",count=1};S.protocol="toast.mine.v1";Sim.run(S,400);st=state(S)
check("fertig ohne Fehler",st.next==9 and S.tool,st.next)

print("T6 Funkverlust -> Stopp, bei Kontakt automatisch weiter")
S=Sim.new({config=mineConfig():gsub("length=4,height=2","length=40,height=2"),actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end},
    {t=5,fn=function(S)S.polling=false end},{t=60,fn=function(S)S.polling=true end}}})
S.protocol="toast.mine.v1"
local lost
S.actions[#S.actions+1]={t=30,fn=function(S)lost=S.last and S.last.fault end}
table.sort(S.actions,function(a,b)return a.t<b.t end)
Sim.run(S,600);st=state(S)
check("Funkverlust erkannt",lost=="Funkverbindung verloren",lost)
check("danach fertig",st.next==81,st.next)

print("T6b radioTimeout=0 -> arbeitet ohne Zentrale weiter")
S=Sim.new({config=mineConfig():gsub("radioTimeout=10,freeSlots","radioTimeout=0,freeSlots"),actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end},
    {t=3,fn=function(S)S.polling=false end}}})
S.protocol="toast.mine.v1";Sim.run(S,400);st=state(S)
check("fertig ohne Kontakt",st.next==9 and not (S.last and S.last.fault),st.next.." "..tostring(S.last and S.last.fault))

print("T7 Halb geschriebene .tmp-Datei blockiert den Start nicht")
S=Sim.new({config=mineConfig(),actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end}}})
S.protocol="toast.mine.v1"
S.files["/toast_mining_state"]='{x=0,y=0,z=0,dir=0,next=3,total=5,harvested=5,commandSerial=1,layout="strip:4:2:2:1",accessHigh=0}'
S.files["/toast_mining_state.tmp"]='{x=0,y=0,z=0,di'
Sim.run(S,400);st=state(S)
check("Start ok + fortgesetzt ab Zelle 3",st.next==9 and S.result~="ended",st.next.." "..S.result.." "..tail(S))

print("T8 STOP setzt kein Auto-Fortsetzen nach Neustart")
S=Sim.new({config=mineConfig(),actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end},{t=6,fn=function(S)Sim.cmd(S,"stop",11)end}}})
S.protocol="toast.mine.v1";Sim.run(S,60);st=state(S)
check("lastMode geloescht",st.lastMode==nil,st.lastMode)

print("T9 Farm: Runde + Absturz + Fortsetzen")
local farmCfg=mineConfig():gsub('job="mining"','job="farm"')
S=Sim.new({config=farmCfg,default=false,actions={{t=2,fn=function(S)Sim.cmd(S,"once",10)end}},
    world=function(S)for x=0,2 do for z=1,3 do S.world[S.key(x,1,z)]="minecraft:wheat_ripe" end end end})
S.inv[1]={name="minecraft:wheat_seeds",count=64}
S.protocol="toast.farm.v2";S.crashAtMove=4
Sim.run(S,300);st=state(S,"/toast_farm_state")
check("Runde abgeschlossen",st.rounds==1,st.rounds.." "..tail(S))
check("Farm zu Hause + Position stimmt",S.p.x==0 and S.p.z==0 and st.x==0 and st.z==0)
check("Absturz geloggt",(S.files["/toast/fehler.log"] or ""):find("SIMULIERTER",1,true)~=nil)

print(("\n%d bestanden, %d fehlgeschlagen"):format(pass,failc))
os.exit(failc==0 and 0 or 1)
