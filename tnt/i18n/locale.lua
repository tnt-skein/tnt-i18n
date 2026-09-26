--- Метки языка: запись по форме, цепочка отступления и выбор языка
--- по заголовку `Accept-Language`.
---
--- Метка — по BCP 47 (RFC 5646): язык, за ним через дефис письменность,
--- область и прочее — `ru`, `en-GB`, `sr-Latn-RS`. Регистр у частей свой:
--- язык строчными, письменность с прописной, область прописными. Сравнивать
--- метки иначе чем в этой записи нельзя — `en-gb` и `en-GB` одно и то же,
--- и каталог, заведённый под одной записью, не нашёлся бы под другой.
--- Подчёркивание вместо дефиса принимается: `ru_RU` приходит из имён
--- локалей системы.
---
--- Язык выбирается поиском из RFC 4647 (§3.4): от самой длинной метки
--- к короткой, отрезая по части с конца. `en-GB` находит каталог `en`,
--- а `en` каталога `en-GB` не находит: язык без области говорит «любой
--- английский», и выбрать за человека британский было бы догадкой.
--- Поэтому каталог, общий для всех областей, заводят под языком без
--- области.
---
--- Заголовок пишет клиент, и отказа по нему нет: негодная часть
--- пропускается, заголовок длиннее предела не читается вовсе, а когда
--- не подошло ничего — берётся язык по умолчанию.

local Module = {}

--- Предел длины заголовка, байт. Браузеры шлют десятки байт; длинный
--- заголовок читать незачем, а разбор его стоил бы работы на каждом запросе.
---@type integer
Module.MAX_HEADER = 1024

--- Сколько языков заголовка читается. Остальные отбрасываются: человек
--- называет два-три языка, и сотый уже ничего не решает.
---@type integer
Module.MAX_RANGES = 16

--- Любой язык в заголовке.
Module.ANY = '*'

--- Часть метки после языка: буквы и цифры, от одного до восьми знаков.
local SUBTAG = '^%w%w?%w?%w?%w?%w?%w?%w?$'

--- Язык: две или три латинские буквы.
local LANGUAGE = '^%a%a%a?$'

--- Вес языка, который назвали без `q`: по RFC 9110 это единица, и больше
--- веса не бывает.
local FULL = 1

--- Вес «этот язык не подходит».
local REFUSED = 0

--- Запись перечня: имя языка и его параметры одной выборкой. Параметры —
--- всё до следующей запятой, вместе с самой точкой с запятой.
local ENTRY = '([^,;%s]+)([^,]*)'

--- Вес в параметрах записи: `;q=0.9`.
local WEIGHT = ';%s*q%s*=%s*([^;%s]*)'

--- Запись веса: цифра, точка и не больше трёх цифр за ней (RFC 9110,
--- §12.4.2). Что вес не больше единицы, проверяется числом.
local QVALUE = '^%d%.?%d?%d?%d?$'

--- Часть метки в своём регистре.
---
--- Язык — строчными, письменность — четыре буквы сразу за языком —
--- с прописной, область — две буквы — прописными. Три цифры области
--- (`es-419`) регистра не имеют, прочие части пишутся строчными.
---@param part string
---@param place integer Место части в метке, язык — первое
---@return string
local function cased(part, place)
    if place == 1 then
        return part:lower()
    end

    if place == 2 and part:match('^%a%a%a%a$') ~= nil then
        return (part:lower():gsub('^%a', string.upper))
    end

    if part:match('^%a%a$') ~= nil then
        return part:upper()
    end

    return part:lower()
end

--- Метка по форме либо nil, если это не метка.
---
---     normalize('EN_gb')  --> 'en-GB'
---     normalize('english') --> nil
---@param tag any
---@return string|nil
function Module.normalize(tag)
    if type(tag) ~= 'string' then
        return nil
    end

    -- Пустая часть между двумя разделителями и в конце видна как пустая
    -- строка и отвергается проверкой части.
    local parts = tag:gsub('_', '-'):split('-')
    -- Первая часть есть всегда: `split` пустой строки отдаёт одну пустую.
    local language = parts[1] --[[@as string]]

    if language:match(LANGUAGE) == nil then
        return nil
    end

    for place, part in ipairs(parts) do
        if part:match(SUBTAG) == nil then
            return nil
        end

        parts[place] = cased(part, place)
    end

    return table.concat(parts, '-')
