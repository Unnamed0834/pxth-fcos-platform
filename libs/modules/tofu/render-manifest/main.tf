











locals {
  manifest = jsondecode(file(var.manifest_path))


  is_multi_node = var.multi_node


  container_images = {
    for key, artifact in local.manifest.artifacts :
    key => (
      contains([null, "container"], try(artifact.type, "container"))
      ? (
        try(artifact.image, "") != ""
        ? (
          startswith(try(artifact.image, ""), "localhost/")
          ? try(artifact.image, "")
          : (
            strcontains(try(artifact.image, ""), "/")
            ? try(artifact.image, "")
            : "docker.io/library/${try(artifact.image, "")}"
          )
        )
        : ""
      )
      : try(artifact.image, "")
    )
  }


  ignition_path = var.ignition_config != "" ? var.ignition_config : "${var.node_name}-config.bu"





  image_ignition_vars = {
    for key, artifact in local.manifest.artifacts :
    (try(artifact.ignition_var, "${replace(replace(key, "-", "_"), ".", "_")}_image")) =>
    (contains([null, "container"], try(artifact.type, "container"))
      ? (
        try(artifact.image, "") != ""
        ? (
          startswith(try(artifact.image, ""), "localhost/")
          ? try(artifact.image, "")
          : (
            strcontains(try(artifact.image, ""), "/")
            ? try(artifact.image, "")
            : "docker.io/library/${try(artifact.image, "")}"
          )
        )
        : ""
      )
      : try(artifact.image, "")
    )
  }


  manifest_metadata_vars = {
    for k, v in local.manifest :
    replace(k, "-", "_") => v
    if contains(["inference_engine", "workload_preset", "nvidia_driver_version"], k)
  }


  ignition_vars = merge(
    local.image_ignition_vars,
    local.manifest_metadata_vars,
    var.ignition_extra_vars
  )

}
