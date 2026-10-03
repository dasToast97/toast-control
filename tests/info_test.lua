package.path="/home/claude/toast/test/?.lua;"..package.path
local Sim=require("sim")
local pass,fail=0,0
local function check(n,c,i)if c then pass=pass+1;print("  PASS "..n)else fail=fail+1;print("  FAIL "..n.."  "..tostring(i))end end
-- 1) Zentrale nimmt Infoscreen auf und schickt ihm die Daten
do
  local S=Sim.new({config=""});local G=Sim.env(S);G.turtle=nil;G.os.getComputerID=function()return 4 end
  for _,n in ipairs({"toast_common.lua","toast_model.lua"})do S.files["/toast/"..n]=io.open("/home/claude/toast/"..n):read("a")end
  local common=G.dofile("/toast/toast_common.lua")
  local cfg=common.load({role="controller",controllerId=4})
  local m=G.dofile("/toast/toast_model.lua").new(cfg)
  m.ingest(12,{kind="status",version=2,id=12,label="Mine Nord",status="Abbau",ack=0,total=50,harvested=80},"toast.mine.v1")
  S.sent={}
  local ok=m.remote(30,{kind="hello",version=1,role="info",controllerId=4},common.remoteProtocol)
  local got;for _,s in ipairs(S.sent)do if s.id==30 and s.msg.kind=="fleet" then got=s.msg end end
  check("Zentrale nimmt Infoscreen auf",ok and got and got.fleet.entries[12].label=="Mine Nord")
  S.sent={};m.tick()
  local again=false;for _,s in ipairs(S.sent)do if s.id==30 and s.msg.kind=="fleet" then again=true end end
  check("schickt ihm jede Runde die Daten",again)
end
-- 2) Infoscreen-Programm auf eigenem Computer mit Monitor
do
  local CFG='return {role="info",name="Info Halle",controllerId=4}'
  local S=Sim.new({config=CFG})
  for _,n in ipairs({"toast_ui.lua","toast_info.lua"})do S.files["/toast/"..n]=io.open("/home/claude/toast/"..n):read("a")end
  S.protocol="toast.control.remote.v1";S.polling=false
  local W,H=39,19;local rows={};local cx,cy=1,1
  for y=1,H do rows[y]=string.rep(" ",W) end
  local mon={getSize=function()return W,H end,isColor=function()return true end,setTextScale=function()end,
    setBackgroundColor=function()end,setTextColor=function()end,clear=function()for y=1,H do rows[y]=string.rep(" ",W) end end,
    setCursorPos=function(x,y)cx,cy=x,y end,write=function(s)if cy<1 or cy>H then return end;s=s:gsub("\7","*");local r=rows[cy];rows[cy]=(r:sub(1,cx-1)..s..r:sub(cx+#s)):sub(1,W);cx=cx+#s end}
  local hellos=0
  local fleet={ids={12},entries={[12]={job="mining",label="Mine Nord",online=true,data={status="Abbau",total=50,harvested=80,scanned=10,cells=100,fuel=500}}}}
  S.actions={{t=2,fn=function(S)table.insert(S.queue,table.pack("rednet_message",4,{kind="fleet",version=1,controllerId=4,fleet=fleet},"toast.control.remote.v1"))end}}
  local orig=Sim.env
  Sim.env=function(S2)local G=orig(S2);G.turtle=nil;G.os.getComputerID=function()return 30 end
    G.peripheral.getNames=function()return {"top"} end
    local gt=G.peripheral.getType;G.peripheral.getType=function(n)if n=="top" then return "monitor" end;return gt(n) end
    local wr=G.peripheral.wrap;G.peripheral.wrap=function(n)if n=="top" then return mon end;return wr(n) end
    local sd=G.rednet.send;G.rednet.send=function(id,msg,p)if type(msg)=="table" and msg.kind=="hello" and msg.role=="info" then hellos=hellos+1 end;return true end
    G.textutils.formatTime=function()return "12:00" end;G.os.time=function()return 12 end
    G.equipModem=nil;return G end
  S.equip={right="computercraft:wireless_modem_advanced"}
  Sim.run(S,8)
  Sim.env=orig
  local screen=table.concat(rows,"\n")
  check("meldet sich bei der Zentrale",hellos>=3,hellos)
  check("zeigt Uebersicht auf dem Monitor",screen:find("TOAST",1,true) and screen:find("Mine Nord",1,true) and screen:find("MINE",1,true),screen)
  check("laeuft weiter (kein Absturz)",S.result=="timeout",S.result.." "..table.concat(S.log," | "):sub(-200))
end
print(("\n%d bestanden, %d fehlgeschlagen"):format(pass,fail))
