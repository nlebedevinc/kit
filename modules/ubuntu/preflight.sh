# shellcheck shell=bash
# preflight: create the user config. The OS/session checks run in bin/kit
# before every install (kit_preflight), so they also run on a second pass.

describe() { echo "Check the system and create your kit config"; }

check() { [ -f "$(kit_user_config)" ]; }

apply() {
  local conf
  conf=$(kit_user_config)
  run_cmd mkdir -p "$(dirname "$conf")"
  run_cmd cp "$KIT_ROOT/lib/templates/kit.conf" "$conf"
  [ "$KIT_DRY_RUN" = 1 ] || info "Created $conf (your overrides for hosts/$KIT_HOST/host.conf)"
}

verify() {
  local ver conf
  ver=$(os_release_value VERSION_ID)
  case $ver in
    24.04 | 26.04) report ok "OS: Ubuntu $ver" ;;
    *) report fail "OS: Ubuntu ${ver:-unknown} (tested: 24.04, 26.04)" "kit may still work; check each module" ;;
  esac
  if [ "$(current_hostname)" = "${HOST_NAME:-}" ]; then
    report ok "Hostname: $HOST_NAME"
  else
    report info "Hostname is '$(current_hostname)', profile expects '${HOST_NAME:-}'" "sudo hostnamectl set-hostname ${HOST_NAME:-NAME}"
  fi
  conf=$(kit_user_config)
  if [ -f "$conf" ]; then
    report ok "User config: $conf"
  else
    report fail "User config missing" "kit install preflight"
  fi
  report_status
}
