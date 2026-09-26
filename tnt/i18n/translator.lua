--- Переводчик: строки по языкам, язык запроса, подстановки и формы слова
--- при числе.
---
--- Язык, на котором говорит запрос, лежит в контексте файбера
--- (`tnt-context`, ключ `locale`): его кладёт слой `layer` на входе
--- роутера, а читают его `get` и `choice` из любой глубины — из
--- обработчика, из шаблона, из проверки формы, — и передавать язык
--- аргументом через все слои не нужно. Вне запроса — фоновая работа,
--- консоль, проверка — языка в контексте нет, и берётся язык
--- по умолчанию; нужный язык там называют аргументом.
---
--- Строки, которой нет в языке запроса, ищут в укороченной метке
--- (`en-GB` → `en`), а потом в языке по умолчанию: пусть лучше
--- по-русски, чем никак. Ключ, которого нет нигде, возвращается сам —
--- `home.title` на странице сразу видно, а пустое место выглядит
--- законченной страницей и доживает до выкладки. Полноту переводов
--- сверяет `diff` в проверках приложения.

local context = require('tnt.context')
local must = require('tnt.must')
local show = require('tnt.must.fail').show

local layered = require('tnt.i18n.layer')
local locale = require('tnt.i18n.locale')
local messages = require('tnt.i18n.messages')
local plural = require('tnt.i18n.plural')

local Module = {}

--- Ключ контекста с языком запроса.
Module.CONTEXT_KEY = layered.CONTEXT_KEY

--- Настройки переводчика.
local OPTIONS = {
    locale = 'string',
    messages = 'table',
    plurals = '?table',
}

--- Правило множественного числа из настроек.
local RULE = {
    forms = { 'between', 1, plural.MAX_FORMS },
    form = 'callable',
}

--- Настройки слоя.
local LAYER = { from = '?callable' }

---@class TntI18nOptions
---@field locale string Язык по умолчанию: его строки — последняя надежда
---@field messages table<string, table> Строки деревом по языкам
---@field plurals table<string, TntI18nRule>|nil Правила множественного числа сверх встроенных

---@class TntI18nLayerOptions
---@field from (fun(request: any): string|nil)|nil Язык, выбранный человеком явно: из куки, сессии, профиля

---@class TntI18nDiff
---@field missing string[] Ключи языка по умолчанию, которых в языке нет
---@field extra string[] Ключи языка, которых нет в языке по умолчанию
---@field mismatched string[] Ключи, у которых подстановки расходятся с языком по умолчанию

---@class TntI18n
---@field default string Язык по умолчанию
---@field catalogs table<string, table<string, string|string[]>> Строки по языкам, плоско
---@field rules table<string, TntI18nRule> Правила множественного числа по языкам
local Translator = {}
Translator.__index = Translator

--- Жалоба о метке, записанной не по форме, либо nil.
---@param tag any
---@param what string Что это за метка — для текста жалобы
---@return string|nil
local function unshaped(tag, what)
    local shaped = locale.normalize(tag)

    if shaped == tag then
        return nil
    end

    if shaped == nil then
        return ('%s %s — не метка языка: ждали вид ru либо en-GB'):format(what, show(tag))
    end

    return ('%s %s записан не по форме: пишите %s'):format(what, show(tag), shaped)
end

--- Правило множественного числа языка: по самой метке либо по укороченной.
---@param rules table<string, TntI18nRule>
---@param tag string
---@return TntI18nRule|nil
local function rule_of(rules, tag)
    for _, candidate in ipairs(locale.chain(tag)) do
        if rules[candidate] ~= nil then
            return rules[candidate]
        end
    end

    return nil
end

