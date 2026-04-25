---@class ss
local ss = SplashSWEPs
if not ss then return end

-- Inkmesh render-test suite registration entrypoint.
-- Layered suite registration updated to trigger client auto-refresh.

include "splashsweps/client/tests/inkmesh_test_support.lua"
include "splashsweps/client/tests/inkmesh_test_fixtures.lua"
include "splashsweps/client/tests/inkmesh_core_suite.lua"
include "splashsweps/client/tests/inkmesh_transport_suite.lua"
include "splashsweps/client/tests/inkmesh_adoption_suite.lua"
include "splashsweps/client/tests/inkmesh_visual_suite.lua"

---@type ss.RenderHarness
local rt = ss.RenderHarness
if not rt or not rt.RegisterSuite then return end
if not ss.InkmeshTestCoreSuite or not ss.InkmeshTransportSuite or not ss.InkmeshAdoptionSuite or not ss.InkmeshVisualSuite then return end

function ss.RegisterInkmeshTestSuites()
    rt.ClearTestPrefix("inkmesh.")
    rt.RegisterSuite("inkmesh-core", ss.InkmeshTestCoreSuite.BuildCases())
    rt.RegisterSuite("inkmesh-transport", ss.InkmeshTransportSuite.BuildCases())
    rt.RegisterSuite("inkmesh-adoption", ss.InkmeshAdoptionSuite.BuildCases())
    rt.RegisterSuite("inkmesh-visual", ss.InkmeshVisualSuite.BuildCases())
end

ss.RegisterInkmeshTestSuites()
