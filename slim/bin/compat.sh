#!/bin/bash
# Backwards compatibility shim for legacy MODE values.
# Maps old MODE names to their slim equivalents so existing deployments
# continue to work without configuration changes.
#
# Legacy → Slim
#   InstallOnly         → Install
#   RunOnly             → Run
#   ForceRunOnly        → Run
#   UpdateOnly          → Update
#   ForceUpdateOnly     → Update
#   UpdateAndRun        → InstallAndRun
#   ForceUpdateAndRun   → InstallAndRun
#   ForceReadyState     → Run  (no state table in slim)
#   Init                → Install

case "${MODE:-}" in
  "InstallOnly")
    echo "COMPAT: MODE='InstallOnly' is deprecated; use 'Install'."
    MODE="Install"
    ;;
  "RunOnly"|"ForceRunOnly")
    echo "COMPAT: MODE='${MODE}' is deprecated; use 'Run'."
    MODE="Run"
    ;;
  "UpdateOnly"|"ForceUpdateOnly")
    echo "COMPAT: MODE='${MODE}' is deprecated; use 'Update'."
    MODE="Update"
    ;;
  "UpdateAndRun"|"ForceUpdateAndRun")
    echo "COMPAT: MODE='${MODE}' is deprecated; use 'InstallAndRun'."
    MODE="InstallAndRun"
    ;;
  "ForceReadyState")
    echo "COMPAT: MODE='ForceReadyState' is deprecated and has no equivalent (no state table in slim); defaulting to 'Run'."
    MODE="Run"
    ;;
  "Init")
    echo "COMPAT: MODE='Init' is deprecated; use 'Install'."
    MODE="Install"
    ;;
esac

export MODE
