## Kustomize build commands

#### Partition
```go
kustomize build overlays/managed-cluster-1/partition/1-basic-rw
kustomize build overlays/managed-cluster-2/partition/1-basic-rw

kustomize build overlays/managed-cluster-1/partition/2-stress
kustomize build overlays/managed-cluster-2/partition/2-stress

kustomize build overlays/managed-cluster-1/partition/3-scale
kustomize build overlays/managed-cluster-2/partition/3-scale

kustomize build overlays/managed-cluster-1/partition/4-argocd-basic-rw
kustomize build overlays/managed-cluster-2/partition/4-argocd-basic-rw
```

#### Non-Partition
```go
kustomize build overlays/managed-cluster-1/non-partition/1-basic-rw
kustomize build overlays/managed-cluster-2/non-partition/1-basic-rw


kustomize build overlays/managed-cluster-1/non-partition/2-stress
kustomize build overlays/managed-cluster-2/non-partition/2-stress

kustomize build overlays/managed-cluster-1/non-partition/3-scale
kustomize build overlays/managed-cluster-2/non-partition/3-scale

kustomize build overlays/managed-cluster-1/non-partition/4-argocd-basic-rw
kustomize build overlays/managed-cluster-2/non-partition/4-argocd-basic-rw
```

---
#### NOTE:
```go
- We can Direct apply without separate build: oc apply -k <path>
- We can Direct apply from git, no local checkout needed: oc apply -k https://github.com/parthraaj/ramen-test//path/to/overlay?ref=main
```
----

### Resources to be Present on Primary Storage

1. **Pool**: `CSI_Parent_Pool` should be present on both storages.
2. **Volume group**: As mentioned in table
3. **Partition**: `Ramen-DR-Partition-Parth` to be present on both storages and DR linked.
4. **Replication Policies**: `partition-async-dr` & `np-2-site-async-dr` to be created on both storages.

---
### Volume group names for each case
| Scenario | Mode | `volume_group` name(s) | `replication_policy` |
|---|---|---|---|
| 1-basic-rw | partition | `parth-ramen-basic-rw-partition-dr` | `partition-async-dr` |
| 1-basic-rw | non-partition | `parth-ramen-basic-rw-non-partition-dr` | `np-2-site-async-dr` |
| 2-stress | partition | `parth-ramen-stress-a-partition-dr`, `parth-ramen-stress-b-partition-dr` | `partition-async-dr` |
| 2-stress | non-partition | `parth-ramen-stress-a-non-partition-dr`, `parth-ramen-stress-b-non-partition-dr` | `np-2-site-async-dr` |
| 3-scale | partition | `parth-ramen-scale-1-partition-dr`, `-2-`, `-3-`, `-4-`, `-5-partition-dr` | `partition-async-dr` |
| 3-scale | non-partition | `parth-ramen-scale-1-non-partition-dr`, `-2-`, `-3-`, `-4-`, `-5-non-partition-dr` | `np-2-site-async-dr` |
| 4-argocd-basic-rw | partition | `parth-ramen-argocd-basic-rw-partition-dr` | `partition-async-dr` |
| 4-argocd-basic-rw | non-partition | `parth-ramen-argocd-basic-rw-non-partition-dr` | `np-2-site-async-dr` |


----

### Generate updated manifests
```go
for f in overlays/*/*/*; do
  outdir="rendered/${f#overlays/}"
  mkdir -p "$outdir"
  kustomize build "$f" > "$outdir/manifest.yaml"
  echo "wrote $outdir/manifest.yaml"
done
```