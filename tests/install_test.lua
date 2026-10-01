package.path="/home/claude/toast/test/?.lua;"..package.path
local Sim=require("sim")
local src=io.open("/home/claude/toast/toast_install.lua"):read("a")
local pass,fail=0,0
local function check(n,c,i)if c then pass=pass+1;print("  PASS "..n)else fail=fail+1;print("  FAIL "..n.." "..tostring(i))end end
local function env(S,isTurtle,id)
  local G=Sim.env(S)
  if not isTurtle then G.turtle=nil end
  G.os.getComputerID=function()return id end
  G.fs.list=function(dir)local seen,out={},{}
    for p in pairs(S.files)do local top=p:match("^/([^/]+)")if top and not seen[top]then seen[top]=true;out[#out+1]=top end end
    out[#out+1]="rom";table.sort(out);return out end
  G.fs.delete=function(p)for k in pairs(S.files)do if k==p or k:sub(1,#p+1)==p.."/" then S.files[k]=nil end end end
  G.fs.isReadOnly=function(p)return p=="/rom" end
  G.fs.getDrive=function(p)return p=="/rom" and "rom" or "hdd" end
  G.fs.getFreeSpace=function()return 900000 end
  G.term.clear=function()end
  G.read=function()local v=table.remove(S.input,1);if v==nil then error("KEINE EINGABE MEHR: "..table.concat(S.log," / "):sub(-400),0) end;return v end
  return G
end
local function install(S,isTurtle,id,args)
  local G=env(S,isTurtle,id)
  local f=assert(load(src,"@inst","t",G))
  local ok,err=pcall(f,table.unpack(args or {}))
  return ok,err
end
local MINECFG=[[return {role="auto",job="mining",controllerId=4,label="Alt",autoDiscover=true,autoPairPockets=true,devices={},pocketIds={},display={monitor="auto",textScale=0.5,pageSize=0},network={pollInterval=1,staleAfter=15,commandTimeout=10,maxDevices=256},farm={width=3,length=3,crop="wheat",interval=5,seedReserve=16,radioTimeout=10,water={}},mine={length=4,height=2,tunnels=2,gap=1,fuelTarget=100,radioTimeout=10,freeSlots=2,digRetries=16,protectedBlocks={"minecraft:bedrock"}}}]]

print("A Turtle Update-Modus")
local S=Sim.new({config=MINECFG,input={"1","n","j","n"}});S.files={}
S.files["/toast.config.lua"]=MINECFG
S.files["/toast_mining_state"]='{x=0,y=0,z=0,dir=0,next=3,total=5,harvested=5,commandSerial=1,layout="strip:4:2:2:1"}'
S.files["/farm_turtle.lua"]="alt";S.files["/toast/alt_modul.lua"]="alt";S.files["/startup.lua"]="shell.run('irgendwas')"
S.files["/toast_mining_state.backup3"]="x";S.files["/meinprog.lua"]="x"
local ok,err=install(S,true,7)
check("laeuft durch",ok,err)
check("Altlasten weg",not S.files["/farm_turtle.lua"] and not S.files["/toast/alt_modul.lua"] and not S.files["/meinprog.lua"] and not S.files["/toast_mining_state.backup3"])
check("Fortschritt + Config behalten",S.files["/toast_mining_state"] and S.files["/toast.config.lua"]==MINECFG)
check("neue Programme da",S.files["/toast/mine_turtle.lua"] and S.files["/toast.lua"] and not S.files["/toast/farm_turtle.lua"])
check("Autostart neu",S.files["/startup.lua"]=='shell.run("/toast.lua")\n',S.files["/startup.lua"])
-- installiertes System direkt laufen lassen
S.T=0;S.timers={};S.queue={};S.input={};S.actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end}};S.protocol="toast.mine.v1"
Sim.run(S,400)
local st=load("return "..S.files["/toast_mining_state"])()
check("installierte Mine laeuft + setzt bei Zelle 3 fort",st.next==9,st.next.." "..tostring(S.result))

print("B Turtle Komplett neu")
S=Sim.new({config=MINECFG,input={"2","LOESCHEN","2","","n","j","n"}});S.files={}
S.files["/toast.config.lua"]=MINECFG;S.files["/toast_mining_state"]="{x=5}";S.files["/meinprog.lua"]="x"
ok,err=install(S,true,7)
check("laeuft durch",ok,err)
check("alles alte weg",not S.files["/toast_mining_state"] and not S.files["/meinprog.lua"])
local c=load(S.files["/toast.config.lua"])()
check("neue Config Mining, Zentrale 4",c.job=="mining" and c.controllerId==4 and c.recovery and c.recovery.autoRetry==3)

print("C Abbruch ohne LOESCHEN loescht nichts")
S=Sim.new({config=MINECFG,input={"2","nein"}});S.files={["/meinprog.lua"]="x"}
ok,err=install(S,true,7)
check("abgebrochen + Datei noch da",not ok and S.files["/meinprog.lua"]=="x",err)

print("D Zentrale neu (Computer #4)")
S=Sim.new({config=MINECFG,input={"1","n","j","n"}});S.files={["/farm_touch.lua"]="alt"}
ok,err=install(S,false,4)
check("laeuft durch",ok,err)
c=load(S.files["/toast.config.lua"])()
check("Rolle Zentrale, ID 4, Dateien da",c.role=="controller" and c.controllerId==4 and S.files["/toast/toast_control.lua"] and not S.files["/farm_touch.lua"])

print("E Kaputte Config wird ersetzt")
S=Sim.new({config=MINECFG,input={"1","1","","n","j","n"}});S.files={["/toast.config.lua"]="return {kaputt"}
ok,err=install(S,true,7)
check("laeuft durch + neue Farm-Config",ok and load(S.files["/toast.config.lua"])().job=="farm",err)
print(("\n%d bestanden, %d fehlgeschlagen"):format(pass,fail))
