package.path="/home/claude/toast/test/?.lua;"..package.path
local Sim=require("sim")
local pass,fail=0,0
local function check(n,c,i)if c then pass=pass+1;print("  PASS "..n)else fail=fail+1;print("  FAIL "..n.."  "..tostring(i))end end
local CFG=[[return {role="turtle",job="mining",name="Alt",controllerId=4,mine={length=6,height=3,tunnels=2,gap=1,radioTimeout=20}}]]
print("toast.lua config: Name + Masse aendern, speichern, dann normal starten")
local S=Sim.new({config=CFG,input={"1","Neu Nord","3","8","","","","","",""},actions={{t=5,fn=function(S)Sim.cmd(S,"start",10)end}}})
S.files["/toast/toast_setup.lua"]=io.open("/home/claude/toast/toast_setup.lua"):read("a")
S.files["/toast_mining_state"]='{x=0,y=0,z=0,dir=0,next=3,total=0,harvested=0,commandSerial=1,layout="strip2:6:3:2:1"}'
S.protocol="toast.mine.v1"
Sim.run(S,400,{"config"})
local c=load(S.files["/toast.config.lua"])()
check("Name + Laenge gespeichert",c.name=="Neu Nord" and c.mine.length==8,c.name.." "..c.mine.length)
check("kompakte Config bleibt gueltig + sauber",S.files["/toast.config.lua"]:find("-- Ganglaenge",1,true)~=nil)
local st=load("return "..S.files["/toast_mining_state"])()
check("neue Masse -> neuer Auftrag, danach fertig",st.next==2*8+1 and st.layout=="strip2:8:3:2:1",st.next.." "..tostring(st.layout))
check("Name in Statusmeldung",S.last and S.last.label=="Neu Nord")
print("toast.lua config: q = abbrechen, nichts geaendert")
S=Sim.new({config=CFG,input={"1","Egal","q"}})
S.files["/toast/toast_setup.lua"]=io.open("/home/claude/toast/toast_setup.lua"):read("a")
S.protocol="toast.mine.v1";Sim.run(S,20,{"config"})
check("Config unveraendert",S.files["/toast.config.lua"]==CFG)
print(("\n%d bestanden, %d fehlgeschlagen"):format(pass,fail))
