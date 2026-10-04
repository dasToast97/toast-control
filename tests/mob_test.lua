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

print("M7 Waechter nur nachts: tagsueber an der Basis, nachts unterwegs")
S=Sim.new({config=cfg([[{mode="patrol",attack="front",nightOnly=true,length=8,width=6,side="right",climb=4,interval=5,fuelTarget=3000,radioTimeout=0}]]),
    default=false,fuel=3000,world=function(S) for x=-10,10 do for z=-1,12 do for y=1,3 do S.world[S.key(x,y,z)]="minecraft:dirt" end end end;S.world[S.key(0,1,0)]="minecraft:chest" end,
    actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end},
      {t=280,fn=function(S) S.dayPos={S.p.x,S.p.y,S.p.z};S.dayStatus=S.last and S.last.status;S.dayTargets=state(S).targets end},
      {t=380,fn=function(S) S.lateTargets=state(S).targets end}}})
S.protocol="toast.mob.v1"
S.gameTime=function(T) if T<100 then return 22 elseif T<300 then return 12 else return 1 end end
S.coal=10000000   -- im Sim kosten Bewegungen keine Zeit: viel Kohle
Sim.run(S,400)
check("nachts unterwegs gewesen",(S.dayTargets or 0)>=1,S.dayTargets)
check("tagsueber an der Basis",S.dayPos and S.dayPos[1]==0 and S.dayPos[2]==0 and S.dayPos[3]==0,S.dayPos and table.concat(S.dayPos,","))
check("Status Tagpause",S.dayStatus=="Tagpause",S.dayStatus)
check("naechste Nacht wieder los",(S.lateTargets or 0)>(S.dayTargets or 0),tostring(S.lateTargets).." vs "..tostring(S.dayTargets))
print("M8 Waechter sammelt herumliegende Items ein, bringt sie zur Basis; voll -> heim")
S=Sim.new({config=cfg(PCFG),default=false,fuel=500,world=terrain,
    actions={{t=2,fn=function(S)Sim.cmd(S,"once",10)end}}})
S.protocol="toast.mob.v1"
-- Items auf dem Boden (im Luftblock ueber dem Gras) - Turtle sammelt sie mit suck()
S.ground={}
for x=0,11 do for z=1,16 do if (x+z)%3==0 then S.ground[S.key(x,0,z)]={name="minecraft:bone",count=1} end end end
local total0=0;for _ in pairs(S.ground) do total0=total0+1 end
do
  local DX,DZ={[0]=0,1,0,-1},{[0]=1,0,-1,0}
  local function pick(x,y,z)
    local k=S.key(x,y,z);local it=S.ground[k];if not it then return false end
    for i=1,16 do local sl=S.inv[i];if sl and sl.name==it.name and sl.count<64 then sl.count=sl.count+1;S.ground[k]=nil;return true end end
    for i=1,16 do if not S.inv[i] then S.inv[i]={name=it.name,count=1};S.ground[k]=nil;return true end end
    return false
  end
  S.turtle.suck=function() return pick(S.p.x+DX[S.p.dir],S.p.y,S.p.z+DZ[S.p.dir]) end
  S.turtle.suckDown=function() return pick(S.p.x,S.p.y+1,S.p.z) end
  local su=S.turtle.suckUp
  S.turtle.suckUp=function(n) if S.world[S.key(S.p.x,S.p.y-1,S.p.z)]=="minecraft:chest" then return su(n) end;return pick(S.p.x,S.p.y-1,S.p.z) end
  -- Inventar wird unterwegs voll (z.B. viel Beute)
  local fw=S.turtle.forward;local n=0
  S.turtle.forward=function() local ok,w=fw();if ok then n=n+1;if n==25 then for i=1,15 do if not S.inv[i] then S.inv[i]={name="minecraft:rotten_flesh",count=64} end end;S.filledAt=S.moves end end;return ok,w end
end
Sim.run(S,3000)
st=state(S)
local left=0;for _ in pairs(S.ground) do left=left+1 end
check("Items eingesammelt",left<total0 and (st.looted or 0)>0,(total0-left).."/"..total0)
check("Knochen in der Kiste abgeliefert",S.chestNames["minecraft:bone"]==true)
check("voll -> heim + abgeladen",S.filledAt and S.chestNames["minecraft:rotten_flesh"]==true,tostring(S.filledAt))
check("nichts aus der Kohlekiste geholt ausser Kohle",S.chestNames["minecraft:coal"]~=true)
check("zu Hause",S.p.x==0 and S.p.z==0 and S.p.y==0)

print("M9 Wache ohne Kiste: Inventar voll -> klare Meldung, wehrt weiter ab")
S=Sim.new({config=cfg([[{mode="guard",attack="front",length=12,width=12,side="right",interval=30,fuelTarget=500,radioTimeout=0}]]),
    default=false,actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end},{t=6,fn=function(S)S.enemies=3 end}},
    gear={left="minecraft:diamond_sword",right="computercraft:wireless_modem_advanced"}})
S.protocol="toast.mob.v1";S.world[S.key(0,1,0)]=false
for i=1,16 do S.inv[i]={name="minecraft:dirt",count=64} end
Sim.run(S,30)
check("wehrt trotzdem ab",S.kills==3,S.kills)
check("Meldung Lager voll",S.last and S.last.status=="Lager voll",S.last and S.last.status)

print("M10 Waechter faehrt nie in Lava (Lavasee im Gebiet)")
local function lavaWorld(S)
    terrain(S)
    for x=6,9 do for z=6,10 do S.world[S.key(x,1,z)]="minecraft:lava";S.world[S.key(x,2,z)]="minecraft:lava" end end
end
S=Sim.new({config=cfg(PCFG),default=false,fuel=500,world=lavaWorld,
    actions={{t=2,fn=function(S)Sim.cmd(S,"once",10)end}}})
S.protocol="toast.mob.v1"
do
  local dd=S.turtle.detectDown
  S.turtle.detectDown=function() local b=S.block(S.p.x,S.p.y+1,S.p.z);if b and b:find("lava",1,true) then return false end;return dd() end
  S.inLava=0;S.overLava=0
  for _,n in ipairs({"forward","up","down"}) do
    local f=S.turtle[n]
    S.turtle[n]=function() local ok,w=f();if ok then
        local here=S.world[S.key(S.p.x,S.p.y,S.p.z)];if here and here:find("lava",1,true) then S.inLava=S.inLava+1 end end;return ok,w end
  end
end
Sim.run(S,3000)
st=state(S)
check("Runde fertig",st.rounds==1,tail(S))
check("nie in Lava gefahren",S.inLava==0,S.inLava)
check("trotzdem viel unterwegs",(st.targets or 0)>=5,st.targets)
check("zu Hause",S.p.x==0 and S.p.z==0 and S.p.y==0)

print(pass.." bestanden, "..failc.." fehlgeschlagen")
