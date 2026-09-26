local t = require('luatest')

local helper = dofile('test/helper.lua')

local g = t.group('tnt.i18n.translator')

local i18n = helper.i18n
local context = helper.context

--- Правило двух форм, где единица и ноль — первая форма.
---@type TntI18nRule
local FRENCH = {
    forms = 2,
    form = function(count)
        return count < 2 and 1 or 2
    end,
}

--- Настройки с одним языком по умолчанию и его строками.
---@param messages table
---@param plurals table|nil
---@return table
local function only(messages, plurals)
    return { locale = 'ru', messages = { ru = messages }, plurals = plurals }
end

-- ── Строка по ключу ──────────────────────────────────────────────────

g.test_a_string_is_found_by_its_key_with_placeholders = function()
    local lang = helper.sample()

    t.assert_equals(lang:get('customer.not_found', { id = 7 }), 'Клиента №7 нет')
    t.assert_equals(lang:get('customer.not_found', { id = 7 }, 'en'), 'Customer 7 not found')
    t.assert_equals(lang:get('home.title'), 'Главная')
    t.assert_equals(lang:get('home.title', nil, 'en'), 'Home')
end

g.test_a_regional_language_falls_back_to_the_bare_one_and_then_to_the_default = function()
    local lang = helper.sample()

    t.assert_equals(lang:get('home.title', nil, 'en-GB'), 'Home page')
    t.assert_equals(lang:get('customer.not_found', { id = 7 }, 'en-GB'), 'Customer 7 not found')
    t.assert_equals(lang:get('customer.saved', nil, 'en-GB'), 'Сохранено')
    t.assert_equals(lang:get('customer.saved', nil, 'de'), 'Сохранено')
end

g.test_a_language_argument_is_normalized = function()
    t.assert_equals(helper.sample():get('home.title', nil, 'EN_gb'), 'Home page')
end

g.test_a_key_that_is_nowhere_is_returned_itself = function()
    local lang = helper.sample()

    t.assert_equals(lang:get('no.such.key'), 'no.such.key')
    t.assert_equals(lang:get('no.such.key', nil, 'en'), 'no.such.key')
    t.assert_equals(lang:choice('no.such.key', 5), 'no.such.key')
end

g.test_a_placeholder_without_a_value_stays_as_it_is = function()
    local lang = helper.sample()

    t.assert_equals(lang:get('customer.not_found'), 'Клиента №{id} нет')
    t.assert_equals(lang:get('customer.not_found', { who = 1 }), 'Клиента №{id} нет')
end

g.test_get_checks_its_arguments = function()
    local lang = helper.sample()

    t.assert_equals(
        helper.blamed(function()
            lang:get(helper.wrong(7))
        end),
        'ключ строки — строка, а не число'
    )
    t.assert_equals(
        helper.blamed(function()
            lang:get('home.title', helper.wrong('id'))
        end),
        'подстановки — таблица, а не строка'
    )
    t.assert_equals(
        helper.blamed(function()
            lang:get('home.title', nil, 'en_')
        end),
        'язык «en_» — не метка языка: ждали вид ru либо en-GB'
    )
    t.assert_equals(
        helper.blamed(function()
            lang:get('nodes')
        end),
        'строка nodes — формы при числе: её берёт choice, а не get'
    )
end

-- ── Язык запроса ─────────────────────────────────────────────────────

g.test_the_language_of_the_request_is_taken_from_the_context = function()
    local lang = helper.sample()

    t.assert_equals(lang:locale(), 'ru')

    context.run({ [i18n.CONTEXT_KEY] = 'en' }, function()
        t.assert_equals(lang:locale(), 'en')
        t.assert_equals(lang:get('home.title'), 'Home')
        t.assert_equals(lang:choice('nodes', 1), '1 node')
        t.assert_equals(lang:has('customer.saved'), false)

        -- Язык в аргументе главнее языка запроса.
        t.assert_equals(lang:get('home.title', nil, 'ru'), 'Главная')
    end)

    t.assert_equals(lang:locale(), 'ru')
end

