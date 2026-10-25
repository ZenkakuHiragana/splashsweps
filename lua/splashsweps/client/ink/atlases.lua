
-- Builds all atlases the ink shaders read from the loaded ink types and ink shapes.

---@class ss
local ss = SplashSWEPs
local InkDetailAtlas = ss.import "splashsweps/client/ink/inkdetailatlas"
local PaintAtlas     = ss.import "splashsweps/client/ink/paintatlas"

---@class ss.InkAtlasesModule
local InkAtlases = ss.module "splashsweps/client/ink/atlases"

---Lays out and creates the atlases, and draws them from the next frame, when drawing works.
function InkAtlases.Load()
    local plan = PaintAtlas.Plan()
    local inkDataByType = InkDetailAtlas.Prepare(plan.Sources.BaseNames)
    if not inkDataByType then return end
    PaintAtlas.Allocate(plan)
    timer.Simple(0, function()
        PaintAtlas.Draw(plan)
        InkDetailAtlas.DrawInitial(inkDataByType)
    end)
end

return InkAtlases
