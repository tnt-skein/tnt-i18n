local t = require('luatest')

local helper = dofile('test/helper.lua')

local g = t.group('tnt.i18n.messages')

local messages = helper.messages

g.test_a_tree_becomes_flat_keys = function()
    t.assert_equals(
        messages.flatten({
            home = { title = 'Главная', menu = { about = 'О нас' } },
            nodes = { '{count} узел', '{count} узла', '{count} узлов' },
            ['customer.saved'] = 'Сохранено',
            empty = {},
        }, 'ru'),
        {
            ['home.title'] = 'Главная',
            ['home.menu.about'] = 'О нас',
            nodes = { '{count} узел', '{count} узла', '{count} узлов' },
            ['customer.saved'] = 'Сохранено',
        }
    )
    t.assert_equals(messages.flatten({}, 'ru'), {})
end

g.test_unfit_strings_are_named = function()
    for _, case in ipairs({
        { tree = 'строки', said = 'строки языка ru — словарь, а не строка' },
        { tree = { 'a', 'b' }, said = 'строки языка ru — словарь, а не список' },
        {
            tree = { a = { b = 1 } },
            said = 'строки языка ru: a.b — строка либо список форм, а не число',
        },
        {
            tree = { a = true },
            said = 'строки языка ru: a — строка либо список форм, а не логическое значение',
        },
        {
            tree = { a = { 'x', 2 } },
            said = 'строки языка ru: a — форма 2 — строка, а не число',
        },
        {
            tree = { a = { 'x', b = 'y' } },
            said = 'строки языка ru: ключ a.? — непустая строка, а не число',
        },
        {
            tree = { [''] = 'x' },
            said = 'строки языка ru: ключ ? — непустая строка, а не пустая',
        },
        {
            tree = { a = { b = 'x' }, ['a.b'] = 'y' },
            said = 'строки языка ru: ключ a.b задан дважды',
        },
    }) do
        local flat, complaint = messages.flatten(case.tree, 'ru')

        t.assert_equals(flat, nil)
        t.assert_equals(complaint, case.said)
    end
end

g.test_placeholders_of_a_string_and_of_all_its_forms = function()
    t.assert_equals(messages.placeholders('Клиента №{id} нет, {n}'), { id = true, n = true })
    t.assert_equals(messages.placeholders({ 'один', '{count} {what}' }), { count = true, what = true })
    t.assert_equals(messages.placeholders('без {} и { id }'), {})
end

g.test_values_are_put_by_names = function()
    t.assert_equals(messages.fill('{n} из {total_count}', { n = 3, total_count = 10 }), '3 из 10')
    t.assert_equals(messages.fill('{n} и {m}', { n = true }), 'true и {m}')
    t.assert_equals(messages.fill('скобки {} и { n }', { n = 1 }), 'скобки {} и { n }')
end
