package.path="/home/claude/toast/test/?.lua;"..package.path
local Sim=require("sim")
local pass,failc=0,0
local function check(name,cond,info)
    if cond then pass=pass+1;print("  PASS "..name) else failc=failc+1;print("  FAIL "..name.."  "..tostring(info or "")) end
end
local function cfg(extra)
    return [[return {role="auto",job="mining",controllerId=4,label="Test",autoDiscover=true,autoPairPockets=true,
    devices={},pocketIds={},display={monitor="auto",textScale=0.5,pageSize=0},
    network={pollInterval=1,staleAfter=15,commandTimeout=10,maxDevices=256},
    farm={width=3,length=3,crop="wheat",interval=5,seedReserve=16,radioTimeout=10,water={}},
    mine={length=20,height=3,tunnels=1,gap=1,fuelTarget=200,radioTimeout=10,freeSlots=2,digRetries=16,protectedBlocks={},]]..extra..[[}}]]
end
local function state(S)local s=S.files["/toast_mining_state"];return s and load("return "..s)() or {} end
local function fill(S) for i=1,16 do if not S.inv[i] then S.inv[i]={name="minecraft:dirt",count=1} end end
    for i=16,1,-1 do if S.inv[i] and S.inv[i].name=="minecraft:dirt" then S.inv[i]=nil;break end end end
print("K1 Kisten unterwegs + Fackeln alle 5")
local leftBase=nil
local S=Sim.new({config=cfg("placeChests=true,torches=5,useCoal=false"),actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end},
}})
S.protocol="toast.mine.v1"
S.inv[2]={name="minecraft:chest",count=3};S.inv[3]={name="minecraft:torch",count=16}
-- Heimkehr nach t=40 erkennen
local mv=S.turtle.forward
S.turtle.forward=function() local ok,w=mv()
    if ok and not S.watch and S.p.z==8 then fill(S);S.watch=true end
    if S.watch and S.p.z==0 and S.p.x==0 and S.p.y==0 then S.homeDuring=(S.homeDuring or 0)+1 end;return ok,w end
Sim.run(S,600)
local st=state(S)
check("Mine fertig",st.next and st.next>20,st.next)
local chests,spot=0
for k,v in pairs(S.world) do local x,y,z=k:match("(-?%d+),(-?%d+),(-?%d+)");if v=="minecraft:chest" and tonumber(z)>0 then chests=chests+1;spot=k end end
check("1 Kiste im Boden gesetzt",chests==1 and spot and spot:match(",1,"),tostring(chests).." "..tostring(spot))
check("Kiste unterwegs befuellt",spot and (S.dropsAt[spot] or 0)>=13,spot and S.dropsAt[spot])
check("nicht heimgefahren zum Abladen",(S.homeDuring or 0)<=1,S.homeDuring)
check("Status zaehlt Kiste",S.last and S.last.chestsPlaced==1 and S.last.chestsLeft==2,S.last and S.last.chestsPlaced)
local torches=0;for _,z in ipairs({5,10,15,20}) do if S.world[S.key(0,0,z)]=="minecraft:torch" then torches=torches+1 end end
check("4 Fackeln auf dem Boden (z=5,10,15,20)",torches==4,torches)
check("Fackeln/Kisten nicht in Basiskiste",not S.chestNames["minecraft:torch"] and S.dropsAt[S.key(0,1,0)] and true)
check("Status Fackeln",S.last and S.last.torchesPlaced==4 and S.last.torchesLeft==12,S.last and S.last.torchesPlaced)

print("K1b Kisten-Position gemerkt: Datei + Status (mit Koordinaten aus der Basis)")
S=Sim.new({config=cfg("placeChests=true,torches=0,useCoal=false").."",actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end}}})
S.files["/toast.config.lua"]=S.files["/toast.config.lua"]:gsub("^return {","return {base={set=true,x=100,y=64,z=-20,facing=\"north\"},")
S.protocol="toast.mine.v1"
S.inv[2]={name="minecraft:chest",count=3}
local mv2=S.turtle.forward
S.turtle.forward=function() local ok,w=mv2()
    if ok and not S.watch and S.p.z==8 then fill(S);S.watch=true end;return ok,w end
