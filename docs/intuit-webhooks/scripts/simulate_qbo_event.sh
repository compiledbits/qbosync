#!/usr/bin/env bash
# filename: simulate_qbo_event.sh
# description: simulates an intuit event notification
# usage example: simulate_qbo_event.sh -w "https://example.my.salesforce-sites.com/services/apexrest/qbosync/webhook/qbo" -v "00000000-0000-0000-0000-000000000000"
# requires: jq, openssl, curl

set -euo pipefail
IFS=$'\n\t'

# required external commands
REQUIRED_CMDS=(jq openssl curl)

check_required_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "error: required command '$cmd' not found." >&2
    exit 2
  fi
}

# verify dependencies are installed
for cmd in "${REQUIRED_CMDS[@]}"; do
  check_required_command "$cmd"
done

usage() {
  echo "usage: simulate_qbo_event.sh -w <webhook_url> -v <verifier_token>"
  exit 1
}

mask_secret() {
  local s="$1"
  if [[ -z "$s" ]]; then
    echo ""
    return
  fi
  printf '%s' "${s:0:4}...${s: -4}"
}

main() {
  local webhook_url=""
  local verifier_token=""
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
  local request_body=$(jq -c -n --arg t "$timestamp" '
    { eventNotifications:
      [ { realmId: "000000000000",
          dataChangeEvent: { entities: [ { id: "1", operation: "Update", name: "Customer", lastUpdated: $t } ] }
        } ]
    }')

  while getopts ":w:v:" opt; do
    case ${opt} in
    w)
      webhook_url="$OPTARG"
      ;;
    v)
      verifier_token="$OPTARG"
      ;;
    \?)
      echo "invalid option: -$OPTARG" >&2
      usage
      ;;
    :)
      echo "option -$OPTARG requires an argument." >&2
      usage
      ;;
    esac
  done

  # shift parsed options away
  shift $((OPTIND - 1))

  # validate all required params
  if [[ -z "$webhook_url" ]]; then
    echo "error: -w <webhook_url> is required."
    usage
  fi
  if [[ -z "$verifier_token" ]]; then
    echo "error: -v <verifier_token> is required."
    usage
  fi

  # compute HMAC-SHA256 of request body using verifier_token as the key
  # then base64-encode the result to match Apex's EncodingUtil.base64Encode(mac)
  if ! signature=$(printf '%s' "$request_body" | openssl dgst -sha256 -hmac "$verifier_token" -binary | openssl base64 2>/dev/null); then
    echo "error: failed to compute HMAC signature (openssl required)"
    exit 2
  fi

  printf 'webhook_url: %s\n' "$webhook_url"
  printf 'verifier_token: %s\n' "$(mask_secret "$verifier_token")"
  printf 'signature: %s\n' "$(mask_secret "$signature")"
  printf '%s' "$request_body" | jq .

  # note: online docs say this should be 'intuit_tid' but while testing i was seeing 'intuit-t-id'
  local intuit_trace_id='intuit-t-id: 99999999-8888-7777-6666-555555555555'
  local intuit_created_time_header="intuit-created-time: $timestamp"
  local intuit_notification_schema_version_header='intuit-notification-schema-version: 1.0'
  local content_type_header='Content-Type: application/json'

  # POST to the webhook URL with the 'intuit-signature' header
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "intuit-signature: $signature" \
    -H "$intuit_trace_id" \
    -H "$intuit_created_time_header" \
    -H "$intuit_notification_schema_version_header" \
    -H "$content_type_header" \
    -d "$request_body" \
    "$webhook_url")

  if [[ "$http_code" -eq 200 ]]; then
    echo "webhook accepted: HTTP 200"
    exit 0
  else
    printf 'webhook failed: HTTP %s\n' "$http_code"
    exit 3
  fi
}

main "$@"
