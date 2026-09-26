# tnt-i18n

Переводы для Tarantool: строки по языкам, поиск по ключу с подстановками,
формы слова при числе по правилу языка, язык запроса по `Accept-Language`
и сверка переводов с языком по умолчанию.

```lua
local i18n = require('tnt.i18n')

local lang = i18n.new({
    locale = 'ru',
    messages = {
        ru = { customer = { not_found = 'Клиента №{id} нет' }, nodes = { '{count} узел', '{count} узла', '{count} узлов' } },
        en = { customer = { not_found = 'Customer {id} not found' }, nodes = { '{count} node', '{count} nodes' } },
    },
})

lang:get('customer.not_found', { id = 7 })   --> 'Клиента №7 нет'
lang:choice('nodes', 5)                      --> '5 узлов'
lang:choice('nodes', 1, nil, 'en')           --> '1 node'
lang:diff('en')                              --> { missing = {}, extra = {}, mismatched = {} }
```

Зависимости: [tnt-str](https://github.com/tnt-skein/tnt-str),
[tnt-context](https://github.com/tnt-skein/tnt-context),
[tnt-must](https://github.com/tnt-skein/tnt-must).

## Зачем

- **Строка по ключу, значения по именам.** `{id}` переживает перевод,
  где слова в предложении встают иначе; склеенную строку не перевести.
- **Формы при числе по правилу языка.** Русское правило — из `tnt-str`:
  строка, собранная в коде, и перевод считают формы одинаково — «21 узел»,
  «12 узлов», «1,5 узла». Прочим языкам правило задают настройкой, и число
  форм сверяется при сборке.
- **Язык запроса в контексте.** Слой выбирает язык по `Accept-Language`
  (поиск RFC 4647) либо по явному выбору и кладёт его в контекст файбера:
  строка из глубины кода говорит на языке запроса без аргумента. Ответу
  слой ставит `Content-Language` и `Vary`, а язык кладёт и в сам запрос —
  для обработчика отказов, который рисует отказ уже за слоем.
- **Отступление и сверка.** Строки нет в `en-GB` — берётся из `en`, нет
  и там — из языка по умолчанию; `diff` называет, чего не хватает, что
  лишнее и где разошлись подстановки.

Негодные строки — исключение при сборке, на строке вызывающего `new`,
а не отказ на первом запросе посетителя. Файлов пакет не читает: строки
приходят таблицами, а откуда их взять, решает приложение.

## Установка

```sh
tt rocks install tnt-i18n --server=https://tnt-skein.github.io/rocks
```

Или из исходников:

```sh
git clone https://github.com/tnt-skein/tnt-i18n.git
cd tnt-i18n && tt rocks make --server=https://tnt-skein.github.io/rocks
```

## Как пользоваться

| Вызов | Что делает |
|---|---|
| `i18n.new(opts)` | собирает переводчик: `locale` — язык по умолчанию, `messages` — строки деревом по языкам, `plurals` — правила сверх встроенных |
| `i18n.explain(opts)` | что не так с настройками, словами, либо `nil` — без броска |
| `lang:get(key, params, tag)` | строка по ключу с подстановками |
| `lang:choice(key, count, params, tag)` | форма строки при числе; число встаёт в `{count}` |
| `lang:has(key, tag)` | есть ли строка в языке — без языка по умолчанию |
| `lang:diff(tag)` | сверка языка с языком по умолчанию |
| `lang:layer(opts)` | слой языка запроса по договору `tnt-middleware` |

Без `tag` говорят на языке запроса — его кладёт в контекст слой:

```lua
local layer = lang:layer({
    from = function(request)   -- явный выбор: кука, сессия, профиль
        return request.headers['x-locale']
    end,
})

layer({ headers = { ['accept-language'] = 'en-US,en;q=0.9' } }, function()
    return { status = 200, body = lang:get('customer.not_found', { id = 7 }) }
end)
--> { status = 200, body = 'Customer 7 not found',
-->   headers = { ['content-language'] = 'en', vary = 'Accept-Language' } }
```

Правило множественного числа встроено у `ru`, `uk`, `be` и `en`; прочим
языкам его задают настройкой:

```lua
i18n.new({
    locale = 'fr',
    messages = { fr = { books = { '{count} livre', '{count} livres' } } },
    plurals = { fr = { forms = 2, form = function(count) return count < 2 and 1 or 2 end } },
}):choice('books', 1.5)   --> '1.5 livre'
```

## Проверки

```sh
make deps          # luatest, luacheck, luacov, cluacov и зависимости пакета в .rocks
make check         # форматирование, линт, проверки, покрытие с порогом 100 %
make mutants-all   # мутационное тестирование утилитой tnt-mutants из PATH, порог 100 % убитых
```

Проверок — 51; покрытие строк — 100 %, убитых мутантов — 100 %
(347 мутантов в пяти модулях). Отказы сверяются текстом целиком,
место броска — файлом вызывающего.

## Документ

Полное описание с обоснованием решений: [docs/i18n.md](docs/i18n.md).

## Лицензия

MIT.
