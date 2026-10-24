-- Execute with lua-language-server -e "dofile('tools/luals/realm-check.lua')".
-- Uses the installed LuaLS parser and merger, not substitutes for either API.
local pluginPath = ...
local executable = assert(arg[-1], 'run with the LuaLS executable')
local install = assert(executable:match('^(.*)[/\\]bin[/\\][^/\\]+$'))
package.path = install .. '/script/?.lua;' .. install .. '/script/?/init.lua;' .. package.path
log = require 'log'
local fs = require 'bee.filesystem'
local fileUri = require 'file-uri'
local parser = require 'parser'
local merger = require 'string-merger'
local root = fileUri.encode(fs.current_path():string())
local source = debug.getinfo(1, 'S').source:sub(2)
pluginPath = pluginPath or source:gsub('[^/\\]+$', 'realm.lua')
local examples = {
    {
        text = 'local a,b = (function() if SERVER then return 1,2 else return 3,4 end end)()\nprint(a,b)',
        server = 3, client = 3,
    },
    {
        text = 'local result = producesNumber()\nif CLIENT then ignored() end\n(function() liveMarker() end)()',
        server = 2, client = 3,
    },
    {
        text = 'local a,b = (function() if CLIENT then return 1,2 end return 3,4 end)()\nprint(a,b)',
        server = 3, client = 3,
    },
    {
        text = 'if SERVER then return end\nlocal a,b = (function() if CLIENT then return 1,2 end return 3,4 end)()\nprint(a,b)',
        server = 1, client = 3,
    },
    {
        -- Each realm keeps references from the removed arm to outer locals.
        text = 'local x, y = 1, 2\nif SERVER then print(x) else print(y) end\n(f)()',
        server = 5, client = 5, keeps = { server = 'local _ = { y };', client = 'local _ = { x };' },
    },
    {
        -- A same-named local in the selected arm does not capture the kept reference.
        text = 'local x = 1\nif SERVER then local x = 2; print(x) else print(x) end',
        server = 3, client = 2, keeps = { server = 'end local _ = { x };' },
    },
    {
        -- References after a returning arm stay outside its block, without unreachable code.
        text = 'local x = 1\nif CLIENT then return x end\nprint(x)\ng()',
        server = 4, client = 3, keeps = { client = 'local _ = { x };' },
    },
    { text = 'if SERVER and ready() then unknown() end', unchanged = true },
    { text = 'local SERVER = false\nif SERVER then unknown() end', unchanged = true },
}
for _, realm in ipairs { 'server', 'client' } do
    assert(loadfile(pluginPath))(nil, root, { realm })
    for index, example in ipairs(examples) do
        local before = assert(parser.compile(example.text, 'Lua', 'LuaJIT'))
        assert(#before.errs == 0, 'invalid regression input')
        local diffs = OnSetText(root .. '/lua/splashsweps/shared/__parser_check.lua', example.text)
        local text = diffs and merger.mergeDiff(example.text, diffs) or example.text
        local after = assert(parser.compile(text, 'Lua', 'LuaJIT'))
        assert(#after.errs == 0, realm .. ' example ' .. index .. ': introduced syntax errors\n' .. text)
        if example.unchanged then
            assert(text == example.text, 'changed an unsupported condition')
        else
            assert(#after.ast == example[realm], realm .. ' example ' .. index .. ': changed statement boundaries\n' .. text)
            local keep = example.keeps and example.keeps[realm]
            assert(not keep or text:find(keep, 1, true), realm .. ' example ' .. index .. ': lost outer reference\n' .. text)
        end
        print('PASS parser', realm, index)
    end
end
