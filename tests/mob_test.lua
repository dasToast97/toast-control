package.path="/home/claude/toast/test/?.lua;"..package.path
local Sim=require("sim")
local pass,failc=0,0
local function check(name,cond,info)
    if cond then pass=pass+1;print("  PASS "..name) else failc=failc+1;print("  FAIL "..name.."  "..tostring(info or "")) end
end
local function cfg(mob)
    return [[return {role="turtle",job="mob",controllerId=4,name="Mob Test",
    network={pollInterval=1,staleAfter=15,commandTimeout=10,maxDevices=256},mob=]]..mob..[[}]]
end
local function state(S)local s=S.files["/toast_mob_state"];return s and load("return "..s)() or {} end
local function tail(S,n)local t={}for i=math.max(1,#S.log-(n or 6)),#S.log do t[#t+1]=S.log[i]end;return table.concat(t," | ")end

print("M1 Mobfarm: Mobs kommen nach und nach, Drops in die Kiste")
local acts={{t=2,fn=function(S)Sim.cmd(S,"start",10)end}}
for i=1,6 do acts[#acts+1]={t=5+i*10,fn=function(S)S.enemies=(S.enemies or 0)+3 end} end
acts[#acts+1]={t=120,fn=function(S)Sim.cmd(S,"stop",11)end}
local S=Sim.new({config=cfg([[{mode="farm",attack="front",length=12,width=12,side="right",interval=30,fuelTarget=500,radioTimeout=0}]]),
    default=false,actions=acts,gear={left="minecraft:diamond_sword",right="computercraft:wireless_modem_advanced"}})
S.protocol="toast.mob.v1";local fuel0=S.fuel
Sim.run(S,160)
local st=state(S)
check("18 Mobs besiegt",S.kills==18,S.kills)
check("Treffer gezaehlt",st.harvested==18,st.harvested)
check("Drops in der Kiste",S.chestNames["minecraft:rotten_flesh"]==true and S.chestBelow==18,S.chestBelow)
check("kein Fuel verbraucht",S.fuel==fuel0,S.fuel)
check("Status Mobs",S.last and S.last.job=="mob" and S.last.mobMode=="farm" and S.last.hits==18,S.last and S.last.hits)
check("nach STOP aus",S.last and S.last.mode=="off",S.last and S.last.mode)

print("M2 Wache 1x: wehrt ab, stoppt nach 8 s Ruhe")
S=Sim.new({config=cfg([[{mode="guard",attack="all",length=12,width=12,side="right",interval=30,fuelTarget=500,radioTimeout=0}]]),
    default=false,actions={{t=2,fn=function(S)S.enemies=4;Sim.cmd(S,"once",10)end}}})
S.protocol="toast.mob.v1"
Sim.run(S,60)
check("4 abgewehrt",S.kills==4,S.kills)
check("danach fertig/aus",S.last and S.last.mode=="off" and state(S).rounds==1,S.last and S.last.mode)

print("M3 Patrouille 5x4: Mob im Weg wird angegriffen, Runde komplett")
S=Sim.new({config=cfg([[{mode="patrol",attack="front",length=5,width=4,side="right",interval=30,fuelTarget=500,radioTimeout=0}]]),
    default=false,actions={{t=2,fn=function(S)Sim.cmd(S,"once",10)end},{t=4,fn=function(S)S.mobs=2 end}}})
S.protocol="toast.mob.v1";local m0=S.moves
Sim.run(S,200)
st=state(S)
check("Runde fertig",st.rounds==1,tostring(st.rounds).." "..tail(S))
check("14 Schritte (Umfang)",S.moves-m0==14,S.moves-m0)
check("zu Hause, Blick vorne",S.p.x==0 and S.p.z==0 and S.p.dir==0,S.p.x..","..S.p.z.." d"..S.p.dir)

print("M4 Patrouille links: Block im Weg -> Fehler, nichts abgebaut")
S=Sim.new({config=cfg([[{mode="patrol",attack="front",length=5,width=3,side="left",interval=30,fuelTarget=500,radioTimeout=0}]]),
    default=false,actions={{t=2,fn=function(S)Sim.cmd(S,"once",10)end}},
    world=function(S) S.world[S.key(-2,0,4)]="minecraft:oak_planks" end})
S.protocol="toast.mob.v1"
Sim.run(S,120)
check("Fehler Weg blockiert",S.last and S.last.fault and S.last.fault:find("blockiert",1,true),S.last and S.last.fault)
check("Block steht noch",S.world[S.key(-2,0,4)]=="minecraft:oak_planks")
check("ist links gelaufen (traf den Block links)",S.last.fault:find("oak_planks",1,true)~=nil and S.p.x==0,S.last.fault)

print("M5 Patrouille: Absturz unterwegs -> Neustart, zurueck, weiter")
S=Sim.new({config=cfg([[{mode="patrol",attack="front",length=4,width=4,side="right",interval=30,fuelTarget=500,radioTimeout=0}]]),
    default=false,actions={{t=2,fn=function(S)Sim.cmd(S,"once",10)end}}})
S.protocol="toast.mob.v1";S.crashAtMove=7
Sim.run(S,200)
st=state(S)
check("Absturz geloggt",(S.files["/toast/fehler.log"] or ""):find("SIMULIERTER",1,true)~=nil)
check("Runde danach fertig",st.rounds==1,tostring(st.rounds).." "..tail(S))
check("Position stimmt + Basis",S.p.x==0 and S.p.z==0 and st.x==0 and st.z==0,S.p.x..","..S.p.z)
print(pass.." bestanden, "..failc.." fehlgeschlagen")
