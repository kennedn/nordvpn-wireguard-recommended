# nordvpn-wireguard-recommended

A minimal command-line interface for interactively selecting a NordVPN country and retrieving a recommended NordLynx/WireGuard endpoint.

The script can output either:

* a standard WireGuard client configuration
* OpenWRT `uci` commands for a WireGuard interface

## Prerequisites

Make sure the following tools are installed and available in your `PATH`:

* `bash`
* `curl`
* [`jq`](https://stedolan.github.io/jq/)
* [`fzf`](https://github.com/junegunn/fzf)
* `column`
* `base64`

Optional:

* [`rbw`](https://github.com/doy/rbw) if you want to read the NordVPN access token from Bitwarden instead of an environment variable

### Debian/Ubuntu Installation

Install tools via apt:

```bash
sudo apt update
sudo apt install bash curl jq fzf util-linux coreutils
```

`rbw` is optional. Install it separately if needed.

## Authentication

The script requires a NordVPN access token. See [here](https://support.nordvpn.com/hc/en-us/articles/20286980309265-How-to-log-in-to-NordVPN-without-a-GUI-using-a-token#h_01HFPBQ30Q1N7QPSD8XXQVF9NM).

It supports the following methods:

1. `NORDVPN_TOKEN` environment variable
2. `rbw` fallback using a Bitwarden item named `nordaccount` with a field named `access_token`

## Usage

```bash
usage: nordvpn-wireguard-recommended.sh [OPTION] [SEARCH]...
Select a NordVPN country and print recommended NordLynx config

Options:
  --wg
        output WireGuard config (default)
  --uci
        output OpenWRT UCI commands
```

## Example

```bash
export NORDVPN_TOKEN="${your-nordvpn_token}"
./nordvpn-wireguard-recommended.sh "United Kingdom" > united-kingdom.conf
```

<details>
  <summary>Output</summary>

```bash
# STDOUT
COUNTRY   United Kingdom
CITY      London
HOSTNAME  uk2736.nordvpn.com
LOAD      14
NAME      uk2736.nordvpn.com

# united-kingdom.conf
[Interface]
PrivateKey = XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
Address = 10.5.0.2/16

[Peer]
PublicKey = XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = uk2736.nordvpn.com:51820
PersistentKeepalive = 25
```

</details>

## OpenWRT Example

```bash
./nordvpn-wireguard-recommended.sh --uci netherlands
```

<details>
  <summary>Output</summary>

```bash
COUNTRY   Netherlands
CITY      Amsterdam
HOSTNAME  nl1234.nordvpn.com
LOAD      11
NAME      nl1234.nordvpn.com

uci set network.wg0='interface'
uci set network.wg0.proto='wireguard'
uci set network.wg0.private_key='XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX'
uci add_list network.wg0.addresses='10.5.0.2/16'
uci add network wireguard_wg0
uci set network.@wireguard_wg0[-1].public_key='XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX'
uci set network.@wireguard_wg0[-1].endpoint_host='nl1234.nordvpn.com'
uci set network.@wireguard_wg0[-1].endpoint_port='51820'
uci add_list network.@wireguard_wg0[-1].allowed_ips='0.0.0.0/0'
uci add_list network.@wireguard_wg0[-1].allowed_ips='::/0'
uci set network.@wireguard_wg0[-1].persistent_keepalive='25'
```

</details>

