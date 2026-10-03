package.path="/home/claude/toast/test/?.lua;"..package.path
local Sim=require("sim")
local pass,failc=0,0
local function check(name,cond,info)
    if cond then pass=pass+1;print("  PASS "..name) else failc=failc+1;print("  FAIL "..name.."  "..tostring(info or "")) end
end
local function cfg(tree)
    return [[return {role="turtle",job="tree",controllerId=4,name="Holz Test",
    network={pollInterval=1,staleAfter=15,commandTimeout=10,maxDevices=256},tree=]]..tree..[[}]]
end
local function state(S)local s=S.files["/toast_tree_state"];return s and load("return "..s)() or {} end
local function tail(S,n)local t={}for i=math.max(1,#S.log-(n or 6)),#S.log do t[#t+1]=S.log[i]end;return table.concat(t," | ")end
local function count(S,name)local n=0;for i=1,16 do local it=S.inv[i];if it and it.name==name then n=n+it.count end end;return n end
-- Sim-Koordinaten: y positiv = nach unten. Boden-Oberflaeche je Feld: g(x,z) = y des obersten Bodenblocks.
local function landscape(S,trees,sideSign)
    local g={}
    local function ground(x,z)
        local h=1
        if x*sideSign>=4 and x*sideSign<=6 and z>=4 and z<=7 then h=-1 end     -- Huegel 2 hoch
        if x*sideSign==2 and z>=9 and z<=10 then h=2 end                          -- Senke 1 tief
        return h
    end
    for x=-12,12 do for z=-1,16 do
        local h=ground(x,z);g[x..":"..z]=h
        for y=h,8 do S.world[S.key(x,y,z)]="minecraft:dirt" end
    end end
    S.world[S.key(0,1,0)]="minecraft:chest";S.world[S.key(0,0,0)]=false;S.world[S.key(0,-1,0)]="minecraft:chest"
    for _,t in ipairs(trees) do
        local x,z=t[1]*sideSign,t[2]
        local base=g[x..":"..z]-1               -- erster Stamm ueber dem Boden
        for i=0,4 do S.world[S.key(x,base-i,z)]="minecraft:birch_log" end
        for _,d in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
            for i=3,4 do local k=S.key(x+d[1],base-i,z+d[2]);if not S.world[k] then S.world[k]="minecraft:birch_leaves" end end
        end
        S.world[S.key(x,base-5,z)]="minecraft:birch_leaves"
    end
    return g
end
local TREES={{2,3},{5,5},{0,6},{3,9},{2,11},{7,2},{8,10},{1,12}}
local function run(side)
    local sign=side=="left" and -1 or 1
    local S=Sim.new({config=cfg('{length=12,width=9,side="'..side..'",climb=6,maxHeight=32,replant=true,keepSaplings=32,interval=30,fuelTarget=1500,radioTimeout=0}'),
        default=false,actions={{t=2,fn=function(S)Sim.cmd(S,"once",10)end}}})
    S.protocol="toast.tree.v1";S.inv[2]={name="minecraft:birch_sapling",count=16}
    local g=landscape(S,TREES,sign)
    Sim.run(S,4000)
    return S,g,sign
end
for _,side in ipairs({"right","left"}) do
    print("H Holzfaeller im Gelaende ("..side..")")
    local S,g,sign=run(side)
    local st=state(S)
    local logsLeft=0;for k,v in pairs(S.world) do if v=="minecraft:birch_log" then logsLeft=logsLeft+1 end end
    check("Runde fertig",st.rounds==1,tostring(st.rounds).." "..tail(S))
    check("alle 8 Baeume gefaellt",st.harvested==8,st.harvested)
    check("kein Stamm uebrig",logsLeft==0,logsLeft)
    check("40 Staemme gezaehlt",st.total==40,st.total)
    local planted=0
    for _,t in ipairs(TREES) do local x,z=t[1]*sign,t[2];if S.world[S.key(x,g[x..":"..z]-1,z)]=="minecraft:birch_sapling" then planted=planted+1 end end
    check("8 Setzlinge auf dem Boden der Baeume",planted==8,planted)
    local other=0;for n,c in pairs(S.dugNames or {}) do if n~="minecraft:birch_log" and n~="minecraft:birch_leaves" then other=other+c end end
    check("nur Holz/Blaetter abgebaut",other==0,other)
    check("zu Hause, Position stimmt",S.p.x==0 and S.p.y==0 and S.p.z==0 and st.x==0 and st.y==0 and st.z==0,S.p.x..","..S.p.y..","..S.p.z)
    check("Holz abgeliefert",S.chestNames["minecraft:birch_log"]==true)
end

print("H3 Absturz mitten im Faellen -> Neustart, Rest faellen, heim")
local S=Sim.new({config=cfg('{length=6,width=3,side="right",climb=6,maxHeight=32,replant=true,keepSaplings=32,interval=30,fuelTarget=800,radioTimeout=0}'),
    default=false,actions={{t=2,fn=function(S)Sim.cmd(S,"once",10)end}}})
S.protocol="toast.tree.v1";S.inv[2]={name="minecraft:birch_sapling",count=8}
landscape(S,{{2,3}},1)
local mv=S.turtle.up;S.turtle.up=function() local ok,w=mv();if ok and S.p.y==-2 and not S.crashed then S.crashed=true;error("SIMULIERTER SERVERSTOPP",0) end;return ok,w end
Sim.run(S,2000)
local st=state(S)
local logsLeft=0;for k,v in pairs(S.world) do if v=="minecraft:birch_log" then logsLeft=logsLeft+1 end end
check("Absturz passiert",S.crashed==true)
check("kein Stamm uebrig",logsLeft==0,logsLeft)
check("Position stimmt + Basis",S.p.x==0 and S.p.y==0 and S.p.z==0 and st.x==0 and st.z==0,S.p.x..","..S.p.y..","..S.p.z.." "..tail(S))

print("H4 Fremder Bau mitten im Gebiet wird nicht abgebaut (umfahren/ueberklettert)")
S=Sim.new({config=cfg('{length=8,width=4,side="right",climb=6,maxHeight=32,replant=false,keepSaplings=32,interval=30,fuelTarget=800,radioTimeout=0}'),
    default=false,actions={{t=2,fn=function(S)Sim.cmd(S,"once",10)end}}})
S.protocol="toast.tree.v1"
landscape(S,{{1,7}},1)
for x=0,3 do for y=0,-1,-1 do S.world[S.key(x,y,4)]="minecraft:cobblestone" end end   -- Mauer 2 hoch quer
Sim.run(S,2000)
st=state(S)
local wallOk=true;for x=0,3 do for y=0,-1,-1 do if S.world[S.key(x,y,4)]~="minecraft:cobblestone" then wallOk=false end end end
check("Mauer steht noch",wallOk)
check("Baum hinter der Mauer gefaellt",st.harvested==1,st.harvested)
check("zu Hause",S.p.x==0 and S.p.y==0 and S.p.z==0)

print("H5 Fehler an der Basis (keine Ausgabekiste): dreht sich NICHT im Kreis")
S=Sim.new({config=cfg('{length=6,width=3,side="right",climb=6,maxHeight=32,replant=true,keepSaplings=32,interval=30,fuelTarget=800,radioTimeout=0}'),
    default=false,actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end},{t=30,fn=function(S)S.turns0=S.turnCount end},{t=150,fn=function(S)S.turns1=S.turnCount end}}})
S.protocol="toast.tree.v1"
landscape(S,{{2,3}},1)
S.world[S.key(0,1,0)]="minecraft:dirt"      -- Ausgabekiste fehlt
S.turnCount=0
for _,n in ipairs({"turnLeft","turnRight"}) do local f=S.turtle[n];S.turtle[n]=function() S.turnCount=S.turnCount+1;return f() end end
Sim.run(S,160)
check("Fehler gemeldet",S.last and (S.last.fault or ""):find("Ausgabekiste",1,true),S.last and S.last.fault)
check("keine Drehungen im Leerlauf",S.turns1==S.turns0,tostring(S.turns0).." -> "..tostring(S.turns1))
print(pass.." bestanden, "..failc.." fehlgeschlagen")
