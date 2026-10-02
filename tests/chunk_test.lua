package.path="/home/claude/toast/test/?.lua;"..package.path
local Sim=require("sim")
local pass,fail=0,0
local function check(n,c,i)if c then pass=pass+1;print("  PASS "..n)else fail=fail+1;print("  FAIL "..n.."  "..tostring(i))end end
local function cfg(job,cl,extra)return ([[return {role="auto",job="%s",controllerId=4,name="CL",autoDiscover=true,autoPairPockets=true,
 devices={},pocketIds={},display={monitor="auto",textScale=0.5,pageSize=0},network={pollInterval=1,staleAfter=15,commandTimeout=10,maxDevices=256},
 chunkload=%s,
 farm={width=4,length=5,crop="wheat",interval=20,seedReserve=64,radioTimeout=20,water={}},
 mine={length=30,height=3,tunnels=2,gap=2,fuelTarget=200,radioTimeout=20,freeSlots=2,digRetries=16,protectedBlocks={}}%s}]]):format(job,cl,extra or "")end
local CL1='{enabled=true,chunks=1,reportEvery=10}'
local function has(S,name)
  if S.equip.left==name or S.equip.right==name then return true end
  for i=1,16 do if S.inv[i] and S.inv[i].name==name then return true end end
end

print("C1 Mine mit Chunkloader: Spitzhacke<->Modem tauschen, Fuel-Verbrauch, Funk")
local S=Sim.new({config=cfg("mining",CL1),fuel=6000,gear={left="ccchunkloader:chunkloader",right="minecraft:diamond_pickaxe"},
  actions={{t=3,fn=function(S)Sim.cmd(S,"start",10)end}}})
S.inv[16]={name="computercraft:wireless_modem_advanced",count=1}
S.protocol="toast.mine.v1"
local during
local function maxR(S)local m=0;for _,r in ipairs(S.cl.history)do if r>m then m=r end end;return m end
local function chunkMsg(S)for _,m in ipairs(S.sent)do if m.msg.chunks and m.msg.chunks>0 then return m.msg end end end
Sim.run(S,3000)
local st=load("return "..S.files["/toast_mining_state"])()
local missing=0;for t=0,1 do for z=1,30 do for y=0,-2,-1 do if S.world[S.key(t*3,y,z)]~=false then missing=missing+1 end end end end
check("Mine fertig + alles abgebaut",st.next==61 and missing==0 and S.p.x==0 and S.p.z==0,st.next.." miss="..missing.." "..tostring(S.last and S.last.fault))
check("kein Funk-/Fehlerabbruch",S.last and not S.last.fault,S.last and S.last.fault)
check("beim Arbeiten 1 Chunk geladen",maxR(S)==0.5,maxR(S))
local cm=chunkMsg(S)
check("Status zeigt Chunks + Fuel/h",cm and cm.chunks==1 and cm.chunkFuel==2400,cm and (tostring(cm.chunks).." "..tostring(cm.chunkFuel)))
check("an der Basis wieder aus (radius 0)",S.cl.radius==0,S.cl.radius)
check("Chunkloader hat Fuel verbraucht",(S.drained or 0)>0,S.drained)
check("Werkzeug + Modem behalten, nichts davon in der Kiste",has(S,"minecraft:diamond_pickaxe") and has(S,"computercraft:wireless_modem_advanced")
  and not S.chestNames["minecraft:diamond_pickaxe"] and not S.chestNames["computercraft:wireless_modem_advanced"])
check("Chunkloader bleibt angebaut",S.equip.left=="ccchunkloader:chunkloader")
check("wakeOnWorldLoad gesetzt",S.cl.wake==true)
check("Ausruestung wurde getauscht",(S.equipCount or 0)>=2,S.equipCount)

print("C2 STOP waehrend der Arbeit kommt trotz Modem-Tausch an")
S=Sim.new({config=cfg("mining",CL1),fuel=6000,gear={left="ccchunkloader:chunkloader",right="minecraft:diamond_pickaxe"},
  actions={{t=3,fn=function(S)Sim.cmd(S,"start",10)end},{t=25,fn=function(S)Sim.cmd(S,"stop",11)end}}})
S.inv[16]={name="computercraft:wireless_modem_advanced",count=1};S.protocol="toast.mine.v1"
Sim.run(S,300);st=load("return "..S.files["/toast_mining_state"])()
check("gestoppt, zu Hause, Chunks aus",st.next<61 and S.p.x==0 and S.p.z==0 and S.cl.radius==0 and st.commandSerial==11,st.next.." r="..S.cl.radius.." ser="..tostring(st.commandSerial))

print("C3 Absturz mitten im Schritt mit Chunkloader -> sicher (keine falsche Position)")
S=Sim.new({config=cfg("mining",CL1),fuel=6000,gear={left="ccchunkloader:chunkloader",right="minecraft:diamond_pickaxe"},
  actions={{t=3,fn=function(S)Sim.cmd(S,"start",10)end}}})
