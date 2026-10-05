package.path="/home/claude/toast/test/?.lua;"..package.path
local Sim=require("sim")
local pass,failc=0,0
local function check(name,cond,info)
    if cond then pass=pass+1;print("  PASS "..name) else failc=failc+1;print("  FAIL "..name.."  "..tostring(info or "")) end
end
local cfg=[[return {role="auto",job="farm",controllerId=4,label="Test",autoDiscover=true,autoPairPockets=true,
    devices={},pocketIds={},display={monitor="auto",textScale=0.5,pageSize=0},
    network={pollInterval=1,staleAfter=15,commandTimeout=10,maxDevices=256},
    farm={width=3,length=3,crop="wheat",interval=5,seedReserve=0,radioTimeout=10,water={}},
    mine={length=4,height=2,tunnels=2,gap=1,fuelTarget=100,radioTimeout=10,freeSlots=2,digRetries=16,protectedBlocks={}}}]]
print("Farm: Saatgut aus der Ernte behalten (seedReserve=0 = auto), keine Saatgutkiste")
local S=Sim.new({config=cfg,default=false,actions={{t=2,fn=function(S)Sim.cmd(S,"once",10)end}},
    world=function(S)for x=0,2 do for z=1,3 do S.world[S.key(x,1,z)]="minecraft:wheat_ripe" end end end})
S.seedDrops=3
S.inv[1]={name="minecraft:wheat_seeds",count=1}     -- nur 1 Saatkorn zum Start
S.protocol="toast.farm.v2";Sim.run(S,300)
local planted=0
for x=0,2 do for z=1,3 do if S.world[S.key(x,1,z)]=="minecraft:planted" then planted=planted+1 end end end
local seeds=0;for i=1,16 do local it=S.inv[i];if it and it.name=="minecraft:wheat_seeds" then seeds=seeds+it.count end end
check("alle 9 Stellen neu bepflanzt",planted==9,planted)
check("Saatgut behalten (16 = Mindestreserve)",seeds==16,seeds)
check("Weizen abgeliefert",S.chestNames["minecraft:wheat"]==true)
check("ueberschuessiges Saatgut abgeliefert",S.chestNames["minecraft:wheat_seeds"]==true)
check("kein Fehler",not (S.last and S.last.fault),S.last and S.last.fault)
-- Ertrag: 9 Weizen + je 2 uebrige Samen (3 fallen raus, 1 wird gepflanzt) = 27
check("Ertrag zaehlt Weizen + uebrige Samen (27)",S.last and S.last.total==27,S.last and S.last.total)
check("davon Samen 18",S.last and S.last.seedsGained==18,S.last and S.last.seedsGained)
check("Geerntet 9 Pflanzen",S.last and S.last.harvested==9,S.last and S.last.harvested)
print("Farm: angefangene Runde (gespeichert bei Feld 11) -> START macht dort weiter")
do
    local cfg2=cfg:gsub("width=3,length=3","width=4,length=6")
    local S=Sim.new({config=cfg2,default=false,actions={{t=2,fn=function(S)Sim.cmd(S,"once",10)end}},
        world=function(S)for x=0,3 do for z=1,6 do S.world[S.key(x,1,z)]="minecraft:wheat_ripe" end end end})
    S.seedDrops=1
    S.inv[1]={name="minecraft:wheat_seeds",count=40}
    S.protocol="toast.farm.v2"
    S.files["/toast_farm_state"]=[[{x=0,z=0,dir=0,total=5,harvested=10,rounds=3,scanAt=11,roundYield=10,roundPlants=10,controller=4,layout="4:6:wheat"}]]
    local first
    local dd=S.turtle.digDown
    S.turtle.digDown=function(...) if not first then first={x=S.p.x,z=S.p.z} end;return dd(...) end
    Sim.run(S,120)
    -- Reihenfolge: Reihe 1 x0..3, Reihe 2 x3..0, Reihe 3 x0..3 -> Feld 11 = Reihe 3, x=2
    check("erste Ernte bei Feld 11 (Reihe 3, x=2)",first and first.z==3 and first.x==2,first and (first.x..","..first.z))
    local left=0;for x=0,3 do for z=1,6 do if S.world[S.key(x,1,z)]=="minecraft:wheat_ripe" then left=left+1 end end end
    check("Felder 1-10 nicht nochmal abgefahren (stehen noch)",left==10,left)
    check("Runde zu Ende gezaehlt (4 Runden), Zaehler weiter",S.last and S.last.rounds==4 and S.last.harvested==24,S.last and (tostring(S.last.rounds).." "..tostring(S.last.harvested)))
    local stf=load("return "..S.files["/toast_farm_state"])()
    check("nach Rundenende kein Fortsetzpunkt mehr",stf.scanAt==nil,stf.scanAt)
end
print(pass.." bestanden, "..failc.." fehlgeschlagen")
