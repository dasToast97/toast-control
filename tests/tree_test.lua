package.path="/home/claude/toast/test/?.lua;"..package.path
local Sim=require("sim")
local pass,failc=0,0
local function check(name,cond,info)
    if cond then pass=pass+1;print("  PASS "..name) else failc=failc+1;print("  FAIL "..name.."  "..tostring(info or "")) end
end
local function cfg(tree)
    return [[return {role="turtle",job="tree",controllerId=4,name="Holz Test",
    network={pollInterval=1,staleAfter=15,commandTimeout=10,maxDevices=256},
    tree=]]..tree..[[}]]
end
local function state(S)local s=S.files["/toast_tree_state"];return s and load("return "..s)() or {} end
local function tail(S,n)local t={}for i=math.max(1,#S.log-(n or 6)),#S.log do t[#t+1]=S.log[i]end;return table.concat(t," | ")end
local function count(S,name)local n=0;for i=1,16 do local it=S.inv[i];if it and it.name==name then n=n+it.count end end;return n end
local function trees(S,positions)
    for _,p in ipairs(positions) do S.growTree(p[1],0,p[2]) end
end

print("H1 Holz: 4 Baeume rechts, gewachsen -> faellen + neu pflanzen")
local S=Sim.new({config=cfg([[{trees=4,spacing=2,side="right",interval=30,bonemeal=false,maxHeight=32,keepSaplings=32,fuelTarget=500,radioTimeout=20}]]),
    default=false,actions={{t=2,fn=function(S)Sim.cmd(S,"once",10)end}},
    world=function(S) S.growTree(1,0,1);S.growTree(1,0,4);S.growTree(1,0,7);S.growTree(1,0,10) end})
S.protocol="toast.tree.v1";S.inv[2]={name="minecraft:birch_sapling",count=8}
Sim.run(S,400)
local st=state(S)
check("4 Baeume gefaellt",st.harvested==4,tostring(st.harvested).." "..tail(S))
check("20 Staemme gezaehlt",st.total==20,st.total)
local saplings=0;for _,z in ipairs({1,4,7,10}) do if S.world[S.key(1,0,z)]=="minecraft:birch_sapling" then saplings=saplings+1 end end
check("4 neue Setzlinge gesetzt",saplings==4,saplings)
local logsLeft=0;for k,v in pairs(S.world) do if v=="minecraft:birch_log" then logsLeft=logsLeft+1 end end
check("kein Stamm uebrig",logsLeft==0,logsLeft)
check("zu Hause, Blick nach vorne",S.p.x==0 and S.p.y==0 and S.p.z==0 and S.p.dir==0,S.p.x..","..S.p.y..","..S.p.z.." d"..S.p.dir)
check("Holz in der Ausgabekiste",S.chestNames["minecraft:birch_log"]==true)
check("Setzlinge behalten",count(S,"minecraft:birch_sapling")==4,count(S,"minecraft:birch_sapling"))
check("Status Holz/Runde",S.last and S.last.job=="tree" and S.last.rounds==1 and S.last.cells==4,S.last and S.last.rounds)

print("H2 Beidseitig, leere Plaetze bepflanzen, Knochenmehl")
S=Sim.new({config=cfg([[{trees=3,spacing=1,side="both",interval=30,bonemeal=true,maxHeight=32,keepSaplings=32,fuelTarget=500,radioTimeout=20}]]),
    default=false,actions={{t=2,fn=function(S)Sim.cmd(S,"once",10)end}}})
S.protocol="toast.tree.v1";S.inv[2]={name="minecraft:birch_sapling",count=16};S.inv[3]={name="minecraft:bone_meal",count=64}
Sim.run(S,600)
st=state(S)
check("6 Plaetze bepflanzt + per Knochenmehl gewachsen + gefaellt",st.harvested==6,tostring(st.harvested).." "..tail(S))
local planted=0
for _,x in ipairs({1,-1}) do for _,z in ipairs({1,3,5}) do if S.world[S.key(x,0,z)]=="minecraft:birch_sapling" then planted=planted+1 end end end
check("alle 6 wieder Setzlinge",planted==6,planted)
check("zu Hause",S.p.x==0 and S.p.z==0 and S.p.y==0)

print("H3 Absturz waehrend des Faellens -> Neustart + weiter")
S=Sim.new({config=cfg([[{trees=2,spacing=2,side="right",interval=30,bonemeal=false,maxHeight=32,keepSaplings=32,fuelTarget=500,radioTimeout=20}]]),
    default=false,actions={{t=2,fn=function(S)Sim.cmd(S,"once",10)end}},
    world=function(S) S.growTree(1,0,1);S.growTree(1,0,4) end})
S.protocol="toast.tree.v1";S.inv[2]={name="minecraft:birch_sapling",count=8};S.crashAtMove=5
Sim.run(S,500)
st=state(S)
check("Absturz geloggt",(S.files["/toast/fehler.log"] or ""):find("SIMULIERTER",1,true)~=nil)
check("beide Baeume gefaellt",st.harvested==2,tostring(st.harvested).." "..tail(S))
check("Position stimmt",S.p.x==st.x and S.p.y==st.y and S.p.z==st.z and S.p.x==0 and S.p.z==0,S.p.x..","..S.p.y..","..S.p.z)

print("H4 Fremder Block im Weg -> Fehler, baut ihn NICHT ab")
S=Sim.new({config=cfg([[{trees=3,spacing=2,side="right",interval=30,bonemeal=false,maxHeight=32,keepSaplings=32,fuelTarget=500,radioTimeout=20}]]),
    default=false,actions={{t=2,fn=function(S)Sim.cmd(S,"once",10)end}},
    world=function(S) S.world[S.key(0,0,3)]="minecraft:cobblestone" end})
S.protocol="toast.tree.v1";S.inv[2]={name="minecraft:birch_sapling",count=8}
Sim.run(S,200)
check("Fehler gemeldet",S.last and S.last.fault and S.last.fault:find("blockiert",1,true),S.last and S.last.fault)
check("Block steht noch",S.world[S.key(0,0,3)]=="minecraft:cobblestone")
print(pass.." bestanden, "..failc.." fehlgeschlagen")
