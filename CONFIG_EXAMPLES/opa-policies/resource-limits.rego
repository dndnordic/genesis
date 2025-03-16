package kubernetes.admission

import data.kubernetes.namespaces

# Deny containers with no resource limits
deny[msg] {
  input.request.kind.kind == "Pod"
  container := input.request.object.spec.containers[_]
  not container.resources.limits
  msg := sprintf("Container %q has no resource limits", [container.name])
}

# Enforce minimum CPU request
deny[msg] {
  input.request.kind.kind == "Pod"
  container := input.request.object.spec.containers[_]
  not container.resources.requests.cpu
  msg := sprintf("Container %q has no CPU request", [container.name])
}

# Enforce minimum memory request
deny[msg] {
  input.request.kind.kind == "Pod"
  container := input.request.object.spec.containers[_]
  not container.resources.requests.memory
  msg := sprintf("Container %q has no memory request", [container.name])
}

# Verify Origin system has QoS class Guaranteed
deny[msg] {
  input.request.kind.kind == "Pod"
  input.request.namespace == "origin-system"
  container := input.request.object.spec.containers[_]
  not container.resources.limits
  msg := "Origin system pods must have resource limits defined for Guaranteed QoS"
}

# Verify Singularity system has limits defined
deny[msg] {
  input.request.kind.kind == "Pod"
  input.request.namespace == "singularity-system"
  container := input.request.object.spec.containers[_]
  not container.resources.limits
  msg := "Singularity system pods must have resource limits defined"
}

# Enforce CPU limits for Singularity in proportion to namespace quota
deny[msg] {
  input.request.kind.kind == "Pod"
  input.request.namespace == "singularity-system"
  container := input.request.object.spec.containers[_]
  cpu_limit := container.resources.limits.cpu
  to_number(cpu_limit) > 4
  msg := sprintf("Singularity container %q CPU limit exceeds maximum allowed (4 CPU)", [container.name])
}

# Enforce preemption settings for Singularity system
deny[msg] {
  input.request.kind.kind == "Pod"
  input.request.namespace == "singularity-system"
  not input.request.object.spec.preemptionPolicy
  msg := "Singularity pods must have preemptionPolicy set to PreemptLowerPriority"
}