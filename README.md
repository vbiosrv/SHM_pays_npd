# SHM_pays_npd

Шаблон и утилиты для регистрации/отмены чеков НПД (Мой налог) в SHM.

## Состав

- `pays_nalog.tpl` — основной шаблон для регистрации дохода и отмены.
- `pays_nalog.tpls` — настройки шаблона.
- `config.nalog.json` — конфиг для `config.nalog` (deviceInfo/inn/token).
- `token.sh` — скрипт для получения refresh token по ИНН/паролю.

## Настройка

1. Получите refresh token:

```bash
bash token.sh <INN> <PASSWORD>
```

Скрипт выводит `refreshToken`.

2. Заполните `config.nalog.json`:

```json
{
  "deviceInfo": {
    "appVersion": "1.0.1",
    "metaDetails": {
      "userAgent": "curl 7.88.1 (x86_64-pc-linux-gnu) libcurl/7.88.1"
    },
    "sourceDeviceId": "MySHM_Billing",
    "sourceType": "WEB"
  },
  "inn": 1234567890,
  "token": "<refresh_token>"
}
```

3. Примените в SHM:

- Значение из `config.nalog.json` добавьте в `config.nalog`.
- Поместите `pays_nalog.tpl` и `pays_nalog.tpls` в каталог шаблонов SHM.

## Настройки шаблона (pays_nalog.tpls)

```json
{
  "allow_past_income": false,
  "max_past_days": 7
}
```

- `allow_past_income`: разрешает регистрацию доходов в прошлом.
- `max_past_days`: ограничение на количество дней в прошлом (если `> 0`).

## Логика работы

- При `payment.succeeded` регистрируется доход (чек).
- При `refund.succeeded` отменяется чек исходного платежа.
- В комментарии платежа хранится `comment.nalog` (flags, receipt_id, receiptLink).

## Примечания

- Для обхода кэша у `print` URL добавляется `?ts=...`.
- Используется `deviceInfo` из `config.nalog`.
