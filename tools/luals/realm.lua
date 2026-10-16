-- LuaLS loads plugins as (chunk, uri, runtime.pluginArgs).
local _, bootstrapUri, args = ...
local realm = args and args[1]
assert(realm == 'server' or realm == 'client', 'realm.lua expects server or client')

local parser = require 'parser'
local guide = parser.guide
local config = require 'config'
local utility = require 'utility'
local fileUri = require 'file-uri'
local platform = require 'bee.platform'
local glob = require 'glob'

local function normalizedPath(uri)
    local path = fileUri.decode(uri):gsub('\\', '/')
    if platform.os == 'windows' then
        path = path:lower()
    end
    return path
end

local rootPrefix = normalizedPath(bootstrapUri):gsub('/+$', '') .. '/'
local ignorePatterns
local ignoreMatcher

local function projectPath(uri)
    if uri:sub(1, 5) ~= 'file:' then
        return nil
    end
    local path = normalizedPath(uri)
    if path:sub(1, #rootPrefix) == rootPrefix then
        return path:sub(#rootPrefix + 1)
    end
end

local function isIgnored(relative)
    local patterns = config.get(bootstrapUri, 'Lua.workspace.ignoreDir')
    if patterns ~= ignorePatterns then
        ignorePatterns = patterns
        -- Use the same pattern semantics as workspace preloading, without .gitignore.
        ignoreMatcher = glob.gitignore(patterns, { ignoreCase = platform.os == 'windows' })
    end
    return ignoreMatcher(relative)
end

local function realmCondition(arm)
    local condition = arm.filter
    if not condition or condition.type ~= 'getglobal' then
        return nil
    end
    if condition[1] == 'SERVER' then
        return realm == 'server'
    elseif condition[1] == 'CLIENT' then
        return realm == 'client'
    end
end

function OnSetText(uri, text)
    local relative = projectPath(uri)
    if not relative or relative == 'lua/types' or relative:sub(1, 10) == 'lua/types/' then
        return
    end
    if relative:sub(1, 4) ~= 'lua/' or isIgnored(relative) then
        if #text > 0 then
            return { { start = 1, finish = #text, text = '' } }
        end
        return
    end
    if not text:find('SERVER', 1, true) and not text:find('CLIENT', 1, true) then
        return
    end

    local state = parser.compile(text, 'Lua', config.get(uri, 'Lua.runtime.version'), {
        special = config.get(uri, 'Lua.runtime.special'),
        unicodeName = config.get(uri, 'Lua.runtime.unicodeName'),
        nonstandardSymbol = utility.arrayToHash(config.get(uri, 'Lua.runtime.nonstandardSymbol')),
    })
    -- Never hide an original parser error, including errors in an inactive arm.
    if not state or not state.ast or #state.errs > 0 then
        return
    end

    local diffs = {}
    local function offset(position)
        return guide.positionToOffset(state, position)
    end
    local function blank(first, last, keyword)
        if first > last then
            return
        end
        local removed = text:sub(first, last)
        local replacement = removed:gsub('[^\r\n]', '')
        -- Diff mapping preserves positions; a newline also separates same-line tokens.
        if replacement == '' then
            replacement = '\n'
        end
        if keyword then
            replacement = keyword .. replacement
        elseif removed:match('^[^\r\n]*[^ \t\r\n]') then
            -- Only trim a separator made trailing by this deletion, not original trailing space.
            while first > 1 and text:sub(first - 1, first - 1):match('[ \t]') do
                first = first - 1
            end
        end
        diffs[#diffs + 1] = { start = first, finish = last, text = replacement }
    end

    local visited = {}
    local visit
    local function visitIf(node)
        local firstArm = node[1]
        local value = realmCondition(firstArm)
        if value == nil then
            for _, arm in ipairs(node) do
                visit(arm)
            end
            return false
        end

        local selected
        if value then
            selected = firstArm
        elseif node[2] and node[2].type == 'elseblock' then
            selected = node[2]
        elseif node[2] then
            local nextArm = node[2]
            blank(offset(node.start) + 1, offset(nextArm.start))
            -- Retain the remaining chain verbatim, even when its condition is compound.
            blank(offset(nextArm.keyword[1]) + 1, offset(nextArm.keyword[2]), 'if')
            for index = 2, #node do
                visit(node[index])
            end
            return false
        else
            -- Lua newlines do not separate statements before a parenthesized call.
            blank(offset(node.start) + 1, offset(node.finish), ';')
            return false
        end

        -- A do block retains the arm's local scope without a conditional return path.
        blank(offset(node.start) + 1, offset(selected.bstart), 'do')
        blank(offset(selected.bfinish) + 1, offset(node.finish) - 3)
        visit(selected)
        local lastStatement = selected[#selected]
        return lastStatement ~= nil and lastStatement.type == 'return'
    end

    visit = function(node)
        if not node or visited[node] then
            return false
        end
        -- Multi-assignment select nodes can share their right-hand expression.
        visited[node] = true
        if node.type == 'if' then
            return visitIf(node)
        end

        local statementIndex = 1
        local stopped = false
        local isBlock = guide.blockTypes[node.type]
        guide.eachChild(node, function(child)
            if not child then
                return
            end
            if isBlock and child == node[statementIndex] then
                local index = statementIndex
                statementIndex = statementIndex + 1
                if stopped then
                    return
                end
                if visit(child) and node[index + 1] then
                    -- Only sibling statements: never the enclosing end/else or function.
                    -- Assignment nodes can end at the name; bfinish includes their values.
                    blank(offset(child.finish) + 1, offset(node.bfinish))
                    stopped = true
                end
            else
                visit(child)
            end
        end)
        return false
    end

    visit(state.ast)
    if #diffs > 0 then
        return diffs
    end
end