Sim.run(S,600)
local file=S.files["/toast_kisten.txt"] or ""
local msg;for _,m in ipairs(S.sent) do if type(m.msg)=="table" and m.msg.chestList and #m.msg.chestList>0 then msg=m.msg end end
local k=msg and msg.chestList[1]
check("Datei /toast_kisten.txt",file:find("Kiste 1:",1,true) and file:find("X 100",1,true) and file:find("Y 63",1,true),file)
check("Status: Kiste 1 mit Weltkoordinaten",k and k.pos and k.pos.x==100 and k.pos.y==63 and k.pos.z==-28,k and k.pos and (k.pos.x..","..k.pos.y..","..k.pos.z))
check("Status: relativ 8 vor, 1 tief",k and k.rel and k.rel.fwd==8 and k.rel.up==-1,k and k.rel and (k.rel.fwd..","..k.rel.up))
do
  local G=Sim.env(S)
  for _,n in ipairs({"toast_ui.lua"})do S.files["/toast/"..n]=io.open("/home/claude/toast/"..n):read("a")end
  local UI=G.dofile("/toast/toast_ui.lua")
  local rows=UI.JOB.mining.rows(msg)
  local found=false;for _,r in ipairs(rows) do if r[1]=="Kiste 1" then found=true end end
  check("Kisten nicht mehr in den Infozeilen (eigener Knopf)",not found)
end

print("K2 Ohne Kisten im Inventar: normal heimfahren")
S=Sim.new({config=cfg("placeChests=true,torches=0"),actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end},
}})
S.protocol="toast.mine.v1"
do local mv2=S.turtle.forward;S.turtle.forward=function() local ok,w=mv2();if ok and not S.filled and S.p.z==8 then fill(S);S.filled=true end;return ok,w end end
Sim.run(S,600)
st=state(S)
check("Mine trotzdem fertig",st.next and st.next>20,st.next)
local c2=0;for k,v in pairs(S.world) do if v=="minecraft:chest" and not k:match("^0,[%-]?1,0$") then c2=c2+1 end end
check("keine Kiste gesetzt",c2==0,c2)

print("K3 Hoehe 6, obere Schicht voll: runter in die Spalte, Kiste setzen, wieder hoch")
S=Sim.new({config=cfg("placeChests=true,torches=0"):gsub("height=3","height=6"),actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end}}})
S.protocol="toast.mine.v1";S.inv[2]={name="minecraft:chest",count=1}
do local mv3=S.turtle.forward;S.turtle.forward=function() local ok,w=mv3()
    if ok and not S.filled and S.p.z==8 and S.p.y==-4 then fill(S);S.filled=true end
    if S.filled and S.p.z==0 then S.homeAfter=true end
    return ok,w end end
Sim.run(S,800)
st=state(S)
check("Mine fertig",st.next and st.next>40,st.next)
local spot3;for k,v in pairs(S.world) do if v=="minecraft:chest" and k~="0,1,0" and k~="0,-1,0" then spot3=k end end
check("Kiste im Boden unter Spalte z=8",spot3=="0,1,8",spot3)
check("befuellt",spot3 and (S.dropsAt[spot3] or 0)>=13,spot3 and S.dropsAt[spot3])

print("K4 Gemischte Nachschubkiste oben: Fackeln, Kisten, Kohle -> holt alles")
S=Sim.new({config=cfg("placeChests=true,torches=5,useCoal=false"),fuel=50,actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end}}})
S.protocol="toast.mine.v1"
S.top={{name="minecraft:torch",count=64},{name="minecraft:dirt",count=10},{name="minecraft:chest",count=64},{name="minecraft:torch",count=64},{name="minecraft:coal",count=64},{name="minecraft:chest",count=20}};S.topN=6
Sim.run(S,600)
st=state(S)
local function inv(name) local n=0;for i=1,16 do if S.inv[i] and S.inv[i].name==name then n=n+S.inv[i].count end end;return n end
check("Mine fertig (Fuel aus der Kiste)",st.next and st.next>20,tostring(st.next).." fuel="..S.fuel)
check("Fackeln geholt",S.last and S.last.torchesPlaced==4 and inv("minecraft:torch")==60,inv("minecraft:torch"))
check("Kisten geholt (1 Stapel)",inv("minecraft:chest")==64,inv("minecraft:chest"))
local back={};for i=1,S.topN do local s=S.top[i];if s then back[s.name]=(back[s.name] or 0)+s.count end end
check("Rest zurueck in die Kiste",back["minecraft:dirt"]==10 and back["minecraft:torch"]==64 and back["minecraft:chest"]==20,
  tostring(back["minecraft:dirt"]).."/"..tostring(back["minecraft:torch"]).."/"..tostring(back["minecraft:chest"]))
check("kein Dreck aus der Nachschubkiste unten abgeladen",not (S.chestNames["minecraft:dirt"]))
print(pass.." bestanden, "..failc.." fehlgeschlagen")
