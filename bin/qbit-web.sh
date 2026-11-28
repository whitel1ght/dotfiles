# Shared bits for the qbit* console scripts — sourced, not run.
#
# qbit_login reads ~/.config/qbitweb.env (QB_WEB_HOST/PORT/USER/PASS), logs into
# the qBittorrent Web UI and sets QB_BASE plus QB_JAR (a curl cookie jar removed
# on exit). qbit_api <endpoint> [curl args...] calls an endpoint with that jar.
#
# qBittorrent 5.3 answers auth/login with 204 and an empty body, so success is a
# status code, not a body — callers that need the status pass -w '\n%{http_code}'
# and split it off the body themselves.

qbit_login() {
    local env_file=$HOME/.config/qbitweb.env
    if [ ! -f "$env_file" ]; then
        echo "qbit: missing $env_file (QB_WEB_HOST/PORT/USER/PASS)" >&2
        return 1
    fi
    set -a
    # shellcheck source=/dev/null
    . "$env_file"
    set +a
    QB_BASE=http://$QB_WEB_HOST:$QB_WEB_PORT/api/v2
    QB_JAR=$(mktemp) || return 1
    trap 'rm -f "$QB_JAR"' EXIT
    local status
    status=$(curl -s -o /dev/null -w '%{http_code}' -c "$QB_JAR" \
        --data-urlencode "username=$QB_WEB_USER" \
        --data-urlencode "password=$QB_WEB_PASS" "$QB_BASE/auth/login")
    case $status in
        200 | 204) return 0 ;;
        *)
            echo "qbit: login to $QB_BASE failed (HTTP $status) — is qBittorrent running with its Web UI on?" >&2
            return 1
            ;;
    esac
}

qbit_api() {
    local endpoint=$1
    shift
    curl -s -b "$QB_JAR" "$QB_BASE/$endpoint" "$@"
}
