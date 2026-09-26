--- Слой языка запроса: выбор языка, контекст на остаток цепочки
--- и заголовки ответа.
---
--- Слой собирает переводчик (`lang:layer(opts)`) — он и проверяет
--- настройки на строке вызывающего, — а здесь то, что делается на каждом
--- запросе. Язык кладётся в контекст файбера (`tnt-context`, ключ
--- `locale`), и строки из любой глубины — обработчик, шаблон, проверка
--- формы — говорят на языке запроса без аргумента. По выходе из слоя,
--- в любом исходе, действует прежний контекст: файбер соединения
--- обслуживает и следующий запрос, и язык первого ему не достаётся.
---
--- Тот же язык ложится и в сам запрос, полем `locale`. Контекст кончается
--- вместе со слоем, а отказ парой `nil, err` проходит слой насквозь,
--- и рисует его обработчик отказов уже снаружи — там, где контекста
--- с языком нет. Запрос же доезжает до обработчика отказов вторым
--- аргументом, и слово отказа находит язык в нём.

local context = require('tnt.context')

local locale = require('tnt.i18n.locale')

local Module = {}

--- Ключ контекста с языком запроса.
Module.CONTEXT_KEY = 'locale'

--- Поле запроса с языком запроса: для того, кто рисует ответ вне слоя.
Module.REQUEST_KEY = 'locale'

--- Метка языка по BCP 47 редко длиннее двух десятков знаков; предел
--- с запасом держит контекст от случайно положенного текста.
Module.CONTEXT_MAX = 64

-- В журнал язык не пишется: он виден по заголовку запроса и ничего
-- не говорит о том, что сломалось. За границу процесса не едет: соседний
-- узел отвечает данными, а не словами, и язык выбирает тот, кто рисует.
context.declare(Module.CONTEXT_KEY, { log = false, max = Module.CONTEXT_MAX })

--- Заголовки ответа, которые ставит слой.
Module.CONTENT_LANGUAGE = 'content-language'
Module.VARY = 'vary'

--- Заголовок запроса, по которому выбирается язык.
Module.ACCEPT_LANGUAGE = 'accept-language'

--- Как заголовок запроса называется в `Vary`.
local VARY_BY = 'Accept-Language'

--- Язык запроса: выбранный человеком явно либо по заголовку.
---@param translator TntI18n
---@param request any
---@param from (fun(request: any): string|nil)|nil
---@return string
local function picked(translator, request, from)
    local asked = from ~= nil and from(request) or nil
    -- Явный выбор ищется так же, как язык заголовка: `en-GB` из куки
    -- найдёт строки `en`, а негодная метка просто не выберется.
    local chosen = locale.negotiate(asked, translator.catalogs, nil)

    if chosen ~= nil then
        return chosen
    end

    local headers = type(request) == 'table' and request.headers or nil
    local header = type(headers) == 'table' and headers[Module.ACCEPT_LANGUAGE] or nil

    return translator:negotiate(header)
end

--- `Vary` ответа с заголовком языка.
---
--- Ответ, выбранный по `Accept-Language`, кэш обязан хранить по языку,
--- иначе второй посетитель получит страницу на языке первого. Звёздочка
--- уже говорит «по всему», а названный заголовок второй раз не пишется.
---@param vary any
---@return any
local function varied(vary)
    if vary == nil then
        return VARY_BY
    end

    if type(vary) ~= 'string' then
        return vary
    end

    for _, name in ipairs(vary:split(',')) do
        local said = name:strip():lower()

        if said == Module.ACCEPT_LANGUAGE or said == '*' then
            return vary
        end
    end

    return vary .. ', ' .. VARY_BY
end

--- Ставит ответу язык и `Vary`.
---
--- Ответ не таблицей или заголовки не таблицей — ставить некуда, и ответ
--- уходит как есть. Язык, поставленный обработчиком, остаётся: ему виднее,
--- на каком языке он ответил.
---@param response any
---@param chosen string
local function annotate(response, chosen)
    if type(response) ~= 'table' then
        return
    end

    local headers = response.headers or {}

    if type(headers) ~= 'table' then
        return
    end

    if headers[Module.CONTENT_LANGUAGE] == nil then
        headers[Module.CONTENT_LANGUAGE] = chosen
    end

    headers[Module.VARY] = varied(headers[Module.VARY])
    response.headers = headers
end

--- Слой по договору `tnt-middleware`: запрос и остаток цепочки.
---@param translator TntI18n
---@param from (fun(request: any): string|nil)|nil Явный выбор языка
---@return fun(request: any, next_layer: fun(request: any): any, any): any, any
function Module.new(translator, from)
    return function(request, next_layer)
        local chosen = picked(translator, request, from)

        -- Запрос не таблицей — класть некуда, а в контексте язык и так есть.
        if type(request) == 'table' then
            request[Module.REQUEST_KEY] = chosen
        end

        local response, failure = context.run({ [Module.CONTEXT_KEY] = chosen }, next_layer, request)

        annotate(response, chosen)

        return response, failure
    end
end

return Module
