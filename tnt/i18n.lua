--- Переводы: строки по языкам, язык запроса и формы слова при числе.
---
---     local i18n = require('tnt.i18n')
---
---     local lang = i18n.new({
---         locale = 'ru',                                   -- язык по умолчанию
---         messages = {
---             ru = { customer = { not_found = 'Клиента №{id} нет' },
---                    nodes = { '{count} узел', '{count} узла', '{count} узлов' } },
---             en = { customer = { not_found = 'Customer {id} not found' },
---                    nodes = { '{count} node', '{count} nodes' } },
---         },
---     })
---
---     lang:get('customer.not_found', { id = 7 })   --> 'Клиента №7 нет'
---     lang:choice('nodes', 5, nil, 'en')           --> '5 nodes'
---     lang:layer()                                 -- слой: язык запроса по Accept-Language
---
--- Язык запроса лежит в контексте файбера (`tnt-context`): его кладёт
--- слой, а `get` и `choice` без языка в аргументах берут его оттуда.
--- Слой кладёт его и в сам запрос, полем `locale`: отказ рисуют уже
--- за слоем, где контекста с языком нет.
--- Согласование слова с числом по-русски — правило `tnt-str`: строка,
--- собранная в коде, и перевод считают формы одинаково. Прочим языкам,
--- кроме встроенных, правило задают настройкой.
---
--- Файлов пакет не читает: строки приходят таблицами, а откуда их взять —
--- из файлов, из базы, из настроек, — решает приложение.
--- Зависит от `tnt-str` (правило множественного числа), `tnt-context`
--- (язык запроса) и `tnt-must` (проверки аргументов).

local layer = require('tnt.i18n.layer')
local locale = require('tnt.i18n.locale')
local plural = require('tnt.i18n.plural')
local translator = require('tnt.i18n.translator')

local Module = {}

--- Ключ контекста с языком запроса.
Module.CONTEXT_KEY = translator.CONTEXT_KEY

--- Поле запроса, куда слой кладёт язык запроса.
Module.REQUEST_KEY = layer.REQUEST_KEY

--- Встроенные правила множественного числа по языку.
Module.PLURALS = plural.BUILTIN

Module.new = translator.new
Module.explain = translator.explain
Module.normalize = locale.normalize
Module.chain = locale.chain
Module.parse = locale.parse
Module.negotiate = locale.negotiate

return Module
