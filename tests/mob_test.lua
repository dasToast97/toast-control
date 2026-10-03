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

-- Gelaende: Boden auf Hoehe -1, Huegel, Grube, hohe Mauer (mit Luecke)
local function terrain(S)
    for x=-20,20 do for z=-1,21 do for y=1,4 do S.world[S.key(x,y,z)]="minecraft:dirt" end end end
    S.world[S.key(0,1,0)]="minecraft:chest"
    for x=3,5 do for z=3,5 do S.world[S.key(x,0,z)]="minecraft:stone" end end
    S.world[S.key(4,-1,4)]="minecraft:stone";S.world[S.key(4,-2,4)]="minecraft:stone"
    for x=1,2 do S.world[S.key(x,1,8)]=false;S.world[S.key(x,2,8)]=false end   -- Grube 2 tief
    for z=1,10 do for y=0,-14,-1 do S.world[S.key(7,y,z)]="minecraft:obsidian" end end -- Mauer, zu hoch
end
local function track(S)
    S.minY,S.maxY,S.maxX=0,0,0
    for _,n in ipairs({"forward","up","down"}) do
        local f=S.turtle[n]
        S.turtle[n]=function() local ok,w=f()
            if ok then S.minY=math.min(S.minY,-S.p.y);S.maxY=math.max(S.maxY,-S.p.y);S.maxX=math.max(S.maxX,math.abs(S.p.x)) end
            return ok,w end
    end
end
local PCFG=[[{mode="patrol",attack="front",length=16,width=12,side="right",climb=6,interval=5,fuelTarget=900,radioTimeout=0}]]
print("M3 Waechter im Gelaende: zufaellig, bis Fuel knapp, dann heim + tanken")
S=Sim.new({config=cfg(PCFG),default=false,fuel=500,world=terrain,
    actions={{t=2,fn=function(S)Sim.cmd(S,"once",10)end},{t=4,fn=function(S)S.mobs=2 end}}})
S.protocol="toast.mob.v1";track(S)
Sim.run(S,3000)
st=state(S)
check("eine Tankfuellung patrouilliert",st.rounds==1,tostring(st.rounds).." "..tail(S))
check("mehrere Ziele angefahren",(st.targets or 0)>=5,st.targets)
check("zu Hause, Blick vorne, Position stimmt",S.p.x==0 and S.p.z==0 and S.p.y==0 and S.p.dir==0 and st.x==0 and st.z==0 and st.y==0,S.p.x..","..S.p.y..","..S.p.z)
check("nichts abgebaut",(S.digs or 0)==0,S.digs)
check("ueber den Huegel geklettert",S.maxY>=2,S.maxY)
check("Kletterhoehe nie ueberschritten",S.maxY<=6 and S.minY>=-6,S.minY..".."..S.maxY)
check("nicht nur Rand: kam weit rein",S.maxX>=5,S.maxX)
check("an Basis getankt",S.fuel>=850,S.fuel)

print("M4 Waechter links (gespiegelt), Dauerbetrieb: mehrere Tankrunden")
S=Sim.new({config=cfg(PCFG:gsub('side="right"','side="left"')),default=false,fuel=300,
    world=function(S) for x=-20,20 do for z=0,20 do S.world[S.key(x,1,z)]="minecraft:dirt" end end;S.world[S.key(0,1,0)]="minecraft:chest" end,
    actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end}}})
S.protocol="toast.mob.v1";S.coal=30
local minX=0
do local f=S.turtle.forward;S.turtle.forward=function() local ok,w=f();if ok then minX=math.min(minX,S.p.x);S.maxXr=math.max(S.maxXr or 0,S.p.x) end;return ok,w end end
Sim.run(S,4000)
st=state(S)
check("mehrere Tankrunden",(st.rounds or 0)>=2,st.rounds)
check("nur links gefahren",minX<=-5 and (S.maxXr or 0)==0,minX.." / "..tostring(S.maxXr))

print("M5 Waechter: Absturz unterwegs -> Neustart, Heimweg durchs Gelaende")
S=Sim.new({config=cfg(PCFG),default=false,fuel=500,world=terrain,
    actions={{t=2,fn=function(S)Sim.cmd(S,"once",10)end}}})
S.protocol="toast.mob.v1";S.crashAtMove=60
Sim.run(S,3000)
st=state(S)
check("Absturz geloggt",(S.files["/toast/fehler.log"] or ""):find("SIMULIERTER",1,true)~=nil)
check("Runde danach fertig",st.rounds==1,tostring(st.rounds).." "..tail(S))
check("Position stimmt + Basis",S.p.x==0 and S.p.z==0 and S.p.y==0 and st.x==0 and st.z==0,S.p.x..","..S.p.y..","..S.p.z)
check("nichts abgebaut",(S.digs or 0)==0,S.digs)


print("M6 Waechter auf schmalem Streifen: Graben runter, Huegel hoch")
S=Sim.new({config=cfg([[{mode="patrol",attack="front",length=10,width=1,side="right",climb=4,interval=5,fuelTarget=400,radioTimeout=0}]]),
    default=false,fuel=400,world=function(S)
        for x=-3,3 do for z=-1,12 do for y=1,6 do S.world[S.key(x,y,z)]="minecraft:dirt" end end end
        S.world[S.key(0,1,0)]="minecraft:chest"
        S.world[S.key(0,1,5)]=false;S.world[S.key(0,2,5)]=false          -- Graben 2 tief
        S.world[S.key(0,0,7)]="minecraft:stone";S.world[S.key(0,-1,7)]="minecraft:stone" -- Huegel 2 hoch
    end,actions={{t=2,fn=function(S)Sim.cmd(S,"once",10)end}}})
S.protocol="toast.mob.v1";track(S)
Sim.run(S,2000)
st=state(S)
check("Runde fertig",st.rounds==1,st.rounds)
check("im Graben unten",S.minY<=-2,S.minY)
check("auf dem Huegel",S.maxY>=2,S.maxY)
check("zu Hause",S.p.x==0 and S.p.y==0 and S.p.z==0)
check("nichts abgebaut",(S.digs or 0)==0,S.digs)
print(pass.." bestanden, "..failc.." fehlgeschlagen")
