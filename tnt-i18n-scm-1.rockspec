rockspec_format = '3.0'

package = 'tnt-i18n'
version = 'scm-1'

source = {
    url = 'git+https://github.com/tnt-skein/tnt-i18n.git',
    branch = 'main',
}

description = {
    summary = 'Переводы: строки по языкам, язык запроса по Accept-Language и формы слова при числе',
    detailed = [[
        Строки по языкам деревом разделов, поиск по ключу с подстановками
        по именам и формы слова при числе по правилу языка: русское,
        украинское и белорусское — правило tnt-str, английское встроено,
        прочие задаются настройкой. Строки, которой нет в языке, ищут
        в укороченной метке (en-GB → en), потом в языке по умолчанию;
        ключ, которого нет нигде, возвращается сам.

        Язык запроса выбирает слой по заголовку Accept-Language (RFC 9110,
        поиск RFC 4647) либо по явному выбору человека и кладёт его
        в контекст файбера на весь остаток цепочки; ответу ставит
        Content-Language и Vary. Сверка diff называет строки, которых
        не хватает, лишние и с разошедшимися подстановками.

        Негодные строки — исключение при сборке, а не на первом запросе.
        Файлов пакет не читает. Зависит от tnt-str, tnt-context
        и tnt-must. Покрытие строк и убитых мутантов — 100 %.
    ]],
    homepage = 'https://github.com/tnt-skein/tnt-i18n',
    issues_url = 'https://github.com/tnt-skein/tnt-i18n/issues',
    maintainer = 'tnt-skein',
    license = 'MIT',
    labels = { 'tarantool', 'i18n', 'translation', 'locale', 'plural' },
}

dependencies = {
    'lua >= 5.1',
    -- Согласование слова с числом по-русски: одно правило для строк в коде и для переводов.
    'tnt-str',
    -- Язык запроса в контексте файбера.
    'tnt-context',
    -- Проверки аргументов на строке вызывающего и показ значения в отказе.
    'tnt-must',
}

build = {
    type = 'builtin',
    modules = {
        ['tnt.i18n'] = 'tnt/i18n.lua',
        ['tnt.i18n.layer'] = 'tnt/i18n/layer.lua',
        ['tnt.i18n.locale'] = 'tnt/i18n/locale.lua',
        ['tnt.i18n.messages'] = 'tnt/i18n/messages.lua',
        ['tnt.i18n.plural'] = 'tnt/i18n/plural.lua',
        ['tnt.i18n.translator'] = 'tnt/i18n/translator.lua',
    },
}