--- Ключи таблицы по алфавиту.
---@param map table
---@return string[]
local function sorted(map)
    local names = {}

    for name in pairs(map) do
        names[#names + 1] = name
    end

    table.sort(names)

    return names
end

--- Правила множественного числа: встроенные и из настроек поверх них.
---@param declared table<string, TntI18nRule>|nil
---@return table<string, TntI18nRule>|nil rules
---@return string|nil complaint
local function rules_of(declared)
    local rules = {}

    for tag, rule in pairs(plural.BUILTIN) do
        rules[tag] = rule
    end

    for tag, rule in pairs(declared or {}) do
        local complaint = unshaped(tag, 'язык правила множественного числа')
            or must.explain.options(
                rule,
                ('правило множественного числа %s'):format(tag),
                RULE
            )

        if complaint ~= nil then
            return nil, complaint
        end

        rules[tag] = rule
    end

    return rules, nil
end

--- Жалоба о строке одного языка, если она расходится с правилом
--- или с тем, как тот же ключ записан в другом языке.
---@param kinds table<string, { listed: boolean, tag: string }> Как ключ записан в языках до этого
---@param rule TntI18nRule|nil
---@param tag string
---@param key string
---@param entry string|string[]
---@return string|nil
local function wrong_entry(kinds, rule, tag, key, entry)
    local listed = type(entry) == 'table'

    if listed then
        if rule == nil then
            return ('строка %s языка %s — формы при числе, а правила множественного числа у языка нет: '):format(
                key,
                tag
            ) .. 'задайте его настройкой plurals'
        end

        if #entry ~= rule.forms then
            return ('строка %s языка %s: форм %d, а у языка их %d'):format(
                key,
                tag,
                #entry,
                rule.forms
            )
        end
    end

    local seen = kinds[key]

    if seen == nil then
        kinds[key] = { listed = listed, tag = tag }
    elseif seen.listed ~= listed then
        return ('строка %s — формы при числе в языке %s и одна строка в языке %s'):format(
            key,
            seen.listed and seen.tag or tag,
            seen.listed and tag or seen.tag
        )
    end

    return nil
end

--- Проверяет настройки и собирает переводчик либо называет, что не так.
---@param opts any
---@return TntI18n|nil
---@return string|nil complaint
local function prepared(opts)
    local complaint = must.explain.options(opts, 'настройки переводов', OPTIONS)
        or unshaped(opts.locale, 'язык по умолчанию')

    if complaint ~= nil then
        return nil, complaint
    end

    local rules, wrong = rules_of(opts.plurals)

    if rules == nil then
        return nil, wrong
    end

    -- Метки проверяются до сортировки: число среди ключей сортировку
    -- уронило бы, а сказать надо о метке.
    for tag in pairs(opts.messages) do
        local wrong_tag = unshaped(tag, 'язык строк')

        if wrong_tag ~= nil then
            return nil, wrong_tag
        end
    end

    local catalogs = {}
    local kinds = {}

    -- Языки по алфавиту: жалоба о ключе, записанном в двух языках
    -- по-разному, иначе называла бы их в случайном порядке.
    for _, tag in ipairs(sorted(opts.messages)) do
        local flat, why = messages.flatten(opts.messages[tag], tag)

        if flat == nil then
            return nil, why
        end

        local rule = rule_of(rules, tag)

        for key, entry in pairs(flat) do
            local bad = wrong_entry(kinds, rule, tag, key, entry)

            if bad ~= nil then
                return nil, bad
            end
        end

        catalogs[tag] = flat
    end

    if catalogs[opts.locale] == nil then
        return nil,
            ('языка по умолчанию %s среди строк нет: есть %s'):format(
                opts.locale,
                table.concat(sorted(catalogs), ', ')
            )
    end

    return setmetatable({ default = opts.locale, catalogs = catalogs, rules = rules }, Translator), nil
end

--- Собирает переводчик.
---
--- Негодные настройки — исключение на строке вызывающего: строки пишет
--- программист, и опечатка в них обязана найтись при сборке, а не
--- на первом запросе посетителя.
---@param opts TntI18nOptions
---@return TntI18n
function Module.new(opts)
    local translator, complaint = prepared(opts)

    if translator == nil then
        error(complaint, 2)
    end

    return translator
end

--- Что не так с настройками, словами, либо nil — без броска.
---
--- Для того, кто бросает сам и по-своему: раскладка приложения говорит
--- оператору текстом без места, и место внутри неё ему ничего не скажет.
---@param opts any
---@return string|nil
function Module.explain(opts)
    local _, complaint = prepared(opts)

    return complaint
end

--- Язык, на котором ищут: названный аргументом либо язык запроса.
---
--- Названный аргументом пишет программист, и негодная метка — бросок.
---@param self TntI18n
---@param tag string|nil
---@return string|nil language
---@return string|nil complaint
local function language_of(self, tag)
    if tag == nil then
        return self:locale(), nil
    end

    local shaped = locale.normalize(tag)

    if shaped == nil then
        return nil,
            ('язык %s — не метка языка: ждали вид ru либо en-GB'):format(show(tag))
    end

    return shaped, nil
end

--- Строка по ключу в цепочке языка — без языка по умолчанию.
---@param self TntI18n
---@param key string
---@param tag string
---@return string|string[]|nil entry
---@return string|nil where В каком языке нашлась
local function found(self, key, tag)
    for _, candidate in ipairs(locale.chain(tag)) do
        local catalog = self.catalogs[candidate]
        local entry = catalog and catalog[key]

        if entry ~= nil then
            return entry, candidate
        end
    end

    return nil
end

--- Строка по ключу: в цепочке языка, потом в языке по умолчанию.
---@param self TntI18n
---@param key string
---@param tag string
---@return string|string[]|nil entry
---@return string|nil where
local function lookup(self, key, tag)
    local entry, where = found(self, key, tag)

    if entry == nil then
        return found(self, key, self.default)
    end

    return entry, where
end

--- Язык запроса: из контекста либо по умолчанию.
---
--- Язык в контекст мог положить не слой, а кто угодно, поэтому негодная
--- метка там не роняет запрос: говорят на языке по умолчанию.
---@return string
function Translator:locale()
    return locale.normalize(context.get(Module.CONTEXT_KEY)) or self.default
end

--- Объявленные языки по алфавиту.
---@return string[]
function Translator:locales()
    return sorted(self.catalogs)
end

--- Строка по ключу с подстановками.
---
---     i18n:get('customer.not_found', { id = 7 })        --> 'Клиента №7 нет'
---     i18n:get('customer.not_found', { id = 7 }, 'en')  --> 'Customer 7 not found'
---@param key string
---@param params table|nil Подстановки по именам
---@param tag string|nil Язык; по умолчанию — язык запроса
---@return string
function Translator:get(key, params, tag)
    local caller = must.at(2)

    caller.string(key, 'ключ строки')
    caller.optional.table(params, 'подстановки')

    local language, wrong = language_of(self, tag)

    if language == nil then
        error(wrong, 2)
    end

    local entry = lookup(self, key, language)

    if entry == nil then
        return key
    end

    if type(entry) == 'table' then
        error(('строка %s — формы при числе: её берёт choice, а не get'):format(key), 2)
    end

    return messages.fill(entry, params or {})
end

--- Форма строки при числе с подстановками; число подставляется в `{count}`,
--- если своего `count` в подстановках нет.
---
---     i18n:choice('nodes', 5)        --> '5 узлов'
---     i18n:choice('nodes', 1, nil, 'en')  --> '1 node'
---
--- Форма выбирается правилом того языка, где строка нашлась: строка,
--- взятая из языка по умолчанию, согласуется с числом по его правилу.
---@param key string
---@param count number
---@param params table|nil
---@param tag string|nil
---@return string
function Translator:choice(key, count, params, tag)
    local caller = must.at(2)

    caller.string(key, 'ключ строки')
    caller.number(count, 'число')
    caller.optional.table(params, 'подстановки')

    if count == math.huge or count == -math.huge then
        error(('число — конечное число, а не %s'):format(tostring(count)), 2)
    end

    local language, wrong = language_of(self, tag)

    if language == nil then
        error(wrong, 2)
    end

    local entry, where = lookup(self, key, language)

    if entry == nil then
        return key
    end

    if type(entry) == 'string' then
        local refusal = ('строка %s — без форм при числе: её берёт get, а не choice'):format(
            key
        )

        error(refusal, 2)
    end

    -- Правило у языка со списком форм есть непременно: это сверила сборка.
    local rule = rule_of(self.rules, where --[[@as string]]) --[[@as TntI18nRule]]
    local form = rule.form(count)
    local text = entry[form]

    if text == nil then
        local refusal = ('правило множественного числа языка %s дало форму %s числу %s: ждали от 1 до %d'):format(
            where,
            show(form),
            tostring(count),
            rule.forms
        )

        error(refusal, 2)
    end

    local filled = { count = count }

    for name, value in pairs(params or {}) do
        filled[name] = value
    end

    return messages.fill(text, filled)
end

--- Есть ли строка в языке — без языка по умолчанию.
---@param key string
---@param tag string|nil Язык; по умолчанию — язык запроса
---@return boolean
function Translator:has(key, tag)
    local caller = must.at(2)

    caller.string(key, 'ключ строки')

    local language, wrong = language_of(self, tag)

    if language == nil then
        error(wrong, 2)
    end

    return (found(self, key, language)) ~= nil
end

--- Лучший из объявленных языков для заголовка `Accept-Language`.
---@param header any
---@return string
function Translator:negotiate(header)
    return locale.negotiate(header, self.catalogs, self.default) --[[@as string]]
end

--- Имя из первого множества, которого нет во втором, либо nil.
---@param left table<string, boolean>
---@param right table<string, boolean>
---@return string|nil
local function stray(left, right)
    for name in pairs(left) do
        if not right[name] then
            return name
        end
    end

    return nil
end

--- Сверка языка с языком по умолчанию: чего не хватает, что лишнее
--- и где разошлись подстановки.
---
--- Для проверок приложения: перевод, у которого пропала строка или
--- подстановка, иначе находят посетители.
---
---     t.assert_equals(i18n:diff('en'), { missing = {}, extra = {}, mismatched = {} })
---@param tag string Объявленный язык
---@return TntI18nDiff
function Translator:diff(tag)
    if self.catalogs[tag] == nil then
        local refusal = ('языка %s среди строк нет: есть %s'):format(
            show(tag),
            table.concat(self:locales(), ', ')
        )

        error(refusal, 2)
    end

    local base = self.catalogs[self.default]
    local report = { missing = {}, extra = {}, mismatched = {} }

    for _, key in ipairs(sorted(base)) do
        local entry = found(self, key, tag)
        local own = messages.placeholders(base[key])
        local theirs = entry and messages.placeholders(entry)

        if theirs == nil then
            table.insert(report.missing, key)
        elseif stray(own, theirs) or stray(theirs, own) then
            table.insert(report.mismatched, key)
        end
    end

    for _, key in ipairs(sorted(self.catalogs[tag])) do
        if base[key] == nil then
            table.insert(report.extra, key)
        end
    end

    return report
end

--- Слой языка запроса: выбирает язык и кладёт его в контекст на весь
--- остаток цепочки (`tnt.i18n.layer`).
---
--- Выбор — явный (`from`: кука, сессия, профиль), если он назван
--- и объявлен, иначе по заголовку `Accept-Language`, иначе язык
--- по умолчанию. Ответу-таблице слой ставит `Content-Language`
--- и `Vary: Accept-Language`; отказ парой проходит как есть — его рисует
--- обработчик отказов уже вне слоя.
---@param opts TntI18nLayerOptions|nil
---@return fun(request: any, next_layer: fun(request: any): any, any): any, any
function Translator:layer(opts)
    local caller = must.at(2)

    opts = opts or {}
    caller.options(opts, 'настройки слоя языка', LAYER)

    return layered.new(self, opts.from)
end

return Module
