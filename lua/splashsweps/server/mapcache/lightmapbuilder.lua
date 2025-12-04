
---@class ss
local ss = SplashSWEPs
if not ss then return end

local band = bit.band
local bxor = bit.bxor
local byte = string.byte
local Clamp = math.Clamp
local floor = math.floor
local pow = math.pow

-- From public/bspflags.h
local SURF_NOLIGHT = 0x0400

-- From public\materialsystem\imaterial.h
local FLAGS2_BUMPED_LIGHTMAP = 8 -- (1 << 3)

---Generates lightmap packing information for all faces in a BSP.
---@param bsp ss.RawBSPResults
---@param ishdr boolean
---@param surfaceInfo ss.PrecachedData.SurfaceInfo
---@param cache ss.PrecachedData
function ss.BuildLightmapInfo(bsp, ishdr, surfaceInfo, cache)
    print("    Generating lightmap info (" .. (ishdr and "HDR" or "LDR") .. ")...")
    local faces = ishdr and bsp.FACES_HDR or bsp.FACES
    if not faces or #faces == 0 then return end

    local rawTexInfo           = bsp.TEXINFO
    local rawTexData           = bsp.TEXDATA
    local rawTexDict           = bsp.TEXDATA_STRING_TABLE
    local rawTexIndex          = bsp.TexDataStringTableToIndex
    local rawTexString         = bsp.TEXDATA_STRING_DATA
    local rawSamples           = ishdr and bsp.LIGHTING_HDR or bsp.LIGHTING
    local materialIDs          = {} ---@type table<string, integer>
    local needsBumpedLightmaps = {} ---@type boolean[]
    local power2         ---@type number[]
    local linearToScreen ---@type number[]
    for i, texName in ipairs(rawTexString) do
        local sanitized = texName:lower():StripExtension():gsub("\\", "/")
        local mat = Material(sanitized)
        needsBumpedLightmaps[i] = mat and not mat:IsError() and
            band(mat:GetInt "$flags2", FLAGS2_BUMPED_LIGHTMAP) ~= 0
        materialIDs[sanitized] = i
        cache.MaterialNames[i] = sanitized
    end

    local faceLumpIndexToSurfaceInfoIndex = {} ---@type integer[]
    for i, surf in ipairs(surfaceInfo.Surfaces) do
        faceLumpIndexToSurfaceInfoIndex[surf.FaceLumpIndex] = i
        surf.FaceLumpIndex = nil
    end

    -- Create a list of face objects with all necessary info for sorting
    for i, rawFace in ipairs(faces) do
        local texInfo     = rawTexInfo[rawFace.texInfo + 1]
        local texData     = rawTexData[texInfo.texData + 1]
        local texOffset   = rawTexDict[texData.nameStringTableID + 1]
        local texIndex    = rawTexIndex[texOffset]
        local texName     = rawTexString[texIndex]
        local materialID  = materialIDs[texName:lower():StripExtension():gsub("\\", "/")]
        local lightOffset = rawFace.lightOffset + 1
        local lightStyles = rawFace.styles
        local width       = rawFace.lightmapTextureSizeInLuxels[1]
        local height      = rawFace.lightmapTextureSizeInLuxels[2]
        local nolight     = band(texInfo.flags, SURF_NOLIGHT) > 0 or
            ((width == 0 or height == 0) and not (rawSamples and #rawSamples > 0))
        local hasLightmap = not nolight
        local t          = ss.new "PrecachedData.LightmapInfo"
        t.FaceIndex      = faceLumpIndexToSurfaceInfoIndex[i]
        t.HasLightmap    = hasLightmap and 1 or nil
        t.HasLightStyles = ((lightStyles[1] ~= 0 and
                            lightStyles[1] ~= 255) or
                            lightStyles[2] ~= 255) and 1 or nil
        t.MaterialIndex  = materialID
        t.Width          = hasLightmap and width + 1 or 0
        t.Height         = hasLightmap and height + 1 or 0

        -- CheckSurfaceLighting
        local v = Vector()
        if not power2 then
            power2 = {
                1.152445441982634800E-041, 2.304890883965269600E-041,
                4.609781767930539200E-041, 9.219563535861078400E-041,
                1.843912707172215700E-040, 3.687825414344431300E-040,
                7.375650828688862700E-040, 1.475130165737772500E-039,
                2.950260331475545100E-039, 5.900520662951090200E-039,
                1.180104132590218000E-038, 2.360208265180436100E-038,
                4.720416530360872100E-038, 9.440833060721744200E-038,
                1.888166612144348800E-037, 3.776333224288697700E-037,
                7.552666448577395400E-037, 1.510533289715479100E-036,
                3.021066579430958200E-036, 6.042133158861916300E-036,
                1.208426631772383300E-035, 2.416853263544766500E-035,
                4.833706527089533100E-035, 9.667413054179066100E-035,
                1.933482610835813200E-034, 3.866965221671626400E-034,
                7.733930443343252900E-034, 1.546786088668650600E-033,
                3.093572177337301200E-033, 6.187144354674602300E-033,
                1.237428870934920500E-032, 2.474857741869840900E-032,
                4.949715483739681800E-032, 9.899430967479363700E-032,
                1.979886193495872700E-031, 3.959772386991745500E-031,
                7.919544773983491000E-031, 1.583908954796698200E-030,
                3.167817909593396400E-030, 6.335635819186792800E-030,
                1.267127163837358600E-029, 2.534254327674717100E-029,
                5.068508655349434200E-029, 1.013701731069886800E-028,
                2.027403462139773700E-028, 4.054806924279547400E-028,
                8.109613848559094700E-028, 1.621922769711818900E-027,
                3.243845539423637900E-027, 6.487691078847275800E-027,
                1.297538215769455200E-026, 2.595076431538910300E-026,
                5.190152863077820600E-026, 1.038030572615564100E-025,
                2.076061145231128300E-025, 4.152122290462256500E-025,
                8.304244580924513000E-025, 1.660848916184902600E-024,
                3.321697832369805200E-024, 6.643395664739610400E-024,
                1.328679132947922100E-023, 2.657358265895844200E-023,
                5.314716531791688300E-023, 1.062943306358337700E-022,
                2.125886612716675300E-022, 4.251773225433350700E-022,
                8.503546450866701300E-022, 1.700709290173340300E-021,
                3.401418580346680500E-021, 6.802837160693361100E-021,
                1.360567432138672200E-020, 2.721134864277344400E-020,
                5.442269728554688800E-020, 1.088453945710937800E-019,
                2.176907891421875500E-019, 4.353815782843751100E-019,
                8.707631565687502200E-019, 1.741526313137500400E-018,
                3.483052626275000900E-018, 6.966105252550001700E-018,
                1.393221050510000300E-017, 2.786442101020000700E-017,
                5.572884202040001400E-017, 1.114576840408000300E-016,
                2.229153680816000600E-016, 4.458307361632001100E-016,
                8.916614723264002200E-016, 1.783322944652800400E-015,
                3.566645889305600900E-015, 7.133291778611201800E-015,
                1.426658355722240400E-014, 2.853316711444480700E-014,
                5.706633422888961400E-014, 1.141326684577792300E-013,
                2.282653369155584600E-013, 4.565306738311169100E-013,
                9.130613476622338300E-013, 1.826122695324467700E-012,
                3.652245390648935300E-012, 7.304490781297870600E-012,
                1.460898156259574100E-011, 2.921796312519148200E-011,
                5.843592625038296500E-011, 1.168718525007659300E-010,
                2.337437050015318600E-010, 4.674874100030637200E-010,
                9.349748200061274400E-010, 1.869949640012254900E-009,
                3.739899280024509800E-009, 7.479798560049019500E-009,
                1.495959712009803900E-008, 2.991919424019607800E-008,
                5.983838848039215600E-008, 1.196767769607843100E-007,
                2.393535539215686200E-007, 4.787071078431372500E-007,
                9.574142156862745000E-007, 1.914828431372549000E-006,
                3.829656862745098000E-006, 7.659313725490196000E-006,
                1.531862745098039200E-005, 3.063725490196078400E-005,
                6.127450980392156800E-005, 1.225490196078431400E-004,
                2.450980392156862700E-004, 4.901960784313725400E-004,
                9.803921568627450800E-004, 1.960784313725490200E-003,
                3.921568627450980300E-003, 7.843137254901960700E-003,
                1.568627450980392100E-002, 3.137254901960784300E-002,
                6.274509803921568500E-002, 1.254901960784313700E-001,
                2.509803921568627400E-001, 5.019607843137254800E-001,
                1.003921568627451000E+000, 2.007843137254901900E+000,
                4.015686274509803900E+000, 8.031372549019607700E+000,
                1.606274509803921500E+001, 3.212549019607843100E+001,
                6.425098039215686200E+001, 1.285019607843137200E+002,
                2.570039215686274500E+002, 5.140078431372548900E+002,
                1.028015686274509800E+003, 2.056031372549019600E+003,
                4.112062745098039200E+003, 8.224125490196078300E+003,
                1.644825098039215700E+004, 3.289650196078431300E+004,
                6.579300392156862700E+004, 1.315860078431372500E+005,
                2.631720156862745100E+005, 5.263440313725490100E+005,
                1.052688062745098000E+006, 2.105376125490196000E+006,
                4.210752250980392100E+006, 8.421504501960784200E+006,
                1.684300900392156800E+007, 3.368601800784313700E+007,
                6.737203601568627400E+007, 1.347440720313725500E+008,
                2.694881440627450900E+008, 5.389762881254901900E+008,
                1.077952576250980400E+009, 2.155905152501960800E+009,
                4.311810305003921500E+009, 8.623620610007843000E+009,
                1.724724122001568600E+010, 3.449448244003137200E+010,
                6.898896488006274400E+010, 1.379779297601254900E+011,
                2.759558595202509800E+011, 5.519117190405019500E+011,
                1.103823438081003900E+012, 2.207646876162007800E+012,
                4.415293752324015600E+012, 8.830587504648031200E+012,
                1.766117500929606200E+013, 3.532235001859212500E+013,
                7.064470003718425000E+013, 1.412894000743685000E+014,
                2.825788001487370000E+014, 5.651576002974740000E+014,
                1.130315200594948000E+015, 2.260630401189896000E+015,
                4.521260802379792000E+015, 9.042521604759584000E+015,
                1.808504320951916800E+016, 3.617008641903833600E+016,
                7.234017283807667200E+016, 1.446803456761533400E+017,
                2.893606913523066900E+017, 5.787213827046133800E+017,
                1.157442765409226800E+018, 2.314885530818453500E+018,
                4.629771061636907000E+018, 9.259542123273814000E+018,
                1.851908424654762800E+019, 3.703816849309525600E+019,
                7.407633698619051200E+019, 1.481526739723810200E+020,
                2.963053479447620500E+020, 5.926106958895241000E+020,
                1.185221391779048200E+021, 2.370442783558096400E+021,
                4.740885567116192800E+021, 9.481771134232385600E+021,
                1.896354226846477100E+022, 3.792708453692954200E+022,
                7.585416907385908400E+022, 1.517083381477181700E+023,
                3.034166762954363400E+023, 6.068333525908726800E+023,
                1.213666705181745400E+024, 2.427333410363490700E+024,
                4.854666820726981400E+024, 9.709333641453962800E+024,
                1.941866728290792600E+025, 3.883733456581585100E+025,
                7.767466913163170200E+025, 1.553493382632634000E+026,
                3.106986765265268100E+026, 6.213973530530536200E+026,
                1.242794706106107200E+027, 2.485589412212214500E+027,
                4.971178824424429000E+027, 9.942357648848857900E+027,
                1.988471529769771600E+028, 3.976943059539543200E+028,
                7.953886119079086300E+028, 1.590777223815817300E+029,
                3.181554447631634500E+029, 6.363108895263269100E+029,
                1.272621779052653800E+030, 2.545243558105307600E+030,
                5.090487116210615300E+030, 1.018097423242123100E+031,
                2.036194846484246100E+031, 4.072389692968492200E+031,
                8.144779385936984400E+031, 1.628955877187396900E+032,
                3.257911754374793800E+032, 6.515823508749587500E+032,
                1.303164701749917500E+033, 2.606329403499835000E+033,
                5.212658806999670000E+033, 1.042531761399934000E+034,
                2.085063522799868000E+034, 4.170127045599736000E+034,
                8.340254091199472000E+034, 1.668050818239894400E+035,
                3.336101636479788800E+035, 6.672203272959577600E+035,
            }

            linearToScreen = {}
            local N = 1024
            for j = 1, N do
                linearToScreen[j] = Clamp(floor(255 * pow((j - 1) / (N - 1), 1 / 2.2)), 0, 255)
            end
        end

        local maxLightmapIndex = 1
        while lightStyles[maxLightmapIndex + 1]
            and lightStyles[maxLightmapIndex + 1] ~= 255 do
            maxLightmapIndex = maxLightmapIndex + 1
        end

        if maxLightmapIndex >= 2 then
            local minLightValue = 1
            local offset = (width + 1) * (height + 1)
            if needsBumpedLightmaps[materialID] then
                offset = offset * 4
            end

            for j = maxLightmapIndex, 2, -1 do
                local maxLength = -1
                local maxR, maxG, maxB = 0, 0, 0
                for k = 0, offset - 1 do
                    local ptr = lightOffset + ((j - 1) * offset + k) * 4
                    local r, g, b, e = byte(rawSamples, ptr, ptr + 3)
                    -- ColorRGBExp32ToVector
                    e = bxor(e, 128)
                    v:SetUnpacked( -- TexLightToLinear
                        255 * r * power2[e + 1],
                        255 * g * power2[e + 1],
                        255 * b * power2[e + 1])
                    local length = v:Length()
                    if length > maxLength then
                        maxLength = length
                        maxR, maxG, maxB = v:Unpack()
                    end
                end

                maxR = linearToScreen[Clamp(floor(maxR * (#linearToScreen - 1)), 0, #linearToScreen - 1) + 1]
                maxG = linearToScreen[Clamp(floor(maxG * (#linearToScreen - 1)), 0, #linearToScreen - 1) + 1]
                maxB = linearToScreen[Clamp(floor(maxB * (#linearToScreen - 1)), 0, #linearToScreen - 1) + 1]
                if maxR <= minLightValue and maxG <= minLightValue and maxB <= minLightValue then
                    maxLightmapIndex = maxLightmapIndex - 1
                end
            end

            if maxLightmapIndex == 1 then
                t.HasLightStyles = nil
            end
        end
        surfaceInfo.Lightmaps[i] = t
    end
end
