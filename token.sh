#!/usr/bin/bash

LOGIN_URL="https://lknpd.nalog.ru/api/v1/auth/lkfl"

USERNAME=$1
PASSWORD=$2

SOURCE_DEVICE_ID="MySHM_Billing"
SOURCE_TYPE="WEB"
APP_VERSION="1.0.1"
USER_AGENT="curl 7.88.1 (x86_64-pc-linux-gnu) libcurl/7.88.1"

auth_resp="$(curl -sS -X POST "$LOGIN_URL" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "'"$USERNAME"'",
    "password": "'"$PASSWORD"'",
    "deviceInfo": {
      "sourceDeviceId": "'"$SOURCE_DEVICE_ID"'",
      "sourceType": "'"$SOURCE_TYPE"'",
      "appVersion": "'"$APP_VERSION"'",
      "metaDetails": {
        "userAgent": "'"$USER_AGENT"'"
      }
    }
  }')"

echo "$auth_resp" | jq -r .refreshToken
