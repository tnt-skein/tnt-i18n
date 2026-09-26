--- Общие средства проверок переводов.
---
--- Внешних зависимостей у пакета нет: строки приходят таблицами, язык
--- запроса лежит в контексте настоящего файбера, и двойник здесь доказал
--- бы только, что мы правильно разговариваем сами с собой.
---
--- Исходники читаются с диска, а не через `require`: у Tarantool свой
--- загрузчик `.rocks`, он идёт раньше `package.path` и подсунул бы
--- установленную копию пакета, если она есть. Проверки тогда шли бы
--- против вчерашнего кода, а покрытие считалось бы по нему. Поэтому
--- файлы читаются сами, в порядке зависимостей, и кладутся
--- в `package.loaded` под именами модулей: `require` изнутри пакета
--- находит их первыми. Зависимости — `tnt-str`, `tnt-context`
--- и `tnt-must` — берутся из `.rocks` обычным `require`: проверяется этот
--- пакет, а не они.
---
--- Проверки берут всё через этот помощник: он — единственное, чем файл
--- проверок отличается от того же файла там, где пакет живёт рядом
--- со своими зависимостями.

local fio = require('fio')
local t = require('luatest')

local helper = {}

--- Модули пакета в порядке зависимостей.
helper.MODULES = {
    { name = 'tnt.i18n.locale', path = 'tnt/i18n/locale.lua' },
    { name = 'tnt.i18n.plural', path = 'tnt/i18n/plural.lua' },
    { name = 'tnt.i18n.messages', path = 'tnt/i18n/messages.lua' },
    { name = 'tnt.i18n.layer', path = 'tnt/i18n/layer.lua' },
    { name = 'tnt.i18n.translator', path = 'tnt/i18n/translator.lua' },
    { name = 'tnt.i18n', path = 'tnt/i18n.lua' },
}

--- Фасад пакета из исходников.
---
--- Грузится один раз на файл проверок: состояния у пакета нет, кроме
--- объявленного ключа контекста, а его повторное объявление с теми же
--- настройками безвредно.
for _, module in ipairs(helper.MODULES) do
    local chunk, failure = loadfile(fio.abspath(module.path))

    if chunk == nil then
        error(('исходник %s не читается: %s'):format(module.name, tostring(failure)))
    end

    local value = chunk()

    -- Пустое значение в `package.loaded` для `require` значит «не загружен»,
    -- и следующий модуль списка молча взял бы зависимость из `.rocks`.
    if value == nil then
        error(('исходник %s не вернул модуль'):format(module.name))
    end

    package.loaded[module.name] = value
end

helper.i18n = package.loaded['tnt.i18n']

--- Части той же загрузки, что и фасад; контекст — тот, что берёт пакет.
helper.context = require('tnt.context')
helper.locale = package.loaded['tnt.i18n.locale']
helper.messages = package.loaded['tnt.i18n.messages']

--- Негодный аргумент — нарочно.
---
--- Анализатор типов о таком намерении знать не может и справедливо
--- ругается на каждую такую строку.
---@param value any
---@return any
function helper.wrong(value)
    return value
end

--- Переводчик, на котором идут проверки: русский по умолчанию,
--- английский, британский поверх английского.
---@param extra table|nil Настройки поверх образца
---@return TntI18n
function helper.sample(extra)
    local options = {
        locale = 'ru',
        messages = {
            ru = {
                customer = { not_found = 'Клиента №{id} нет', saved = 'Сохранено' },
                nodes = { '{count} узел', '{count} узла', '{count} узлов' },
                files = { '{count} файл', '{count} файла', '{count} файлов' },
                ['home.title'] = 'Главная',
            },
            en = {
                customer = { not_found = 'Customer {id} not found' },
                nodes = { '{count} node', '{count} nodes' },
                home = { title = 'Home' },
            },
            ['en-GB'] = { home = { title = 'Home page' } },
        },
    }

    for key, value in pairs(extra or {}) do
        options[key] = value
    end

    return helper.i18n.new(options)
end

--- Текст броска вызова; место в нём обязано быть файлом проверок,
--- откуда позвали, а не строкой внутри пакета.
---
--- Сверяется файл, а не номер строки: следующий по стеку кадр лежит уже
--- в другом файле (у luatest либо здесь), так что уровень вины, съехавший
--- на кадр в любую сторону, проверка видит, а переформатирование
--- проверок номера строк не ломает.
---@param call fun()
---@return string|nil
function helper.blamed(call)
    local passed, raised = pcall(call)

    t.assert_not(passed, 'вызов не бросил')

    local caller = debug.getinfo(2, 'S') --[[@as { short_src: string }]]
    local where, said = tostring(raised):match('^(.-):%d+: (.*)$')

    t.assert_equals(where, caller.short_src, tostring(raised))

    return said
end

return helper
