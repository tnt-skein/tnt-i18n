local t = require('luatest')

local helper = dofile('test/helper.lua')

local g = t.group('tnt.i18n.locale')

local i18n = helper.i18n
local locale = helper.locale

-- ── Запись метки ─────────────────────────────────────────────────────

g.test_a_tag_is_written_in_its_own_case = function()
    t.assert_equals(i18n.normalize('ru'), 'ru')
    t.assert_equals(i18n.normalize('RU'), 'ru')
    t.assert_equals(i18n.normalize('fil'), 'fil')
    t.assert_equals(i18n.normalize('en_gb'), 'en-GB')
    t.assert_equals(i18n.normalize('EN-us'), 'en-US')
    t.assert_equals(i18n.normalize('sr-latn-rs'), 'sr-Latn-RS')
    t.assert_equals(i18n.normalize('ZH-HANT'), 'zh-Hant')
    t.assert_equals(i18n.normalize('es-419'), 'es-419')
    t.assert_equals(i18n.normalize('de-CH-1996'), 'de-CH-1996')

    -- Четыре буквы — письменность только сразу за языком; пять букв там же —
    -- вариант, и он строчный.
    t.assert_equals(i18n.normalize('en-US-LATN'), 'en-US-latn')
    t.assert_equals(i18n.normalize('sl-ROZAJ'), 'sl-rozaj')

    -- Часть до восьми знаков.
    t.assert_equals(i18n.normalize('en-ABCDEFGH'), 'en-abcdefgh')
    t.assert_equals(i18n.normalize('en-x-AB'), 'en-x-AB')
end

g.test_what_is_not_a_tag_is_nil = function()
    for _, said in ipairs({
        '',
        'e',
        'english',
        'e1',
        '12',
        'ру',
        'en-',
        '-en',
        'en--US',
        'en_',
        'en-abcdefghi',
        'en US',
        'en-G!',
    }) do
        t.assert_equals(i18n.normalize(said), nil, said)
    end

    t.assert_equals(i18n.normalize(nil), nil)
    t.assert_equals(i18n.normalize(42), nil)
end

-- ── Цепочка отступления ──────────────────────────────────────────────

g.test_the_chain_cuts_the_tag_part_by_part = function()
    t.assert_equals(i18n.chain('ru'), { 'ru' })
    t.assert_equals(i18n.chain('en-GB'), { 'en-GB', 'en' })
    t.assert_equals(i18n.chain('zh-Hant-TW'), { 'zh-Hant-TW', 'zh-Hant', 'zh' })
end

g.test_a_singleton_goes_away_with_what_follows_it = function()
    t.assert_equals(i18n.chain('en-x-ab'), { 'en-x-ab', 'en' })
    t.assert_equals(i18n.chain('en-a-bc-x-yz'), { 'en-a-bc-x-yz', 'en-a-bc', 'en' })
end

-- ── Заголовок ────────────────────────────────────────────────────────

g.test_languages_go_by_weight_and_then_by_order = function()
    t.assert_equals(i18n.parse('en-GB,en;q=0.8,ru;q=0.9'), {
        { tag = 'en-GB', q = 1 },
        { tag = 'ru', q = 0.9 },
        { tag = 'en', q = 0.8 },
    })

    t.assert_equals(i18n.parse('ru;q=0.5,en;q=0.5,de'), {
        { tag = 'de', q = 1 },
        { tag = 'ru', q = 0.5 },
        { tag = 'en', q = 0.5 },
    })
end

g.test_spaces_and_case_do_not_matter = function()
    t.assert_equals(i18n.parse(' EN-us ; Q = 0.7 , * ;q=0.1, ru'), {
        { tag = 'ru', q = 1 },
        { tag = 'en-US', q = 0.7 },
        { tag = '*', q = 0.1 },
    })
end

g.test_a_weight_is_from_zero_to_one_with_three_digits_at_most = function()
    t.assert_equals(i18n.parse('ru;q=1'), { { tag = 'ru', q = 1 } })
    t.assert_equals(i18n.parse('ru;q=1.'), { { tag = 'ru', q = 1 } })
    t.assert_equals(i18n.parse('ru;q=1.000'), { { tag = 'ru', q = 1 } })
    t.assert_equals(i18n.parse('ru;q=0.001'), { { tag = 'ru', q = 0.001 } })
    t.assert_equals(i18n.parse('ru;level=1;q=0.4'), { { tag = 'ru', q = 0.4 } })

    -- Негодный вес делает негодной всю запись, а ноль — «не подходит».
    for _, said in ipairs({ 'ru;q=0', 'ru;q=0.000', 'ru;q=', 'ru;q=1.5', 'ru;q=2', 'ru;q=0123', 'ru;q=.5' }) do
        t.assert_equals(i18n.parse(said), {}, said)
    end

    for _, said in ipairs({ 'ru;q=0.5000', 'ru;q=abc', 'ru;q=-1', 'ru;q=1e0' }) do
        t.assert_equals(i18n.parse(said), {}, said)
    end
end

g.test_what_is_not_a_language_is_skipped = function()
    t.assert_equals(i18n.parse('english, ru ,,;q=0.5, en'), { { tag = 'ru', q = 1 }, { tag = 'en', q = 1 } })
    t.assert_equals(i18n.parse(''), {})
    t.assert_equals(i18n.parse(nil), {})
    t.assert_equals(i18n.parse(42), {})
end

g.test_a_header_longer_than_the_limit_is_not_read = function()
    local exact = 'ru' .. string.rep(' ', 1022)

    t.assert_equals(#exact, locale.MAX_HEADER)
    t.assert_equals(i18n.parse(exact), { { tag = 'ru', q = 1 } })
    t.assert_equals(i18n.parse(exact .. ' '), {})
end

g.test_only_so_many_languages_are_read = function()
    local names = {}

    for code = 1, locale.MAX_RANGES do
        table.insert(names, 'a' .. string.char(96 + code))
    end

    t.assert_equals(#names, 16)
    t.assert_equals(#i18n.parse(table.concat(names, ',')), 16)

    table.insert(names, 'ru')

    local read = i18n.parse(table.concat(names, ','))

    t.assert_equals(#read, 16)
    t.assert_equals(read[16], { tag = 'ap', q = 1 })
end

-- ── Выбор языка ──────────────────────────────────────────────────────

--- Объявленные языки образца.
local AVAILABLE = { ru = true, en = true, ['pt-BR'] = true }

g.test_the_best_declared_language_is_chosen = function()
    t.assert_equals(i18n.negotiate('en-GB,ru;q=0.5', AVAILABLE, 'ru'), 'en')
    t.assert_equals(i18n.negotiate('de,ru;q=0.5,en;q=0.4', AVAILABLE, 'en'), 'ru')
    t.assert_equals(i18n.negotiate('pt-BR', AVAILABLE, 'ru'), 'pt-BR')
end

g.test_a_language_without_region_does_not_find_a_regional_one = function()
    t.assert_equals(i18n.negotiate('pt', AVAILABLE, 'ru'), 'ru')
end

g.test_any_language_is_the_default_one = function()
    t.assert_equals(i18n.negotiate('de,*;q=0.5,en;q=0.1', AVAILABLE, 'ru'), 'ru')
end

g.test_nothing_suitable_gives_the_default = function()
    t.assert_equals(i18n.negotiate('de', AVAILABLE, 'ru'), 'ru')
    t.assert_equals(i18n.negotiate(nil, AVAILABLE, 'en'), 'en')
    t.assert_equals(i18n.negotiate('de', AVAILABLE, nil), nil)
end
