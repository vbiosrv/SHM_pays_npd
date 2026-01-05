{{# Автоотправка чека через API НПД. refresh_token берется из config.nalog.token }}

{{ REFRESH_TOKEN = config.nalog.token || '' }}
{{ INN = config.nalog.inn || '774342612670' }}

{{ SERVICE_NAME = 'Оплата удалённого доступа' }}
{{ PAYMENT_TYPE = 'WIRE' }}
{{ TIME_ZONE = '+03:00' }}
{{ PAY_SYSTEM = ['sbpkassa', 'yookassa', 'sbpkassa-refund', 'yookassa-refund'] }}

{{ DEVICE_INFO = config.nalog.deviceInfo || {} }}

{{ IF !REFRESH_TOKEN }}
{{ dump("STOP: no REFRESH_TOKEN") }}
REFRESH_TOKEN не задан в config.nalog.token
{{ STOP }}
{{ END }}

{{ pay_id = request.params.pay_id || (user.pays.last && user.pays.last.id) || '' }}
{{ IF event_name == 'PAYMENT' && user.pays.last.money > 0 }}
  {{ pay = pay.id(user.pays.last.id) }}
{{ ELSIF pay_id }}
  {{ pay = pay.id(pay_id) }}
{{ ELSE }}
  {{ dump("STOP: no pay_id") }}
  {{ STOP }}
{{ END }}

{{ IF pay.comment.event != 'payment.succeeded' && pay.comment.event != 'refund.succeeded' }}
  {{ pays = pay.filter('user_id' => pay.user_id).rsort('id').limit(50).items('admin', 1) }}
  {{ FOR p IN pays }}
    {{ IF p.comment.event == 'payment.succeeded' }}
      {{ pay = p }}
      {{ LAST }}
    {{ END }}
  {{ END }}
{{ END }}

{{ IF pay.comment.event != 'refund.succeeded' && PAY_SYSTEM.grep('^' _ pay.pay_system_id _ '$').size == 0 }}
  {{ dump("STOP: pay_system_id not allowed: " _ pay.pay_system_id) }}
  {{ STOP }}
{{ END }}

{{ comment = pay.comment || {} }}
{{ has_nalog = comment.nalog.defined ? 1 : 0 }}
{{ nalog = has_nalog ? comment.nalog : {} }}
{{ income_send = has_nalog ? nalog.income_send : comment.income_send }}
{{ IF !has_nalog && (comment.income_send || comment.receipt_id || comment.receiptLink || comment.cancel_send || comment.receiptUuid) }}
  {{ nalog = {
    income_send = comment.income_send
    receipt_id = comment.receipt_id
    receiptLink = comment.receiptLink
    cancel_send = comment.cancel_send
    receiptUuid = comment.receiptUuid
  } }}
  {{ comment.nalog = nalog }}
  {{ pay.set_json('comment', comment) }}
  {{ has_nalog = 1 }}
{{ END }}

{{ IF income_send && pay.comment.event == 'payment.succeeded' }}
  {{ dump("STOP: income_send already set") }}
  {{ STOP }}
{{ END }}

{{ allow_past = tpl.settings.allow_past_income }}
{{ max_past_days = (tpl.settings.max_past_days || 0) + 0 }}
{{ USE date }}
{{ dump({
  allow_past_income = allow_past,
  max_past_days = max_past_days,
  pay_date = pay.date,
  now = date.now
}) }}
{{ IF !(allow_past == 1 || allow_past == true) }}
  {{ pay_day = date.format(pay.date, '%Y-%m-%d') }}
  {{ now_day = date.format(date.now, '%Y-%m-%d') }}
{{ IF pay_day < now_day }}
    {{ dump("STOP: past income and allow_past_income disabled") }}
    {{ STOP }}
  {{ END }}
{{ ELSIF max_past_days > 0 }}
  {{ pay_sec = date.format(pay.date, '%s') }}
  {{ now_sec = date.format(date.now, '%s') }}
  {{ dump({ pay_sec = pay_sec, now_sec = now_sec, diff_days = (now_sec - pay_sec) / 86400 }) }}
  {{ max_sec = max_past_days * 86400 }}
{{ IF (now_sec - pay_sec) > max_sec }}
    {{ dump("STOP: past income exceeds max_past_days") }}
    {{ STOP }}
  {{ END }}
{{ END }}

{{ token_resp = http.post(
  'https://lknpd.nalog.ru/api/v1/auth/token',
  'content_type','application/json',
  'content', { refreshToken = REFRESH_TOKEN, deviceInfo = DEVICE_INFO }
) }}
{{# debug removed: token_resp }}

{{ ACCESS_TOKEN = token_resp.token || '' }}
{{ IF !ACCESS_TOKEN }}
{{ dump("STOP: no ACCESS_TOKEN") }}
Не удалось получить access token
{{ STOP }}
{{ END }}

{{ IF pay.comment.event == 'refund.succeeded' }}
  {{ IF (comment.nalog && comment.nalog.cancel_send) || comment.cancel_send }}
    {{ dump("STOP: cancel_send already set") }}
    {{ STOP }}
  {{ END }}
  {{ obj = pay.comment.object || {} }}
  {{ orig_payment_id = obj.payment_id || '' }}
  {{ target_pay = {} }}
  {{ IF orig_payment_id }}
    {{ pays = pay.filter('user_id' => pay.user_id).rsort('id').limit(50).items('admin', 1) }}
    {{ FOR p IN pays }}
      {{ p_obj = p.comment.object || {} }}
      {{ IF p_obj.id && ('' _ p_obj.id) == ('' _ orig_payment_id) }}
        {{ target_pay = p }}
        {{ LAST }}
      {{ END }}
    {{ END }}
  {{ END }}

  {{ target_comment = target_pay.comment || {} }}
  {{ target_has_nalog = target_comment.nalog.defined ? 1 : 0 }}
  {{ target_nalog = target_has_nalog ? target_comment.nalog : {} }}
  {{ IF !target_has_nalog && (target_comment.income_send || target_comment.receipt_id || target_comment.receiptLink || target_comment.cancel_send || target_comment.receiptUuid) }}
    {{ target_nalog = {
      income_send = target_comment.income_send
      receipt_id = target_comment.receipt_id
      receiptLink = target_comment.receiptLink
      cancel_send = target_comment.cancel_send
      receiptUuid = target_comment.receiptUuid
    } }}
  {{ END }}

  {{ target_receipt_uuid = (target_nalog.receipt_id || target_nalog.receiptUuid || '') }}
    {{ USE date }}
    {{ ts = date.now }}
    {{ target_receipt_url = target_receipt_uuid ? ('https://lknpd.nalog.ru/api/v1/receipt/' _ INN _ '/' _ target_receipt_uuid _ '/print?ts=' _ ts) : '' }}

  {{ current_nalog = comment.nalog || {} }}
  {{ current_receipt_id = current_nalog.receipt_id || current_nalog.receiptUuid || comment.receipt_id || comment.receiptUuid || '' }}
  {{ current_receipt_url = current_nalog.receiptLink || comment.receiptLink || (current_receipt_id ? ('https://lknpd.nalog.ru/api/v1/receipt/' _ INN _ '/' _ current_receipt_id _ '/print') : '') }}

  {{ IF target_receipt_uuid }}
    {{ USE date }}
    {{ cancel_time = date.format(pay.date, '%Y-%m-%dT%H:%M:%S' _ TIME_ZONE) }}
    {{ cancel_body = {
      operationTime = cancel_time
      requestTime = cancel_time
      comment = 'Возврат средств'
      receiptUuid = target_receipt_uuid
      partnerCode = null
    } }}
    {{ cancel_headers = { Authorization = 'Bearer ' _ ACCESS_TOKEN } }}
    {{ cancel_resp = http.post(
      'https://lknpd.nalog.ru/api/v1/cancel',
      'content_type','application/json',
      'content', cancel_body,
      'headers', cancel_headers
    ) }}
    {{# debug removed: cancel_resp }}
    {{ current_nalog = comment.nalog || {} }}
    {{ current_nalog.income_send = 1 }}
    {{ current_nalog.cancel_send = 1 }}
    {{ IF target_receipt_uuid }}
      {{ current_nalog.receipt_id = target_receipt_uuid }}
    {{ END }}
    {{ IF target_receipt_url }}
      {{ current_nalog.receiptLink = target_receipt_url }}
    {{ END }}
    {{ comment.nalog = current_nalog }}
    {{ pay.set_json('comment', comment) }}
    {{ u = user.id(pay.user_id) }}
    {{ send_url = current_nalog.receiptLink || target_receipt_url || '' }}
    {{ FOR b IN config.telegram.keys }}
      {{ tg = u.settings.telegram.${b} }}
      {{ IF tg && tg.chat_id && tg.status != "kicked" }}
        {{ IF send_url }}
          {{ send_result = u.telegram.profile(b).send("sendPhoto" = {
            "chat_id" => tg.chat_id,
            "photo" => send_url,
            "caption" => "💸 Оформлен возврат.\nЧек №" _ target_pay.id _ " аннулирован."
          }) }}
          {{ dump(send_result.ok) }}
          {{ dump(send_result.message) }}
          {{ dump(send_result.result) }}
        {{ END }}
      {{ END }}
    {{ END }}
  {{ END }}
  {{ dump("STOP: refund.succeeded handled") }}
  {{ STOP }}
{{ END }}

{{ IF pay.comment.event != 'payment.succeeded' }}
  {{ dump("STOP: not payment.succeeded, event=" _ (pay.comment.event || '')) }}
  {{ STOP }}
{{ END }}

{{ USE date }}
{{ trans_time = date.format(pay.date, '%Y-%m-%dT%H:%M:%S' _ TIME_ZONE) }}

{{ amount = pay.money * 1 }}
{{ income_content = {
  operationTime = trans_time
  requestTime = trans_time
  services = [ { name = SERVICE_NAME, amount = amount, quantity = 1 } ]
  totalAmount = amount
  client = { contactPhone = null, displayName = null, inn = null, incomeType = 'FROM_INDIVIDUAL' }
  paymentType = PAYMENT_TYPE
  ignoreMaxTotalIncomeRestriction = false
} }}

{{ headers = { Authorization = 'Bearer ' _ ACCESS_TOKEN } }}
{{ income_resp = http.post(
  'https://lknpd.nalog.ru/api/v1/income',
  'content_type','application/json',
  'content', income_content,
  'headers', headers
) }}
{{# debug removed: income_resp }}

{{ receipt_id = income_resp.approvedReceiptUuid || '' }}
{{ IF !receipt_id }}
{{ dump("STOP: no receipt_id from income_resp") }}
Чек не создан
{{ STOP }}
{{ END }}

{{ receipt_url = 'https://lknpd.nalog.ru/api/v1/receipt/' _ INN _ '/' _ receipt_id _ '/print' }}
{{ nalog.income_send = 1 }}
{{ nalog.receipt_id = receipt_id }}
{{ nalog.receiptLink = receipt_url }}
{{ comment.nalog = nalog }}
{{ pay.set_json('comment', comment) }}

{{ u = user.id(pay.user_id) }}
{{ FOR b IN config.telegram.keys }}
  {{ tg = u.settings.telegram.${b} }}
  {{ IF tg && tg.chat_id && tg.status != "kicked" }}
    {{ u.telegram.profile(b).send("sendPhoto" = {
      "chat_id" => tg.chat_id,
      "photo" => receipt_url,
      "caption" => "Чек №" _ pay.id
    }) }}
  {{ END }}
{{ END }}