g.test_an_unfit_language_in_the_context_means_the_default = function()
    local lang = helper.sample()

    context.run({ [i18n.CONTEXT_KEY] = 'en_GB' }, function()
        t.assert_equals(lang:locale(), 'en-GB')
    end)

    context.run({ [i18n.CONTEXT_KEY] = 'english' }, function()
        t.assert_equals(lang:locale(), 'ru')
        t.assert_equals(lang:get('home.title'), 'Главная')
    end)
end

g.test_the_language_is_not_written_to_the_journal = function()
    -- Язык виден по заголовку запроса и ничего не говорит о поломке:
    -- записи журнала он не нужен.
    context.run({ [i18n.CONTEXT_KEY] = 'en' }, function()
        t.assert_equals(context.log_fields(), nil)
    end)
end

g.test_the_context_key_takes_a_long_tag_but_not_a_text = function()
    local long = 'en-' .. string.rep('a', 61)

    t.assert_equals(#long, 64)

    context.run({ [i18n.CONTEXT_KEY] = long }, function()
        t.assert_equals(context.get(i18n.CONTEXT_KEY), long)
    end)

    t.assert_error_msg_contains('до 64 байт', context.run, { [i18n.CONTEXT_KEY] = long .. 'a' }, function() end)
end

-- ── Формы при числе ──────────────────────────────────────────────────

g.test_the_form_agrees_with_the_number_in_russian = function()
    local lang = helper.sample()

    t.assert_equals(lang:choice('nodes', 1), '1 узел')
    t.assert_equals(lang:choice('nodes', 3), '3 узла')
    t.assert_equals(lang:choice('nodes', 11), '11 узлов')
    t.assert_equals(lang:choice('nodes', 21), '21 узел')
    t.assert_equals(lang:choice('nodes', 1.5), '1.5 узла')
end

g.test_the_form_agrees_with_the_number_in_english = function()
    local lang = helper.sample()

    t.assert_equals(lang:choice('nodes', 1, nil, 'en'), '1 node')
    t.assert_equals(lang:choice('nodes', -1, nil, 'en'), '-1 node')
    t.assert_equals(lang:choice('nodes', 0, nil, 'en'), '0 nodes')
    t.assert_equals(lang:choice('nodes', 2, nil, 'en'), '2 nodes')
    t.assert_equals(lang:choice('nodes', 1.5, nil, 'en'), '1.5 nodes')

    -- Британский своих форм не держит и берёт английские.
    t.assert_equals(lang:choice('nodes', 1, nil, 'en-GB'), '1 node')
end

g.test_ukrainian_and_belarusian_take_the_russian_rule = function()
    local lang = i18n.new({
        locale = 'uk',
        messages = {
            uk = { nodes = { '{count} вузол', '{count} вузли', '{count} вузлів' } },
            be = { nodes = { '{count} вузел', '{count} вузлы', '{count} вузлоў' } },
        },
    })

    t.assert_equals(lang:choice('nodes', 21), '21 вузол')
    t.assert_equals(lang:choice('nodes', 4), '4 вузли')
    t.assert_equals(lang:choice('nodes', 12), '12 вузлів')
    t.assert_equals(lang:choice('nodes', 22, nil, 'be'), '22 вузлы')
end

g.test_the_form_follows_the_rule_of_the_language_where_the_string_was_found = function()
    -- Строки нет в английском, она взята из русского — и согласуется
    -- по-русски: «5 файлов», а не вторая форма английского правила.
    t.assert_equals(helper.sample():choice('files', 5, nil, 'en'), '5 файлов')
end

g.test_the_count_is_put_unless_given_among_placeholders = function()
    local lang =
        i18n.new(only({ left = { '{who}: {count} узел', '{who}: {count} узла', '{who}: {count} узлов' } }))

    t.assert_equals(lang:choice('left', 2, { who = 'кластер' }), 'кластер: 2 узла')
    t.assert_equals(lang:choice('left', 1.5, { who = 'кластер', count = '1,5' }), 'кластер: 1,5 узла')
end

g.test_choice_checks_its_arguments = function()
    local lang = helper.sample()

    for _, case in ipairs({
        { key = 7, count = 1, said = 'ключ строки — строка, а не число' },
        { key = 'nodes', count = '1', said = 'число — число, а не строка' },
        { key = 'nodes', count = 0 / 0, said = 'число — число, а не NaN' },
        { key = 'nodes', count = math.huge, said = 'число — конечное число, а не inf' },
        { key = 'nodes', count = -math.huge, said = 'число — конечное число, а не -inf' },
        {
            key = 'nodes',
            count = 1,
            params = 'x',
            said = 'подстановки — таблица, а не строка',
        },
        {
            key = 'nodes',
            count = 1,
            tag = '?',
            said = 'язык «?» — не метка языка: ждали вид ru либо en-GB',
        },
        {
            key = 'home.title',
            count = 1,
            said = 'строка home.title — без форм при числе: её берёт get, а не choice',
        },
    }) do
        t.assert_equals(
            helper.blamed(function()
                lang:choice(case.key, case.count, case.params, case.tag)
            end),
            case.said
        )
    end
end

g.test_a_declared_rule_serves_its_language_and_the_regional_ones = function()
    local lang = i18n.new({
        locale = 'fr',
        messages = {
            fr = { books = { '{count} livre', '{count} livres' } },
            ['fr-CA'] = { books = { '{count} bouquin', '{count} bouquins' } },
        },
        plurals = { fr = FRENCH },
    })

    t.assert_equals(lang:choice('books', 1.5), '1.5 livre')
    t.assert_equals(lang:choice('books', 0), '0 livre')
    t.assert_equals(lang:choice('books', 2), '2 livres')
    t.assert_equals(lang:choice('books', 1, nil, 'fr-CA'), '1 bouquin')
end

g.test_a_declared_rule_replaces_the_builtin_one = function()
    local lang = i18n.new({
        locale = 'en',
        messages = { en = { sheep = { '{count} sheep' } } },
        plurals = {
            en = {
                forms = 1,
                form = function()
                    return 1
                end,
            },
        },
    })

    t.assert_equals(lang:choice('sheep', 3), '3 sheep')
end

g.test_a_rule_answering_out_of_its_forms_is_an_error = function()
    for _, case in ipairs({
        { answer = 3, shown = '3' },
        { answer = 1.5, shown = '1.5' },
        { answer = '1', shown = '«1»' },
    }) do
        local lang = i18n.new({
            locale = 'fr',
            messages = { fr = { books = { 'livre', 'livres' } } },
            plurals = {
                fr = {
                    forms = 2,
                    form = function()
                        return case.answer
                    end,
                },
            },
        })

        t.assert_equals(
            helper.blamed(function()
                lang:choice('books', 5)
            end),
            ('правило множественного числа языка fr дало форму %s числу 5: ждали от 1 до 2'):format(
                case.shown
            )
        )
    end
end

-- ── Есть ли строка ───────────────────────────────────────────────────

g.test_has_looks_in_the_language_without_the_default = function()
    local lang = helper.sample()

    t.assert_equals(lang:has('home.title', 'en-GB'), true)
    t.assert_equals(lang:has('customer.not_found', 'en-GB'), true)
    t.assert_equals(lang:has('customer.saved', 'en'), false)
    t.assert_equals(lang:has('customer.saved'), true)
    t.assert_equals(lang:has('home.title', 'de'), false)

    t.assert_equals(
        helper.blamed(function()
            lang:has(helper.wrong(nil))
        end),
        'ключ строки — строка, а не nil'
    )
    t.assert_equals(
        helper.blamed(function()
            lang:has('home.title', '')
        end),
        'язык «» — не метка языка: ждали вид ru либо en-GB'
    )
end

-- ── Языки ────────────────────────────────────────────────────────────

g.test_the_languages_are_listed_and_negotiated = function()
    local lang = helper.sample()

    t.assert_equals(lang:locales(), { 'en', 'en-GB', 'ru' })
    t.assert_equals(lang:negotiate('en-GB,en;q=0.5'), 'en-GB')
    t.assert_equals(lang:negotiate('de'), 'ru')
end

-- ── Сверка ───────────────────────────────────────────────────────────

g.test_the_diff_names_missing_extra_and_mismatched_keys = function()
    local lang = i18n.new({
        locale = 'ru',
        messages = {
            ru = {
                a = 'А {x}',
                b = 'Б',
                c = { '{n} узел', '{n} узла', '{n} узлов' },
                d = { 'один', '{n} узла', '{n} узлов' },
                e = 'Е {y}',
                f = 'Ф',
            },
            en = {
                a = 'A {x}',
                c = { '{n} node', '{n} nodes' },
                d = { 'one', 'many' },
                e = 'E {z}',
                f = 'F {x}',
                z = 'Z',
                y = 'Y',
            },
            ['en-GB'] = { b = 'B', q = 'Q' },
        },
    })

    t.assert_equals(lang:diff('en'), { missing = { 'b' }, extra = { 'y', 'z' }, mismatched = { 'd', 'e', 'f' } })
    t.assert_equals(lang:diff('en-GB'), { missing = {}, extra = { 'q' }, mismatched = { 'd', 'e', 'f' } })
    t.assert_equals(lang:diff('ru'), { missing = {}, extra = {}, mismatched = {} })
end

g.test_the_diff_is_asked_about_a_declared_language = function()
    t.assert_equals(
        helper.blamed(function()
            helper.sample():diff('de')
        end),
        'языка «de» среди строк нет: есть en, en-GB, ru'
    )
end

-- ── Настройки ────────────────────────────────────────────────────────

g.test_unfit_settings_are_named = function()
    local function nodes(forms)
        return { nodes = forms }
    end

    for _, case in ipairs({
        { options = nil, said = 'настройки переводов — таблица, а не nil' },
        {
            options = { messages = {} },
            said = 'настройки переводов.locale — строка, а не nil',
        },
        {
            options = { locale = 'RU', messages = { ru = {} } },
            said = 'язык по умолчанию «RU» записан не по форме: пишите ru',
        },
        {
            options = { locale = 'russian', messages = {} },
            said = 'язык по умолчанию «russian» — не метка языка: ждали вид ru либо en-GB',
        },
        {
            options = { locale = 'de', messages = { ru = {}, en = {} } },
            said = 'языка по умолчанию de среди строк нет: есть en, ru',
        },
        {
            options = { locale = 'ru', messages = { ru = {}, en_US = {} } },
            said = 'язык строк «en_US» записан не по форме: пишите en-US',
        },
        {
            options = { locale = 'ru', messages = { ru = {}, [1] = {} } },
            said = 'язык строк 1 — не метка языка: ждали вид ru либо en-GB',
        },
        {
            options = { locale = 'ru', messages = { ru = 'строки' } },
            said = 'строки языка ru — словарь, а не строка',
        },
        {
            options = only({}, { FR = FRENCH }),
            said = 'язык правила множественного числа «FR» записан не по форме: пишите fr',
        },
        {
            options = only({}, { fr = { forms = 7, form = FRENCH.form } }),
            said = 'правило множественного числа fr.forms — число от 1 до 6, а не 7',
        },
        {
            options = only({}, { fr = { forms = 0, form = FRENCH.form } }),
            said = 'правило множественного числа fr.forms — число от 1 до 6, а не 0',
        },
        {
            options = only({}, { fr = 'правило' }),
            said = 'правило множественного числа fr — таблица, а не строка',
        },
        {
            options = only(nodes({ 'узел', 'узла' })),
            said = 'строка nodes языка ru: форм 2, а у языка их 3',
        },
        {
            options = only(nodes({ 'узел', 'узла', 'узлов', 'узлу' })),
            said = 'строка nodes языка ru: форм 4, а у языка их 3',
        },
        {
            options = { locale = 'fr', messages = { fr = nodes({ 'nœud', 'nœuds' }) } },
            said = 'строка nodes языка fr — формы при числе, а правила множественного числа у языка нет: '
                .. 'задайте его настройкой plurals',
        },
        {
            options = {
                locale = 'ru',
                messages = { ru = nodes({ 'узел', 'узла', 'узлов' }), en = nodes('nodes') },
            },
            said = 'строка nodes — формы при числе в языке ru и одна строка в языке en',
        },
        {
            options = { locale = 'ru', messages = { ru = nodes('узлы'), en = nodes({ 'node', 'nodes' }) } },
            said = 'строка nodes — формы при числе в языке en и одна строка в языке ru',
        },
    }) do
        t.assert_equals(i18n.explain(case.options), case.said)
        t.assert_equals(
            helper.blamed(function()
                i18n.new(case.options)
            end),
            case.said
        )
    end
end

g.test_fit_settings_explain_nothing = function()
    t.assert_equals(i18n.explain(only({ a = 'А' }, { fr = FRENCH })), nil)
end
