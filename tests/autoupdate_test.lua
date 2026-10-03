package.path="/home/claude/toast/test/?.lua;"..package.path
local Sim=require("sim")
local pass,failc=0,0
local function check(name,cond,info)
    if cond then pass=pass+1;print("  PASS "..name) else failc=failc+1;print("  FAIL "..name.."  "..tostring(info or "")) end
end
local function tail(S,n)local t={}for i=math.max(1,#S.log-(n or 8)),#S.log do t[#t+1]=S.log[i]end;return table.concat(t," | ")end
print("A1 Zentrale prueft alle 5 min die Version und startet bei neuer Version das Update fuer alle")
for _,remoteVer in ipairs({"3.2","99.0"}) do
  local S=Sim.new({config=[[return {role="controller",controllerId=4,name="Z",display={monitor="terminal"},
     devices={[12]={job="mining",name="Mine"}},gps={host=true,set=true,x=10,y=70,z=20,auto=false}}]]})
  for _,n in ipairs({"toast_control.lua","toast_model.lua","toast_ui.lua"}) do S.files["/toast/"..n]=io.open("/home/claude/toast/"..n):read("a") end
  S.polling=false;S.protocol="toast.mine.v1"
  local orig=Sim.env
  Sim.env=function(S2) local G=orig(S2);G.os.getComputerID=function()return 4 end;G.turtle=nil
      G.term.isColor=function()return false end
      G.http={request=function(url) S2.requests=(S2.requests or 0)+1
          table.insert(S2.queue,table.pack("http_success",url,{readAll=function()return remoteVer.."\n" end,close=function()end})) return true end,
        get=function() return nil end}
      local sends={};S2.updates=0
      local snd=G.rednet.send
      G.rednet.send=function(id,msg,p) if type(msg)=="table" and msg.action=="update" then S2.updates=S2.updates+1 end;return snd(id,msg,p) end
      -- GPS-Anfrage einspielen
      G.peripheral.getNames=function()return {"right"} end
      G.peripheral.wrap=function(n) if n=="right" then return {isWireless=function()return true end,open=function()end,
          transmit=function(ch,rep,m)S2.gpsReply=m end} end end
      return G end
  S.actions={{t=30,fn=function(S) table.insert(S.queue,table.pack("modem_message","right",65534,777,"PING",5)) end}}
  Sim.run(S,700)
  Sim.env=orig
  check("Version "..remoteVer..": gepruefft (mind. 2x in 700 s)",(S.requests or 0)>=2,S.requests)
  if remoteVer=="99.0" then check("neuere Version -> Update an Turtle gesendet",S.updates>=1,S.updates.." "..tail(S))
  else check("gleiche Version -> kein Update",S.updates==0,S.updates) end
  check("Zentrale beantwortet GPS",S.gpsReply and S.gpsReply[1]==10 and S.gpsReply[2]==70 and S.gpsReply[3]==20,tostring(S.gpsReply and S.gpsReply[1]).." "..tail(S,4))
end
print("A2 Versionsvergleich")
local S=Sim.new({config="return {}"});local G=Sim.env(S);local common=G.dofile("/toast/toast_common.lua")
check("3.2.1 > 3.2",common.newer("3.2.1","3.2"))
check("3.10 > 3.9",common.newer("3.10","3.9"))
check("3.2 = 3.2",not common.newer("3.2","3.2"))
check("3.1 < 3.2",not common.newer("3.1","3.2"))
print(pass.." bestanden, "..failc.." fehlgeschlagen")
