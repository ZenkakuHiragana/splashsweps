
-- Builds all atlases the ink shaders read from the loaded ink types and ink shapes.

---@class ss
local ss = SplashSWEPs
local DetailAtlas = ss.import "splashsweps/client/ink/detailatlas"
local TypeAtlas   = ss.import "splashsweps/client/ink/typeatlas"

---@class ss.InkAtlasesModule
local InkAtlases = ss.module "splashsweps/client/ink/atlases"

---Lays out and creates the atlases, and draws them from the next frame, when drawing works.
function InkAtlases.Load()
    local plan = TypeAtlas.Plan()
    local rowsByType = DetailAtlas.Prepare(plan.Sources.BaseNames)
    if not rowsByType then return end
    TypeAtlas.Allocate(plan)
    timer.Simple(0, function()
        TypeAtlas.Draw(plan)
        DetailAtlas.DrawInitial(rowsByType)
    end)
end

return InkAtlases