end

--- Цепочка отступления: сама метка и все её укорочения.
---
---     chain('zh-Hant-TW')  --> { 'zh-Hant-TW', 'zh-Hant', 'zh' }
---
--- Одиночный знак — начало расширения (`x-…`) — без того, что за ним,
--- смысла не имеет и отрезается вместе со следующей частью (RFC 4647).
---@param tag string Метка по форме
---@return string[]
function Module.chain(tag)
    local parts = tag:split('-')
    local chain = {}

    for last = #parts, 1, -1 do
        if #parts[last] > 1 then
            table.insert(chain, table.concat(parts, '-', 1, last))
        end
    end

    return chain
end

--- Вес языка по параметрам записи: число либо nil, если записан негодно.
---
--- Негодный вес — `q=абв`, `q=1.5`, `q=` — делает негодной всю запись:
--- гадать, что клиент имел в виду, незачем, у него есть и другие языки.
---@param params string Параметры записи: всё после имени языка
---@return number|nil
local function weight(params)
    local said = params:lower():match(WEIGHT)

    if said == nil then
        return FULL
    end

    local q = said:match(QVALUE) and tonumber(said)

    if not q or q > FULL then
        return nil
    end

    return q
end

--- Ставит язык в список по убыванию веса: после всех, чей вес не меньше.
---
--- Вставкой, а не `table.sort`: сортировка в Lua неустойчива, а при
--- равном весе решает порядок записи — первым назван, первым и выбран.
---@param ranges { tag: string, q: number }[]
---@param range { tag: string, q: number }
local function placed(ranges, range)
    local at = #ranges + 1

    -- Пока `at` больше единицы, перед ним есть язык: список сплошной.
    while
        at > 1 and (ranges[at - 1] --[[@as { q: number }]]).q < range.q
    do
        at = at - 1
    end

    table.insert(ranges, at, range)
end

--- Языки заголовка по убыванию веса; при равном весе — в порядке записи.
---
---     parse('en-GB,en;q=0.8,ru;q=0.9')
---     --> { { tag = 'en-GB', q = 1 }, { tag = 'ru', q = 0.9 }, { tag = 'en', q = 0.8 } }
---@param header any Значение заголовка `Accept-Language`
---@return { tag: string, q: number }[]
function Module.parse(header)
    if type(header) ~= 'string' or #header > Module.MAX_HEADER then
        return {}
    end

    local ranges = {}

    for name, params in header:gmatch(ENTRY) do
        local q = weight(params)
        local tag = name == Module.ANY and Module.ANY or Module.normalize(name)

        -- Вес ноль — «этот язык не подходит»: такой язык не выбирается.
        if q ~= nil and q ~= REFUSED and tag ~= nil and #ranges < Module.MAX_RANGES then
            placed(ranges, { tag = tag, q = q })
        end
    end

    return ranges
end

--- Язык из объявленных, лучший для заголовка, либо язык по умолчанию.
---
--- `*` значит «любой», и лучший из любых — язык по умолчанию: он и
--- выбирается, если раньше звёздочки не нашлось ничего.
---@param header any Значение заголовка `Accept-Language`
---@param available table<string, any> Объявленные языки: метка по форме — ключ
---@param default string|nil Язык по умолчанию; пусто — nil, когда не подошло ничего
---@return string|nil
function Module.negotiate(header, available, default)
    for _, range in ipairs(Module.parse(header)) do
        if range.tag == Module.ANY then
            return default
        end

        for _, tag in ipairs(Module.chain(range.tag)) do
            if available[tag] ~= nil then
                return tag
            end
        end
    end

    return default
end

return Module
