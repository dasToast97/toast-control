package.path="/home/claude/toast/test/?.lua;"..package.path
local Sim=require("sim")
local src=io.open("/home/claude/toast/toast_install.lua"):read("a")
local pass,fail=0,0
local function check(n,c,i)if c then pass=pass+1;print("  PASS "..n)else fail=fail+1;print("  FAIL "..n.." "..tostring(i))end end
local function env(S,isTurtle,id)
  local G=Sim.env(S)
  if not isTurtle then G.turtle=nil end
  G.os.getComputerID=function()return id end
  G.fs.list=function()local seen,out={},{}
    for p in pairs(S.files)do local top=p:match("^/([^/]+)")if top and not seen[top]then seen[top]=true;out[#out+1]=top end end
    out[#out+1]="rom";table.sort(out);return out end
  G.fs.delete=function(p)for k in pairs(S.files)do if k==p or k:sub(1,#p+1)==p.."/" then S.files[k]=nil end end end
  G.fs.isReadOnly=function(p)return p=="/rom" end
  G.fs.getDrive=function(p)return p=="/rom" and "rom" or "hdd" end
  G.fs.getFreeSpace=function()return 900000 end
  G.term.clear=function()end;G.term.isColor=function()return true end
  G.sleep=function()end
  G.read=function()local v=table.remove(S.input,1);if v==nil then error("KEINE EINGABE MEHR: "..table.concat(S.log," / "):sub(-300),0) end;return v end
  return G
end
local function install(S,isTurtle,id,args)
  local f=assert(load(src,"@inst","t",env(S,isTurtle,id)))
  return pcall(f,table.unpack(args or {}))
end
local function cfgOf(S)local f=load(S.files["/toast.config.lua"] or "return nil");return f and f() end
local MINECFG=[[return {role="auto",job="mining",controllerId=4,label="Alt",autoDiscover=true,autoPairPockets=true,devices={},pocketIds={},display={monitor="auto",textScale=0.5,pageSize=0},network={pollInterval=1,staleAfter=15,commandTimeout=10,maxDevices=256},farm={width=3,length=3,crop="wheat",interval=5,seedReserve=16,radioTimeout=10,water={}},mine={length=4,height=2,tunnels=2,gap=1,fuelTarget=100,radioTimeout=10,freeSlots=2,digRetries=16,protectedBlocks={"minecraft:bedrock"}}}]]

print("A Turtle Update (alte Config) -> Einstellungen bleiben, saubere Config, Mine laeuft weiter")
local S=Sim.new({config=MINECFG,input={"1","n","j","n"}});S.files={}
S.files["/toast.config.lua"]=MINECFG
S.files["/toast_mining_state"]='{x=0,y=0,z=0,dir=0,next=3,total=5,harvested=5,commandSerial=1,layout="strip:4:2:2:1"}'
S.files["/farm_turtle.lua"]="alt";S.files["/toast/alt_modul.lua"]="alt";S.files["/startup.lua"]="shell.run('irgendwas')"
S.files["/meinprog.lua"]="x"
local ok,err=install(S,true,7)
check("laeuft durch",ok,err)
check("Altlasten weg",not S.files["/farm_turtle.lua"] and not S.files["/toast/alt_modul.lua"] and not S.files["/meinprog.lua"])
local kc=cfgOf(S)
check("Werte behalten (Name aus label, Zentrale, Masse)",kc and kc.job=="mining" and kc.controllerId==4 and kc.name=="Alt" and kc.mine.length==4 and kc.mine.radioTimeout==10,kc and kc.name)
check("alte Schutzliste geleert",kc and #kc.mine.protectedBlocks==0)
check("Config sauber: Kommentare, kein farm-Abschnitt",S.files["/toast.config.lua"]:find("-- Ganglaenge",1,true) and not kc.farm and not kc.display)
check("Einstellungsmenue installiert",S.files["/toast/toast_setup.lua"]~=nil)
check("Autostart",S.files["/startup.lua"]=='shell.run("/toast.lua")\n')
S.T=0;S.timers={};S.queue={};S.input={};S.actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end}};S.protocol="toast.mine.v1"
Sim.run(S,600)
local st=load("return "..S.files["/toast_mining_state"])()
check("installierte Mine laeuft ab gespeicherter Stelle",st.next==9,st.next.." "..tostring(S.result))

print("B Turtle komplett neu, Standardwerte")
S=Sim.new({config=MINECFG,input={"2","LOESCHEN","2","","","j","n"}});S.files={}
S.files["/toast.config.lua"]=MINECFG;S.files["/toast_mining_state"]="{x=5}";S.files["/meinprog.lua"]="x"
ok,err=install(S,true,7)
check("laeuft durch",ok,err)
check("alles alte weg",not S.files["/toast_mining_state"] and not S.files["/meinprog.lua"])
kc=cfgOf(S)
check("neue Config Mining mit Standardwerten",kc and kc.job=="mining" and kc.mine.length==100 and kc.recovery.autoRetry==3)

print("C Abbruch ohne LOESCHEN loescht nichts")
S=Sim.new({config=MINECFG,input={"2","nein"}});S.files={["/meinprog.lua"]="x"}
ok,err=install(S,true,7)
check("abgebrochen + Datei noch da",not ok and S.files["/meinprog.lua"]=="x",err)

print("D Neue Zentrale (#4, ohne Monitor, 1 gewaehlt) mit Name")
S=Sim.new({config=MINECFG,input={"1","1","1","Zentrale Haus","","n","n"}});S.files={["/farm_touch.lua"]="alt"}
ok,err=install(S,false,4)
kc=ok and cfgOf(S)
check("Zentrale, ID 4, Name, Dateien",kc and kc.role=="controller" and kc.controllerId==4 and kc.name=="Zentrale Haus"
  and S.files["/toast/toast_control.lua"] and not S.files["/farm_touch.lua"] and kc.display and not kc.mine,err)

print("E Kaputte Config wird ersetzt")
S=Sim.new({config=MINECFG,input={"1","1","","","n","n"}});S.files={["/toast.config.lua"]="return {kaputt"}
ok,err=install(S,true,7)
check("neue Farm-Config",ok and cfgOf(S).job=="farm",err)

print("F Neue Farm: Name, 10 x 4, links, Karotten, Pause 30")
S=Sim.new({config=MINECFG,input={"1","1","4","1","Karotten Sued","3","10","4","l","2","30","","","j","n"}});S.files={}
ok,err=install(S,true,7)
kc=ok and cfgOf(S)
check("Name + Feld gespeichert",kc and kc.name=="Karotten Sued" and kc.farm.length==10 and kc.farm.width==4 and kc.farm.side=="left"
  and kc.farm.crop=="carrots" and kc.farm.interval==30 and #kc.farm.water==0 and not kc.mine,err)
-- Runde auf gespiegeltem 10x4-Feld mit Wasserreihe
S.T=0;S.timers={};S.queue={};S.input={};S.protocol="toast.farm.v2"
S.actions={{t=2,fn=function(S)Sim.cmd(S,"once",10)end}}
S.inv[1]={name="minecraft:carrot",count=64}
for x=0,3 do for z=1,10 do S.world[S.key(-x,1,z)]=(z==5) and "minecraft:water" or "minecraft:carrots_ripe" end end
S.world[S.key(0,1,0)]="minecraft:chest";S.world[S.key(0,-1,0)]="minecraft:chest"
for x=-4,4 do for z=0,11 do if S.world[S.key(x,0,z)]==nil then S.world[S.key(x,0,z)]=false end end end
Sim.run(S,600)
if os.getenv("DBG") then print(S.result);for i=math.max(1,#S.log-8),#S.log do print("   ",S.log[i]) end;print(S.last and S.last.status,S.last and S.last.detail) end
local fs_=load("return "..S.files["/toast_farm_state"])()
local left=0;for x=0,3 do for z=1,10 do if S.world[S.key(-x,1,z)]=="minecraft:carrots_ripe" then left=left+1 end end end
check("Feld links abgeerntet, Wasser uebersprungen",fs_.rounds==1 and left==0 and fs_.harvested==36,tostring(fs_.rounds).." rest="..left)
check("Name in Statusmeldung",S.last and S.last.label=="Karotten Sued")

print("G Minenmasse aendern -> neuer Auftrag")
S=Sim.new({config=MINECFG,input={"1","j","3","50","3","3","2","r","","","","","j","n","n"}});S.files={}
S.files["/toast.config.lua"]=MINECFG
S.files["/toast_mining_state"]='{x=0,y=0,z=0,dir=0,next=5,total=5,harvested=5,commandSerial=1,layout="strip2:4:2:2:1"}'
ok,err=install(S,true,7)
kc=ok and cfgOf(S)
check("neue Minenmasse",kc and kc.mine.length==50 and kc.mine.height==3 and kc.mine.tunnels==3,err)
check("alter Fortschritt zurueckgesetzt",S.files["/toast_mining_state"]==nil)

print("H Computer ohne Monitor -> Enter = Repeater")
S=Sim.new({config=MINECFG,input={"1","","1","Repeater Nord","","j","n"}});S.files={}
ok,err=install(S,false,9)
kc=ok and cfgOf(S)
check("Repeater mit Name",kc and kc.role=="repeater" and kc.name=="Repeater Nord" and S.files["/toast/repeater.lua"] and not S.files["/toast/toast_control.lua"],err)

print("J Repeater-Update fragt nicht erneut nach der Rolle")
S=Sim.new({config=MINECFG,input={"1","n","j","n"}});S.files={["/toast.config.lua"]='return {role="repeater",name="R1"}'}
ok,err=install(S,false,9)
check("bleibt Repeater",ok and cfgOf(S).role=="repeater" and cfgOf(S).name=="R1",err)

print("K Chunkloader 9 Chunks waehlen, Basis wach (Standard ja)")
S=Sim.new({config=MINECFG,input={"1","j","4","9","","","n","n"}});S.files={["/toast.config.lua"]=MINECFG}
ok,err=install(S,true,7)
local kc2=ok and cfgOf(S).chunkload
check("chunkload gespeichert",kc2 and kc2.enabled==true and kc2.chunks==9 and kc2.idle==true and kc2.wakeOnWorldLoad==true,err)
local shown=false;for _,l in ipairs(S.log)do if l:find("47185 Fuel/h",1,true) then shown=true end end
check("Kosten angezeigt",shown)

print("L Abstand 0 -> seitlich mitabbauen")
S=Sim.new({config=MINECFG,input={"1","j","3","40","6","8","0","r","j","","","","","n","n"}});S.files={["/toast.config.lua"]=MINECFG}
ok,err=install(S,true,7)
local lm=ok and cfgOf(S).mine
check("sideDig gespeichert",lm and lm.gap==0 and lm.sideDig==true and lm.tunnels==8,err)

print("M Ungueltige Eingabe wird abgefangen")
S=Sim.new({config=MINECFG,input={"1","j","3","abc","5000","40","","","","","","","","n","n"}});S.files={["/toast.config.lua"]=MINECFG}
ok,err=install(S,true,7)
check("Laenge 40 trotz Falscheingaben",ok and cfgOf(S).mine.length==40,err)

print("N Pocket")
S=Sim.new({config=MINECFG,input={"1","","","j","n"}});S.files={}
local G=env(S,false,12);G.pocket={}
ok,err=pcall(assert(load(src,"@inst","t",G)))
kc=ok and cfgOf(S)
check("Pocket-Config ohne Turtle-Abschnitte",kc and kc.role=="pocket" and not kc.mine and not kc.chunkload and kc.network,err)
print("O Computer -> 3 Infoscreen")
S=Sim.new({config=MINECFG,input={"1","3","4","1","Info Halle","","j","n"}});S.files={}
ok,err=install(S,false,30)
kc=ok and cfgOf(S)
check("Infoscreen mit Name + Zentrale",kc and kc.role=="info" and kc.name=="Info Halle" and kc.controllerId==4
  and S.files["/toast/toast_info.lua"] and S.files["/toast/toast_ui.lua"] and not S.files["/toast/toast_control.lua"] and kc.display and not kc.mine,err)
print("O2 Infoscreen zeigt bestimmte Turtle")
S=Sim.new({config=MINECFG,input={"1","3","4","4","6","12","","n","n"}});S.files={}
ok,err=install(S,false,31)
kc=ok and cfgOf(S)
check("show = 12",kc and kc.role=="info" and kc.show==12,err)
S=Sim.new({config=MINECFG,input={"1","3","4","4","3","","n","n"}});S.files={}
ok,err=install(S,false,32)
check("show = mining",ok and cfgOf(S).show=="mining",err)
print("P Infoscreen-Update bleibt Infoscreen")
S=Sim.new({config=MINECFG,input={"1","n","j","n"}});S.files={["/toast.config.lua"]='return {role="info",name="I1",controllerId=4}'}
ok,err=install(S,false,30)
check("bleibt Infoscreen",ok and cfgOf(S).role=="info",err)

print("Q Zentrale: Monitorgroesse 4x8 eingeben")
S=Sim.new({config=MINECFG,input={"1","1","2","","4x8","","n","n"}});S.files={}
ok,err=install(S,false,4)
kc=ok and cfgOf(S)
check("display.size gespeichert",kc and kc.display.size=="4x8",err)
local hint=false;for _,l in ipairs(S.log)do if l:find("82 x 26",1,true) then hint=true end end
check("zeigt berechnete Zeichen (82 x 26)",hint)
print("R Falsche Groesse wird abgefangen")
S=Sim.new({config=MINECFG,input={"1","1","2","","9x9","4 x 3","","n","n"}});S.files={}
ok,err=install(S,false,4)
check("4x3 trotz Falscheingabe",ok and cfgOf(S).display.size=="4x3",err)

print("T Neue Holzfarm: 3 Baeume beidseitig, Abstand 2, Knochenmehl aus")
S=Sim.new({config=MINECFG,input={"1","3","4","1","Birken","3","3","2","3","60","n","20","","j","n"}});S.files={}
ok,err=install(S,true,7)
kc=ok and cfgOf(S)
check("Holz-Config gespeichert",kc and kc.job=="tree" and kc.tree.trees==3 and kc.tree.spacing==2 and kc.tree.side=="both"
  and kc.tree.interval==60 and kc.tree.bonemeal==false and kc.tree.maxHeight==20 and not kc.mine and not kc.farm and not kc.chunkload,err)
check("Holz-Programme installiert",S.files["/toast/tree_turtle.lua"] and S.files["/toast/toast_worker.lua"] and not S.files["/toast/mine_turtle.lua"])
S.T=0;S.timers={};S.queue={};S.input={};S.protocol="toast.tree.v1"
S.actions={{t=2,fn=function(S)Sim.cmd(S,"once",10)end}}
S.inv[1]={name="minecraft:spruce_sapling",count=12}
S.world[S.key(0,1,0)]="minecraft:chest";S.world[S.key(0,-1,0)]="minecraft:chest"
for x=-2,2 do for z=0,8 do for y=-8,0 do if S.world[S.key(x,y,z)]==nil then S.world[S.key(x,y,z)]=false end end end end
S.growTree(1,0,1);S.growTree(-1,0,4);S.growTree(1,0,7)
Sim.run(S,600)
local ts=load("return "..(S.files["/toast_tree_state"] or "{}"))()
check("Holzrunde nach Installation",ts.rounds==1 and ts.harvested==3,tostring(ts.rounds).."/"..tostring(ts.harvested))
check("Status mit Name + Job",S.last and S.last.label=="Birken" and S.last.job=="tree")

print("U Neue Mob-Turtle: Patrouille 6x3 links")
S=Sim.new({config=MINECFG,input={"1","4","4","3","3","n","6","3","l","10","","j","n"}});S.files={}
ok,err=install(S,true,7)
kc=ok and cfgOf(S)
check("Mob-Config gespeichert",kc and kc.job=="mob" and kc.mob.mode=="patrol" and kc.mob.length==6 and kc.mob.width==3
  and kc.mob.side=="left" and kc.mob.interval==10 and kc.mob.attack=="front",err)
check("Mob-Programme installiert",S.files["/toast/mob_turtle.lua"] and S.files["/toast/toast_worker.lua"])
print("U2 Update einer Mob-Turtle behaelt Einstellungen")
local keepFiles=S.files
S=Sim.new({config=MINECFG,input={"1","n","j","n"}});S.files=keepFiles
ok,err=install(S,true,7)
kc=ok and cfgOf(S)
check("Update: Mob-Patrouille bleibt",kc and kc.job=="mob" and kc.mob.mode=="patrol" and kc.mob.length==6,err)

print(("\n%d bestanden, %d fehlgeschlagen"):format(pass,fail))
