#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
production_dir="${repo_root}/apps/production"

for command_name in kubectl awk; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "${command_name} is required to validate production capacity" >&2
    exit 2
  fi
done

# Keep the rendered production workload requests below the single-node budget:
# 6000m CPU (6 cores) and 12 GiB RAM budget.
kubectl kustomize "$production_dir" | awk \
  -v cpu_budget_m=6000 \
  -v memory_budget_mi=12288 '
  function reset_document() {
    kind = ""
    object_name = ""
    target_name = ""
    replicas = 0
    max_replicas = 0
    request_cpu_m = 0
    request_memory_mi = 0
    resource_mode = ""
  }

  function cpu_to_millicores(value) {
    gsub(/"/, "", value)
    if (value ~ /m$/) {
      sub(/m$/, "", value)
      return value + 0
    }
    return (value + 0) * 1000
  }

  function memory_to_mib(value) {
    gsub(/"/, "", value)
    if (value ~ /Gi$/) {
      sub(/Gi$/, "", value)
      return (value + 0) * 1024
    }
    if (value ~ /Mi$/) {
      sub(/Mi$/, "", value)
      return value + 0
    }
    if (value ~ /Ki$/) {
      sub(/Ki$/, "", value)
      return (value + 0) / 1024
    }
    return 0
  }

  function record_document() {
    if (kind == "Deployment" || kind == "StatefulSet") {
      workload[object_name] = 1
      workload_replicas[object_name] = replicas
      workload_cpu_m[object_name] = request_cpu_m
      workload_memory_mi[object_name] = request_memory_mi
    } else if (kind == "HorizontalPodAutoscaler") {
      hpa_max_replicas[target_name] = max_replicas
    }
  }

  BEGIN { reset_document() }

  /^---$/ {
    record_document()
    reset_document()
    next
  }

  /^kind: / {
    kind = $2
    next
  }

  /^  name: / && object_name == "" {
    object_name = $2
    next
  }

  /^  replicas: / {
    replicas = $2 + 0
    next
  }

  /^  maxReplicas: / {
    max_replicas = $2 + 0
    next
  }

  /^    name: / && kind == "HorizontalPodAutoscaler" {
    target_name = $2
    next
  }

  /^          requests:$/ {
    resource_mode = "requests"
    next
  }

  /^          limits:$/ {
    resource_mode = "limits"
    next
  }

  /^            cpu: / && resource_mode == "requests" {
    request_cpu_m += cpu_to_millicores($2)
    next
  }

  /^            memory: / && resource_mode == "requests" {
    request_memory_mi += memory_to_mib($2)
    next
  }

  END {
    record_document()

    for (name in workload) {
      baseline_cpu_m += workload_replicas[name] * workload_cpu_m[name]
      baseline_memory_mi += \
        workload_replicas[name] * workload_memory_mi[name]

      ceiling_replicas = workload_replicas[name]
      if (hpa_max_replicas[name] > ceiling_replicas) {
        ceiling_replicas = hpa_max_replicas[name]
      }
      ceiling_cpu_m += ceiling_replicas * workload_cpu_m[name]
      ceiling_memory_mi += ceiling_replicas * workload_memory_mi[name]
    }

    printf "Production capacity: baseline %.2f CPU / %.2f GiB; ", \
      baseline_cpu_m / 1000, baseline_memory_mi / 1024
    printf "ceiling %.2f CPU / %.2f GiB.\n", \
      ceiling_cpu_m / 1000, ceiling_memory_mi / 1024

    failed = 0
    if (ceiling_cpu_m > cpu_budget_m) {
      printf "CPU request ceiling %.0fm exceeds budget %.0fm.\n", \
        ceiling_cpu_m, cpu_budget_m > "/dev/stderr"
      failed = 1
    }
    if (ceiling_memory_mi > memory_budget_mi) {
      printf "Memory request ceiling %.0fMi exceeds budget %.0fMi.\n", \
        ceiling_memory_mi, memory_budget_mi > "/dev/stderr"
      failed = 1
    }
    exit failed
  }
'
