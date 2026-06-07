# Preserve live state created by the earlier provider-for_each edge modules
# while the root now uses explicit pt/de provider aliases for OpenTofu test
# compatibility.
moved {
  from = module.garuda_k8s["pt"]
  to   = module.garuda_k8s_pt
}

moved {
  from = module.garuda_k8s["de"]
  to   = module.garuda_k8s_de
}

moved {
  from = module.wireguard_kube["pt"]
  to   = module.wireguard_kube_pt
}

moved {
  from = module.wireguard_kube["de"]
  to   = module.wireguard_kube_de
}
