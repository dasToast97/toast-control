package.path="/home/claude/toast/test/?.lua;"..package.path
local Sim=require("sim")
local S=Sim.new({config=""});local G=Sim.env(S)
for _,n in ipairs({"toast_common.lua","toast_model.lua","toast_ui.lua"})do S.files["/toast/"..n]=io.open("/home/claude/toast/"..n):read("a")end
G.os.getComputerID=function()return 4 end;G.turtle=nil
local cfg=G.dofile("/toast/toast_common.lua").load(assert(load(io.open("/home/claude/toast/toast.config.lua"):read("a"),"c","t",{}))())
assert(cfg.recovery.autoRetry==3,"defaults")
local model=G.dofile("/toast/toast_model.lua").new(cfg)
model.ingest(12,{kind="status",version=2,id=12,status="Lava erkannt",fault="Lava erkannt",detail="x",ack=0,total=5},"toast.mine.v1")
model.ingest(5,{kind="status",version=2,id=5,status="Bereit",ack=0,total=9},"toast.farm.v2")
assert(model.command("reset","all"),"reset all")
local sent=0;for _,m in ipairs(S.sent)do if m.msg.action=="reset" then sent=sent+1 end end
assert(sent==2,"reset an beide: "..sent)
for _,sz in ipairs({{26,18},{39,13},{26,20},{79,38}})do
  local lines={}
  local scr={getSize=function()return sz[1],sz[2]end,setBackgroundColor=function()end,setTextColor=function()end,
    clear=function()lines={}end,setCursorPos=function(x,y)lines.y=y end,write=function(s)lines[lines.y]=(lines[lines.y] or "")..s end}
  local ui=G.dofile("/toast/toast_ui.lua").new(scr,cfg)
  ui.draw(model.fleet(),true,model.notice)
  local found=false;for _,b in ipairs(ui.buttons)do if b.action=="reset" and b.enabled then found=true end end
  local okSmall=sz[2]<18
  assert(found or okSmall,"reset button "..sz[1].."x"..sz[2])
  if found then assert(ui.click(math.floor(sz[1]/2),sz[2])=="reset","reset unten") end
  print("UI "..sz[1].."x"..sz[2].." ok"..(okSmall and " (Mindestgroesse-Hinweis)" or ""))
end
assert(G.dofile("/toast/toast_ui.lua").new({},cfg).keys["4"]=="reset")
print("Zentrale/UI-Test bestanden; Fehlerlog:",(S.files["/toast/fehler.log"] or ""):gsub("\n"," "))
