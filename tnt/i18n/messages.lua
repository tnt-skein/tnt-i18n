--- Строки одного языка: дерево из файла — в плоский словарь по ключам.
---
--- Строки пишут деревом, потому что так их удобно держать по разделам:
---
---     { home = { title = 'Главная', nodes = { '{count} узел', '{count} узла', '{count} узлов' } } }
---
--- а ищут по полному ключу — `home.title`. Список строк — формы слова при
--- числе, словарь — раздел. Ключ можно записать и целиком, с точками:
--- `['home.title'] = 'Главная'` — это тот же ключ, и два его объявления
--- в одном языке — ошибка, а не тихая подмена одного другим.
---
--- Здесь не бросают: разбор отдаёт жалобу строкой, а бросает сборка
--- переводов — с местом вызывающего либо без места, как решит тот,
--- кто её зовёт (`i18n.explain`).

local kind = require('tnt.must.fail').kind

local Module = {}

--- Подстановка в строке: `{имя}`. Имя начинается с буквы или цифры:
--- пустые фигурные скобки — это просто скобки.
Module.PLACEHOLDER = '{(%w[%w_]*)}'

--- Список ли это — формы слова при числе — или раздел.
---
--- Пустая таблица — пустой раздел: форм без единой формы не бывает,
--- а раздел без строк безвреден.
---@param value table
---@return boolean
local function listed(value)
    local count = 0

    for _ in pairs(value) do
        count = count + 1
    end

    return count > 0 and count == #value
end

--- Жалоба о формах слова, если они негодны.
---@param forms table
---@return string|nil
local function wrong_forms(forms)
    for place, form in ipairs(forms) do
        if type(form) ~= 'string' then
            return ('форма %d — строка, а не %s'):format(place, kind(form))
        end
    end

    return nil
end

--- Раскладывает раздел в плоский словарь.
---@param flat table<string, string|string[]> Куда класть
---@param prefix string Ключ раздела с точкой на конце либо пусто
---@param tree table Раздел
---@param language string Язык — для текста жалобы
---@return string|nil complaint
local function spread(flat, prefix, tree, language)
    for name, value in pairs(tree) do
        if type(name) ~= 'string' or name == '' then
            return ('строки языка %s: ключ %s? — непустая строка, а не %s'):format(
                language,
                prefix,
                name == '' and 'пустая' or kind(name)
            )
        end

        local key = prefix .. name

        if type(value) == 'table' and not listed(value) then
            local complaint = spread(flat, key .. '.', value, language)

            if complaint ~= nil then
                return complaint
            end
        elseif flat[key] ~= nil then
            return ('строки языка %s: ключ %s задан дважды'):format(language, key)
        elseif type(value) == 'table' then
            local complaint = wrong_forms(value)

            if complaint ~= nil then
                return ('строки языка %s: %s — %s'):format(language, key, complaint)
            end

            flat[key] = value
        elseif type(value) == 'string' then
            flat[key] = value
        else
            return ('строки языка %s: %s — строка либо список форм, а не %s'):format(
                language,
                key,
                kind(value)
            )
        end
    end

    return nil
end

--- Плоский словарь строк языка по дереву.
---@param tree table Строки языка деревом
---@param language string Язык — для текста жалобы
---@return table<string, string|string[]>|nil flat
---@return string|nil complaint
function Module.flatten(tree, language)
    if type(tree) ~= 'table' or listed(tree) then
        return nil,
            ('строки языка %s — словарь, а не %s'):format(
                language,
                type(tree) == 'table' and 'список' or kind(tree)
            )
    end

    local flat = {}
    local complaint = spread(flat, '', tree, language)

    if complaint ~= nil then
        return nil, complaint
    end

    return flat, nil
end

--- Имена подстановок строки либо всех её форм — множеством.
---@param entry string|string[]
---@return table<string, boolean>
function Module.placeholders(entry)
    local names = {}
    local texts = type(entry) == 'table' and entry or { entry }

    for _, text in ipairs(texts) do
        for name in text:gmatch(Module.PLACEHOLDER) do
            names[name] = true
        end
    end

    return names
end

--- Подставляет значения в строку.
---
--- Подстановка, для которой значения не передали, остаётся в строке как
--- есть: «Клиента №{id} нет» сразу говорит, что забыли `id`, а «Клиента
--- № нет» выглядит законченной фразой и доживает до выкладки.
---@param text string
---@param params table
---@return string
function Module.fill(text, params)
    return (
        text:gsub(Module.PLACEHOLDER, function(name)
            local value = params[name]

            if value == nil then
                return nil
            end

            return tostring(value)
        end)
    )
end

return Module
