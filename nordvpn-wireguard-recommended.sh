#!/bin/bash
set -euo pipefail

# Required binaries
REQUIRED_BINS=(curl jq fzf column base64)
# rbw only required if no env token
[ -z "${NORDVPN_TOKEN:-}" ] && REQUIRED_BINS+=(rbw)

missing=()

for bin in "${REQUIRED_BINS[@]}"; do
  command -v "$bin" >/dev/null 2>&1 || missing+=("$bin")
done

if [ "${#missing[@]}" -ne 0 ]; then
  printf 'Missing required binaries: %s\n' "${missing[*]}" >&2
  exit 1
fi

usage() {
  cat <<EOF
usage: ${0} [OPTION] [SEARCH]...
Select a NordVPN country and print recommended NordLynx config

Options:
  --wg
        output WireGuard config (default)
  --uci-full
        output Full OpenWRT UCI commands for initial setup of wireguard interface
  --uci
        output OpenWRT UCI commands for updating a pre-existing wireguard interface
  -h, --help
        print this message
EOF
}

OUTPUT_MODE="wg"   # default
SEARCH_QUERY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --uci-full)
      OUTPUT_MODE="uci-full"
      shift
      ;;
    --uci)
      OUTPUT_MODE="uci"
      shift
      ;;
    --wg)
      OUTPUT_MODE="wg"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
    *)
      SEARCH_QUERY="${SEARCH_QUERY:+$SEARCH_QUERY }$1"
      shift
      ;;
  esac
done

countries_table="$(
  curl -s 'https://api.nordvpn.com/v1/servers/countries' \
  | jq -r '
      (["ID","CODE","NAME"] | join("\u001F")),
      (.[] | [.id, .code, .name] | join("\u001F"))
    ' \
  | column -s $'\x1F' -t
)"

# Exit if no countries returned
[ "$(printf '%s\n' "$countries_table" | wc -l)" -lt 2 ] && echo "No countries returned" && exit 1

country_id="$(
  printf '%s\n' "$countries_table" \
  | fzf -1 -q "${SEARCH_QUERY}" --header-lines=1 --with-nth=2.. \
  | awk '{print $1}'
)"

[ -z "$country_id" ] && echo "No country selected" && exit 1

access_token="${NORDVPN_TOKEN:-$(rbw get nordaccount -f access_token 2>/dev/null)}"
auth_header="Authorization: Basic $(printf 'token:%s' "$(rbw get nordaccount -f access_token)" | base64 -w0)"
private_key="$(curl -s -H "${auth_header}" "https://api.nordvpn.com/v1/users/services/credentials" | jq -r '.nordlynx_private_key')"
raw_json=$(curl -s "https://api.nordvpn.com/v1/servers/recommendations?limit=1&filters\[country_id\]=${country_id}") 

jq -r '.[] | {
  name,
  hostname,
  country: .locations[].country.name,
  city: .locations[].country.city.name,
  load
} | to_entries[] | "\(.key | ascii_upcase),\(.value)"' <<<"${raw_json}" | \
column -t -s, 1>&2

echo 1>&2

if [ "${OUTPUT_MODE}" == "wg" ]; then
jq -r --arg privateKey "$private_key" '.[] | {
  publickey: (.technologies[] | select(.identifier == "wireguard_udp") | .metadata[] | select(.name == "public_key").value),
  station
} | 
"[Interface]
PrivateKey = \($privateKey)
Address = 10.5.0.2/16

[Peer]
PublicKey = \(.publickey)
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = \(.station):51820
PersistentKeepalive = 25"' <<<"${raw_json}"
elif [ "${OUTPUT_MODE}" == "uci-full" ]; then
  jq -r --arg privateKey "$private_key" '
  .[]
  | {
      publickey: (
        .technologies[]
        | select(.identifier == "wireguard_udp")
        | .metadata[]
        | select(.name == "public_key")
        | .value
      ),
      station
    }
  | "uci set network.wg0='\''interface'\''
uci set network.wg0.proto='\''wireguard'\''
uci set network.wg0.private_key='\''\($privateKey)'\''
uci add_list network.wg0.addresses='\''10.5.0.2/16'\''
uci add network wireguard_wg0
uci set network.@wireguard_wg0[-1].public_key='\''\(.publickey)'\''
uci set network.@wireguard_wg0[-1].endpoint_host='\''\(.station)'\''
uci set network.@wireguard_wg0[-1].endpoint_port='\''51820'\''
uci add_list network.@wireguard_wg0[-1].allowed_ips='\''0.0.0.0/0'\''
uci set network.@wireguard_wg0[-1].persistent_keepalive='\''25'\''"
  ' <<< "${raw_json}"
elif [ "${OUTPUT_MODE}" == "uci" ]; then
  jq -r '
  .[]
  | {
      publickey: (
        .technologies[]
        | select(.identifier == "wireguard_udp")
        | .metadata[]
        | select(.name == "public_key")
        | .value
      ),
      station
    }
  | "uci set network.@wireguard_wg0[-1].public_key='\''\(.publickey)'\''
uci set network.@wireguard_wg0[-1].endpoint_host='\''\(.station)'\''
uci set network.@wireguard_wg0[-1].endpoint_port='\''51820'\''"
  ' <<< "${raw_json}"
fi
