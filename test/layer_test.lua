local t = require('luatest')

local helper = dofile('test/helper.lua')

local g = t.group('tnt.i18n.layer')

local i18n = helper.i18n
local context = helper.context

--- Запрос с заголовками по договору границы HTTP: имена строчными.
---@param headers table|nil
---@return table
local function request(headers)
    return { method = 'GET', path = '/', headers = headers or {} }
end

--- Проходит слой с обработчиком, который отвечает языком запроса
--- и строкой на нём.
---@param layer function
---@param incoming any
---@param response table|nil Что отдать; по умолчанию — таблица со строкой
---@return any response
---@return any failure
---@return table seen Что видел обработчик
local function passed(layer, incoming, response)
    local lang = g.lang
    local seen = {}

    local answer, failure = layer(incoming, function(inner)
        seen.request = inner
        seen.locale = lang:locale()
        seen.title = lang:get('home.title')

        return response or { status = 200, body = seen.title }
    end)

    return answer, failure, seen
end

g.before_each(function()
    g.lang = helper.sample()
end)

g.test_the_language_of_the_header_is_in_the_context_of_the_chain = function()
    local incoming = request({ ['accept-language'] = 'en-GB,en;q=0.8' })
    local answer, failure, seen = passed(g.lang:layer(), incoming)

    t.assert_equals(failure, nil)
    t.assert_is(seen.request, incoming)
    t.assert_equals(seen.locale, 'en-GB')
    -- Язык лежит и в самом запросе: за слоем контекста уже нет.
    t.assert_equals(i18n.REQUEST_KEY, 'locale')
    t.assert_equals(incoming.locale, 'en-GB')
    t.assert_equals(seen.title, 'Home page')
    t.assert_equals(answer, {
        status = 200,
        body = 'Home page',
        headers = { ['content-language'] = 'en-GB', vary = 'Accept-Language' },
    })

    -- За слоем язык запроса прежний.
    t.assert_equals(g.lang:locale(), 'ru')
    t.assert_equals(context.get(i18n.CONTEXT_KEY), nil)
end

g.test_without_a_suitable_header_the_default_is_chosen = function()
    for _, incoming in ipairs({
        request(),
        request({ ['accept-language'] = 'de' }),
        { headers = 'accept-language: en' },
        'не запрос',
    }) do
        local _, _, seen = passed(g.lang:layer(), incoming)

        t.assert_equals(seen.locale, 'ru')
    end
end

g.test_an_explicit_choice_beats_the_header = function()
    local asked = nil
    local layer = g.lang:layer({
        from = function(incoming)
            t.assert_equals(incoming.path, '/')

            return asked
        end,
    })
    local incoming = request({ ['accept-language'] = 'en' })

    for _, case in ipairs({
        { asked = 'en-GB', chosen = 'en-GB' },
        { asked = 'RU', chosen = 'ru' },
        { asked = 'en-AU', chosen = 'en' },
        { asked = 'de', chosen = 'en' },
        { asked = 'английский', chosen = 'en' },
        { asked = nil, chosen = 'en' },
    }) do
        asked = case.asked

        local _, _, seen = passed(layer, incoming)

        t.assert_equals(seen.locale, case.chosen, tostring(case.asked))
    end
end

g.test_the_headers_of_the_handler_are_kept = function()
    local cases = {
        { vary = 'Cookie', language = 'ru', expected = 'Cookie, Accept-Language' },
        { vary = 'accept-language', expected = 'accept-language' },
        { vary = 'Origin, Accept-Language ', expected = 'Origin, Accept-Language ' },
        { vary = '*', expected = '*' },
    }

    for _, case in ipairs(cases) do
        local headers = { vary = case.vary, ['content-language'] = case.language }
        local answer, _, seen = passed(g.lang:layer(), request({ ['accept-language'] = 'en' }), { headers = headers })

        t.assert_equals(seen.locale, 'en')
        t.assert_is(answer.headers, headers)
        t.assert_equals(answer.headers.vary, case.expected)
        t.assert_equals(answer.headers['content-language'], case.language or 'en')
    end
end

g.test_what_is_not_a_table_of_headers_is_left_as_it_is = function()
    local odd = { 'Accept-Language' }
    local answer = passed(g.lang:layer(), request(), { headers = { vary = odd } })

    t.assert_is(answer.headers.vary, odd)
    t.assert_equals(answer.headers['content-language'], 'ru')

    answer = passed(g.lang:layer(), request(), { headers = 'content-type: text/plain' })

    t.assert_equals(answer, { headers = 'content-type: text/plain' })

    local text = g.lang:layer()(request(), function()
        return 'готово'
    end)

    t.assert_equals(text, 'готово')
end

g.test_a_refusal_passes_through = function()
    local refusal = { status = 404, message = 'нет такого адреса' }
    local incoming = request({ ['accept-language'] = 'en' })
    local answer, failure = g.lang:layer()(incoming, function()
        t.assert_equals(g.lang:locale(), 'en')

        return nil, refusal
    end)

    t.assert_equals(answer, nil)
    t.assert_is(failure, refusal)
    t.assert_equals(refusal, { status = 404, message = 'нет такого адреса' })

    -- Отказ рисуют за слоем, где контекста нет: язык ему остаётся в запросе.
    t.assert_equals(g.lang:locale(), 'ru')
    t.assert_equals(incoming.locale, 'en')
end

g.test_the_language_chosen_explicitly_goes_to_the_request_too = function()
    local incoming = request({ ['accept-language'] = 'en' })

    passed(
        g.lang:layer({
            from = function()
                return 'RU'
            end,
        }),
        incoming
    )

    t.assert_equals(incoming.locale, 'ru')
end

g.test_unfit_layer_settings_are_named = function()
    t.assert_equals(
        helper.blamed(function()
            g.lang:layer({ form = helper.wrong(print) })
        end),
        'настройки слоя языка: ключа «form» нет, есть from'
    )
    t.assert_equals(
        helper.blamed(function()
            g.lang:layer({ from = helper.wrong('cookie') })
        end),
        'настройки слоя языка.from — функция или вызываемая таблица, а не строка'
    )
end
