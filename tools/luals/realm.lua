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

    -- Local references with their declaration offsets, ordered by position.
    local localRefs
    local function allLocalRefs()
        if not localRefs then
            localRefs = {}
            guide.eachSourceType(state.ast, 'getlocal', function (ref)
                if ref.node then
                    localRefs[#localRefs + 1] = {
                        offset(ref.start) + 1, offset(ref.finish), offset(ref.node.start) + 1,
                    }
                end
            end)
            table.sort(localRefs, function (a, b) return a[1] < b[1] end)
        end
        return localRefs
    end

    -- References in removed text to locals declared outside it, at their original
    -- offsets. Keeping them marks a local used by either realm as used in both, and
    -- the identifiers still map to their original source positions.
    local function outerReferences(first, last)
        local all = allLocalRefs()
        local low, high = 1, #all + 1
        while low < high do
            local middle = math.floor((low + high) / 2)
            if all[middle][1] < first then
                low = middle + 1
            else
                high = middle
            end
        end
        local refs = {}
        for index = low, #all do
            local ref = all[index]
            if ref[1] > last then
                break
            end
            if ref[2] <= last and (ref[3] < first or ref[3] > last) then
                refs[#refs + 1] = ref
            end
        end
        return refs
    end

    local function newlines(first, last)
        return (text:sub(first, last):gsub('[^\r\n]', ''))
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

    -- Replaces removed text with `prefix local _ = { a, b }; suffix`, keeping
    -- references to outer locals in place. One local per removed range keeps within
    -- the parser's local limit; `;` ends the statement before a following
    -- parenthesized call; line breaks go before inserted words to avoid trailing space.
    local function replace(first, last, prefix, refs, suffix)
        prefix = prefix and ' ' .. prefix or ''
        suffix = suffix and ' ' .. suffix or ''
        local cursor = first
        if prefix == '' and newlines(first, (refs[1] and refs[1][1] or last + 1) - 1) ~= '' then
            -- The line holding the removed text would be left with indentation only.
            while cursor > 1 and text:sub(cursor - 1, cursor - 1):match('[ \t]') do
                cursor = cursor - 1
            end
        end
        for index, ref in ipairs(refs) do
            local before = index == 1 and prefix or ','
            diffs[#diffs + 1] = {
                start = cursor, finish = ref[1] - 1,
                text = before .. newlines(cursor, ref[1] - 1) .. (index == 1 and ' local _ = { ' or ' '),
            }
            cursor = ref[2] + 1
        end
        local separator = #refs > 0 and ' };' or prefix
        local rest = separator .. newlines(cursor, last) .. suffix
        if text:sub(last + 1, last + 1):match('[%w_]') then
            -- Keep an inserted keyword apart from an immediately following one.
            rest = rest .. '\n'
        end
        diffs[#diffs + 1] = { start = cursor, finish = last, text = rest ~= '' and rest or '\n' }
    end

    local visited = {}
    local visit
    local function visitIf(node, parent, index)
        local firstArm = node[1]
        local value = realmCondition(firstArm)
        if value == nil then
            for _, arm in ipairs(node) do
                visit(arm)
            end
            return false
        end

        local head = offset(node.start) + 1
        local selected
        if value then
            selected = firstArm
        elseif node[2] and node[2].type == 'elseblock' then
            selected = node[2]
        elseif node[2] then
            local nextArm = node[2]
            replace(head, offset(nextArm.start), nil, outerReferences(head, offset(nextArm.start)))
            -- Retain the remaining chain verbatim, even when its condition is compound.
            blank(offset(nextArm.keyword[1]) + 1, offset(nextArm.keyword[2]), 'if')
            for arm = 2, #node do
                visit(node[arm])
            end
            return false
        else
            local refs = outerReferences(head, offset(node.finish))
            if #refs > 0 then
                replace(head, offset(node.finish), nil, refs)
            else
                -- Lua newlines do not separate statements before a parenthesized call.
                blank(head, offset(node.finish), ';')
            end
            return false
        end

        -- A do block retains the arm's local scope without a conditional return path.
        -- It ends before the kept references of the removed arms, so they bind to the
        -- outer locals even when the selected arm declares the same names.
        local lastStatement = selected[#selected]
        local returns = lastStatement ~= nil and lastStatement.type == 'return'
        -- After a return, the rest of the enclosing block is unreachable in this realm.
        local siblings = returns and parent and parent[index + 1]
        local bodyFirst, bodyLast = offset(selected.bstart), offset(selected.bfinish) + 1
        local tailLast = siblings and offset(parent.bfinish) or offset(node.finish)
        local before = selected == firstArm and {} or outerReferences(head, bodyFirst)
        if #before > 0 then
            replace(head, bodyFirst, nil, before, 'do')
        else
            blank(head, bodyFirst, 'do')
        end
        -- LuaLS does not mark a do block as returning, so the references may follow it.
        replace(bodyLast, tailLast, 'end', outerReferences(bodyLast, tailLast))
        visit(selected)
        return returns
    end

    visit = function(node, parent, index)
        if not node or visited[node] then
            return false
        end
        -- Multi-assignment select nodes can share their right-hand expression.
        visited[node] = true
        if node.type == 'if' then
            return visitIf(node, parent, index)
        end

        local statementIndex = 1
        local stopped = false
        local isBlock = guide.blockTypes[node.type]
        guide.eachChild(node, function(child)
            if not child then
                return
            end
            if isBlock and child == node[statementIndex] then
                local current = statementIndex
                statementIndex = statementIndex + 1
                if stopped then
                    return
                end
                -- A returning realm branch has already removed the following statements.
                stopped = visit(child, node, current)
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
