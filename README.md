## Test Info

### Partition
```bash
# 1-basic-rw
kbuild -m overlays/managed-cluster-1/partition/1-basic-rw
kbuild -m overlays/managed-cluster-2/partition/1-basic-rw
kbuild -h overlays/shirly/1-basic-rw/partition

# 2-stress
kbuild -m overlays/managed-cluster-1/partition/2-stress
kbuild -m overlays/managed-cluster-2/partition/2-stress
kbuild -h overlays/shirly/2-stress/partition

# 3-scale
kbuild -m overlays/managed-cluster-1/partition/3-scale
kbuild -m overlays/managed-cluster-2/partition/3-scale
kbuild -h overlays/shirly/3-scale/partition

# 4-argocd-basic-rw (argocd hub)
kbuild -m overlays/managed-cluster-1/partition/4-argocd-basic-rw
kbuild -m overlays/managed-cluster-2/partition/4-argocd-basic-rw
kbuild -h overlays/shirly/1-basic-rw/partition
```

### Non-Partition
```bash
# 1-basic-rw
kbuild -m overlays/managed-cluster-1/non-partition/1-basic-rw
kbuild -m overlays/managed-cluster-2/non-partition/1-basic-rw
kbuild -h overlays/shirly/1-basic-rw/non-partition

# 2-stress
kbuild -m overlays/managed-cluster-1/non-partition/2-stress
kbuild -m overlays/managed-cluster-2/non-partition/2-stress
kbuild -h overlays/shirly/2-stress/non-partition

# 3-scale
kbuild -m overlays/managed-cluster-1/non-partition/3-scale
kbuild -m overlays/managed-cluster-2/non-partition/3-scale
kbuild -h overlays/shirly/3-scale/non-partition

# 4-argocd-basic-rw (argocd hub)
kbuild -m overlays/managed-cluster-1/non-partition/4-argocd-basic-rw
kbuild -m overlays/managed-cluster-2/non-partition/4-argocd-basic-rw
kbuild -h overlays/shirly/1-basic-rw/non-partition
```

### NOTE:
We can also use kapply -r <path> to apply a single raw YAML file directly, without going through kustomize at all. This is useful for one off files like 0-hub-global-prereq/0-reference-combined.yaml, individual split files under rendered/, or any standalone manifest that doesn't need a kustomization.yaml.
```go
kapply -r 2-hub/1-subscription-acm/0-hub-global-prereq/0-reference-combined.yaml
kapply -r 2-hub/1-subscription-acm/rendered/ramen1/1-basic-rw/partition/1-pre-req.yaml
kdelete -r 2-hub/2-argocd/rendered/shirly/1-basic-rw/partition/2-drpc.yaml
```

### Running locally instead of via git URL

Lets take Example of => Partition + 1-basic-rw
```bash
# clone once
git clone https://github.com/parthraaj/ramen-dr-test
cd ramen-dr-test

# 1. See the build manifests
kustomize build 1-managed-cluster/overlays/managed-cluster-1/partition/1-basic-rw
kustomize build 1-managed-cluster/overlays/managed-cluster-2/partition/1-basic-rw
kustomize build 2-hub/1-subscription-acm/overlays/shirly/1-basic-rw/partition

# Apply the manifests
oc apply -k 1-managed-cluster/overlays/managed-cluster-1/partition/1-basic-rw
oc apply -k 1-managed-cluster/overlays/managed-cluster-2/partition/1-basic-rw
oc apply -k 2-hub/1-subscription-acm/overlays/shirly/1-basic-rw/partition
```