S.inv[16]={name="computercraft:wireless_modem_advanced",count=1};S.protocol="toast.mine.v1";S.crashAtMove=25
Sim.run(S,3000);st=load("return "..S.files["/toast_mining_state"])()
local ok3=(st.next==61 and S.p.x==0 and S.p.z==0) or (S.last and S.last.recovery and st.x==nil or (S.last and S.last.recovery))
local consistent=(S.last and S.last.recovery) or (st.x==S.p.x and st.y==S.p.y and st.z==S.p.z)
check("entweder fertig oder 'Position unklar', nie falsche Position",ok3 and consistent,
  "next="..st.next.." rec="..tostring(S.last and S.last.recovery).." st="..tostring(st.x)..","..tostring(st.z).." real="..S.p.x..","..S.p.z)
print("    -> Ergebnis: "..((S.last and S.last.recovery) and "Position unklar (Turtle wartet auf --dock)" or "selbst wiederhergestellt"))

print("C3b Absturz VOR dem Schritt (Fuel nur vom Chunkloader weniger) -> nie falsche Position")
S=Sim.new({config=cfg("mining",CL1),fuel=6000,gear={left="ccchunkloader:chunkloader",right="minecraft:diamond_pickaxe"},
  actions={{t=3,fn=function(S)Sim.cmd(S,"start",10)end}}})
S.inv[16]={name="computercraft:wireless_modem_advanced",count=1};S.protocol="toast.mine.v1"
local origFwd=S.turtle.forward;local n=0
S.turtle.forward=function()n=n+1;if n==20 then S.turtle.forward=origFwd;error("SIMULIERTER SERVERSTOPP VOR SCHRITT",0) end;return origFwd()end
Sim.run(S,3000);st=load("return "..S.files["/toast_mining_state"])()
consistent=(S.last and S.last.recovery) or (st.x==S.p.x and st.y==S.p.y and st.z==S.p.z)
check("vor dem Schritt: fertig oder 'Position unklar', nie falsch",consistent,
  "rec="..tostring(S.last and S.last.recovery).." st="..tostring(st.x)..","..tostring(st.z).." real="..S.p.x..","..S.p.z)
print("    -> Ergebnis: "..((S.last and S.last.recovery) and "Position unklar (Turtle wartet auf --dock)" or "selbst wiederhergestellt"))

print("C4 Chunkloader an, aber kein Modem -> klare Meldung")
S=Sim.new({config=cfg("mining",CL1),gear={left="ccchunkloader:chunkloader",right="minecraft:diamond_pickaxe"}})
S.protocol="toast.mine.v1";Sim.run(S,30)
local msg=table.concat(S.log," | ")
check("Meldung Modem ins Inventar",msg:find("Endermodem ins Turtle-Inventar",1,true)~=nil,msg:sub(-200))

print("C5 Chunkloader an, aber Upgrade fehlt -> klare Meldung")
S=Sim.new({config=cfg("mining",CL1)});S.protocol="toast.mine.v1";Sim.run(S,30)
msg=table.concat(S.log," | ")
check("Meldung Upgrade nicht angebaut",msg:find("Chunkloader-Upgrade nicht angebaut",1,true)~=nil,msg:sub(-200))

print("C6 Farm mit Chunkloader: Runde + Warten bleibt geladen, danach STOP -> aus")
S=Sim.new({config=cfg("farm",CL1),default=false,fuel=3000,gear={left="ccchunkloader:chunkloader",right="minecraft:diamond_pickaxe"},
  actions={{t=3,fn=function(S)Sim.cmd(S,"start",10)end}},
  world=function(S)for x=0,3 do for z=1,5 do S.world[S.key(x,1,z)]="minecraft:wheat_ripe" end end end})
S.inv[1]={name="minecraft:wheat_seeds",count=64};S.inv[16]={name="computercraft:wireless_modem_advanced",count=1}
S.protocol="toast.farm.v2"
local waitRadius
S.actions[#S.actions+1]={t=80,fn=function(S)waitRadius=S.cl.radius end}
S.actions[#S.actions+1]={t=90,fn=function(S)Sim.cmd(S,"stop",11)end}
Sim.run(S,140)
local fs_=load("return "..S.files["/toast_farm_state"])()
check("Runde fertig",fs_.rounds>=1 and fs_.harvested==20,tostring(fs_.rounds).." h="..tostring(fs_.harvested))
check("im Dauerbetrieb geladen",waitRadius==0.5,waitRadius)
check("nach STOP an Basis aus",S.cl.radius==0 and S.p.x==0 and S.p.z==0,S.cl.radius)
check("Werkzeug + Modem behalten",has(S,"minecraft:diamond_pickaxe") and has(S,"computercraft:wireless_modem_advanced") and not S.chestNames["minecraft:diamond_pickaxe"])

print("C7 idle=true -> auch an der Basis geladen")
S=Sim.new({config=cfg("mining",'{enabled=true,chunks=1,idle=true}'),gear={left="ccchunkloader:chunkloader",right="computercraft:wireless_modem_advanced"}})
S.inv[16]={name="minecraft:diamond_pickaxe",count=1};S.protocol="toast.mine.v1";Sim.run(S,20)
check("an Basis geladen",S.cl.radius==0.5,S.cl.radius)

print(("\n%d bestanden, %d fehlgeschlagen"):format(pass,fail))
