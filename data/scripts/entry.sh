#!/bin/ash
# shellcheck shell=ash
# shellcheck disable=SC2169 # making up for lack of ash support

cleanup() {
    # When you run `docker stop` or any equivalent, a SIGTERM signal is sent to PID 1.
    # A process running as PID 1 inside a container is treated specially by Linux:
    # it ignores any signal with the default action. As a result, the process will
    # not terminate on SIGINT or SIGTERM unless it is coded to do so. Because of this,
    # I've defined behavior for when SIGINT and SIGTERM is received.
    if [ "$openvpn_child" ]; then
        echo "Stopping OpenVPN..."
        kill -TERM "$openvpn_child"
    fi

    sleep 1
    echo "Exiting."
    exit 0
}

is_ip() {
    echo "$1" | grep -Eq "[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*"
}

# shellcheck disable=SC2153
if ! (echo "$VPN_LOG_LEVEL" | grep -Eq '^([1-9]|1[0-1])$'); then
    echo "WARNING: Invalid log level $VPN_LOG_LEVEL. Setting to default."
    vpn_log_level=3
else
    vpn_log_level=$VPN_LOG_LEVEL
fi

echo "
---- Running with the following variables ----
Kill switch: ${KILL_SWITCH:-off}
HTTP proxy: ${HTTP_PROXY:-off}
SOCKS proxy: ${SOCKS_PROXY:-off}
Proxy username secret: ${PROXY_PASSWORD_SECRET:-none}
Proxy password secret: ${PROXY_USERNAME_SECRET:-none}
Allowing subnets: ${SUBNETS:-none}
Using OpenVPN log level: $vpn_log_level"

if [ -n "$VPN_CONFIG_FILE" ]; then
    config_file_original="$VPN_CONFIG_FILE/act.path.client.ovpn"
else
    # Capture the filename of the first .conf file to use as the OpenVPN config.
    config_file_original=$(find /data/vpn -name "*.conf" 2> /dev/null | sort | head -1)
    if [ -z "$config_file_original" ]; then
        >&2 echo "ERROR: No configuration file found. Please check your mount and file permissions. Exiting."
        exit 1
    fi
fi
echo "Using configuration file: $config_file_original"

trap cleanup INT TERM

if [ "$HTTP_PROXY" = "on" ]; then
    if [ "$PROXY_USERNAME" ]; then
        if [ "$PROXY_PASSWORD" ]; then
            echo "Configuring HTTP proxy authentication."
            echo -e "\nBasicAuth $PROXY_USERNAME $PROXY_PASSWORD" >> /data/tinyproxy.conf
        else
            echo "WARNING: Proxy username supplied without password. Starting HTTP proxy without credentials."
        fi
    elif [ -f "/run/secrets/$PROXY_USERNAME_SECRET" ]; then
        if [ -f "/run/secrets/$PROXY_PASSWORD_SECRET" ]; then
            echo "Configuring proxy authentication."
            echo -e "\nBasicAuth $(cat /run/secrets/$PROXY_USERNAME_SECRET) $(cat /run/secrets/$PROXY_PASSWORD_SECRET)" >> /data/tinyproxy.conf
        else
            echo "WARNING: Credentials secrets not read. Starting HTTP proxy without credentials."
        fi
    fi
    /data/scripts/tinyproxy_wrapper.sh &
fi

if [ "$SOCKS_PROXY" = "on" ]; then
    if [ "$PROXY_USERNAME" ]; then
        if [ "$PROXY_PASSWORD" ]; then
            echo "Configuring SOCKS proxy authentication."
            adduser -S -D -g "$PROXY_USERNAME" -H -h /dev/null "$PROXY_USERNAME"
            echo "$PROXY_USERNAME:$PROXY_PASSWORD" | chpasswd 2> /dev/null
            sed -i 's/socksmethod: none/socksmethod: username/' /data/sockd.conf
        else
            echo "WARNING: Proxy username supplied without password. Starting SOCKS proxy without credentials."
        fi
    elif [ -f "/run/secrets/$PROXY_USERNAME_SECRET" ]; then
        if [ -f "/run/secrets/$PROXY_PASSWORD_SECRET" ]; then
            echo "Configuring proxy authentication."
            adduser -S -D -g "$(cat /run/secrets/$PROXY_USERNAME_SECRET)" -H -h /dev/null "$(cat /run/secrets/$PROXY_USERNAME_SECRET)"
            echo "$(cat /run/secrets/$PROXY_USERNAME_SECRET):$(cat /run/secrets/$PROXY_PASSWORD_SECRET)" | chpasswd 2> /dev/null
            sed -i 's/socksmethod: none/socksmethod: username/' /data/sockd.conf
        else
            echo "WARNING: Credentials secrets not read. Starting SOCKS proxy without credentials."
        fi
    fi
    /data/scripts/dante_wrapper.sh &
fi

ovpn_auth_flag=''
if [ -n "$OPENVPN_AUTH_SECRET" ]; then 
    if [ -f "/run/secrets/$OPENVPN_AUTH_SECRET" ]; then
        echo "Configuring OpenVPN authentication."
        ovpn_auth_flag="--auth-user-pass /run/secrets/$OPENVPN_AUTH_SECRET"
    else
        echo "WARNING: OpenVPN Credentials secrets fail to read."
    fi
fi

echo -e "Running OpenVPN client.\n"

openvpn --config "$config_file_original" \
    $ovpn_auth_flag \
    --verb "$vpn_log_level" \
    --auth-nocache \
    --connect-retry-max 10 \
    --pull-filter ignore "route-ipv6" \
    --pull-filter ignore "ifconfig-ipv6" \
    --script-security 2 \
    --up-restart \
    --cd /data/vpn &
openvpn_child=$!

wait $openvpn_child
