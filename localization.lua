-- Standalone localization: follows Balatro without requiring Steamodded.
local Localization = {}
local supported = {
    ['en-us']=true, ru=true, de=true, fr=true, it=true, nl=true, pl=true,
    pt_BR=true, es_ES=true, es_419=true, id=true, ja=true, ko=true,
    zh_CN=true, zh_TW=true,
}
local english = require('Mods.BalatroBuzz.localization.en-us')
local cache = {['en-us']=english}

function Localization.language()
    local language = G and G.SETTINGS and G.SETTINGS.language
    return supported[language] and language or 'en-us'
end

function Localization.get(key, values)
    local language = Localization.language()
    if not cache[language] then
        cache[language] = require('Mods.BalatroBuzz.localization.'..language)
    end
    local text = cache[language][key] or english[key] or key
    -- Function replacements keep '%' in server error details literal.
    return (text:gsub('{([%w_]+)}', function(name)
        if values and values[name] ~= nil then return tostring(values[name]) end
        return '{'..name..'}'
    end))
end

return Localization
