# If you don't have ramen operator with vol translation support

## Method 1: Use Script to patch volumeHandles of PV after Creation of resources on Primary site
```go
#!/bin/bash
# Usage: ./0-pv-patch.sh [-n <namespace>] [-p <pvc-name>] <new-handle> [<new-handle-2> ...]
#   -p <pvc-name>   Target a single specific PVC (skips count-matching against all PVCs in ns)
#   (no -p)         Original behavior: handles must match ALL PVCs in namespace, in oc get order

set -e

NAMESPACE=""
TARGET_PVC=""
NEW_HANDLES=()

while [[ $# -gt 0 ]]; do
    case $1 in
        -n)
            NAMESPACE="$2"
            shift 2
            ;;
        -p)
            TARGET_PVC="$2"
            shift 2
            ;;
        *)
            NEW_HANDLES+=("$1")
            shift
            ;;
    esac
done

if [ -z "$NAMESPACE" ]; then
    NAMESPACE=$(oc project -q 2>/dev/null || echo "")
    if [ -z "$NAMESPACE" ]; then
        echo "ERROR: Could not detect current namespace. Please specify using -n <namespace>"
        exit 1
    fi
fi

echo "Target Namespace: $NAMESPACE"

if [ -n "$TARGET_PVC" ]; then
    # ---- Single PVC mode ----
    echo "Target PVC (single): $TARGET_PVC"

    if [ "${#NEW_HANDLES[@]}" -ne 1 ]; then
        echo "ERROR: -p mode requires exactly ONE new handle. Got ${#NEW_HANDLES[@]}."
        exit 1
    fi

    echo "Waiting for PVC '$TARGET_PVC' to appear in namespace '$NAMESPACE'..."
    while true; do
        if oc get pvc "$TARGET_PVC" -n "$NAMESPACE" &>/dev/null; then
            echo "Found PVC '$TARGET_PVC'."
            break
        fi
        sleep 0.5
    done

    MAPFILE_PVCS=("$TARGET_PVC")
else
    # ---- Original all-PVC mode ----
    echo "Waiting for PVCs to appear in namespace '$NAMESPACE'..."
    while true; do
        MAPFILE_PVCS=($(oc get pvc -n "$NAMESPACE" --no-headers -o custom-columns=":metadata.name" 2>/dev/null || true))
        if [ "${#MAPFILE_PVCS[@]}" -gt 0 ]; then
            echo "Found ${#MAPFILE_PVCS[@]} PVC(s)."
            break
        fi
        sleep 0.1
    done

    NUM_PVCS=${#MAPFILE_PVCS[@]}
    NUM_HANDLES=${#NEW_HANDLES[@]}

    if [ "$NUM_PVCS" -ne "$NUM_HANDLES" ]; then
        echo "ERROR: Mismatch between found PVCs ($NUM_PVCS) and provided handles ($NUM_HANDLES)."
        echo "Expected exactly $NUM_PVCS handles matching this 'oc get pvc' order:"
        for i in "${!MAPFILE_PVCS[@]}"; do
            echo "  [$((i+1))] ${MAPFILE_PVCS[$i]}"
        done
        echo ""
        echo "TIP: To patch a single PVC instead, use: -p <pvc-name> <new-handle>"
        exit 1
    fi
fi

NUM_PVCS=${#MAPFILE_PVCS[@]}

echo ""
echo "=== Mapping Matrix ==="
for i in $(seq 0 $((NUM_PVCS - 1))); do
    PVC_NAME="${MAPFILE_PVCS[$i]}"
    NEW_HANDLE="${NEW_HANDLES[$i]}"
    PV_NAME=$(oc get pvc "$PVC_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.volumeName}')

    if [ -z "$PV_NAME" ]; then
        echo "ERROR: PVC $PVC_NAME is not bound to a PV. Aborting."
        exit 1
    fi
    echo "[$((i+1))] PVC: $PVC_NAME  -->  PV: $PV_NAME  -->  New Handle: $NEW_HANDLE"
done

echo ""
echo "Executing updates immediately..."

for i in $(seq 0 $((NUM_PVCS - 1))); do
    PVC_NAME="${MAPFILE_PVCS[$i]}"
    NEW_HANDLE="${NEW_HANDLES[$i]}"
    PV_NAME=$(oc get pvc "$PVC_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.volumeName}')
    PVC_UID=$(oc get pvc "$PVC_NAME" -n "$NAMESPACE" -o jsonpath='{.metadata.uid}')
    OLD_HANDLE=$(oc get pv "$PV_NAME" -o jsonpath='{.spec.csi.volumeHandle}')

    echo "--------------------------------------------------------"
    echo "Processing [$((i+1))/$NUM_PVCS]: $PVC_NAME ($PV_NAME)..."
    echo "--------------------------------------------------------"

    echo "Step 1: Remove ramen annotations from PV..."
    oc annotate pv "$PV_NAME" \
      volumereplicationgroups.ramendr.openshift.io/ramen-restore- \
      volumereplicationgroups.ramendr.openshift.io/vr-archived- \
      volumereplicationgroups.ramendr.openshift.io/vr-retained- \
      2>/dev/null || true

    echo "Step 2: Exporting and sanitizing PV manifest..."
    TMPFILE=$(mktemp /tmp/pv-fixed-XXXXXX.yaml)
    oc get pv "$PV_NAME" -oyaml > "$TMPFILE"

    sed -i "s@${OLD_HANDLE}@${NEW_HANDLE}@g" "$TMPFILE"
    sed -i '/ramen-restore/d' "$TMPFILE"
    sed -i '/vr-archived/d' "$TMPFILE"
    sed -i '/vr-retained/d' "$TMPFILE"
    sed -i '/resourceVersion:/d' "$TMPFILE"
    sed -i '/uid:/d' "$TMPFILE"
    sed -i '/creationTimestamp:/d' "$TMPFILE"
    sed -i '/lastPhaseTransitionTime/d' "$TMPFILE"
    sed -i '/  phase:/d' "$TMPFILE"
    sed -i '/^status:/d' "$TMPFILE"

    echo "Step 3: Replacing PV..."
    oc delete pv "$PV_NAME" --wait=false
    sleep 3

    if oc get pv "$PV_NAME" &>/dev/null; then
        echo "PV stuck, clearing finalizers..."
        oc patch pv "$PV_NAME" -p '{"metadata":{"finalizers":[]}}' --type=merge
    fi

    while oc get pv "$PV_NAME" &>/dev/null; do sleep 1; done

    oc apply -f "$TMPFILE"
    rm -f "$TMPFILE"

    echo "Step 4: Fixing PVC binding..."
    oc annotate pvc "$PVC_NAME" -n "$NAMESPACE" pv.kubernetes.io/bind-completed- 2>/dev/null || true

    oc patch pv "$PV_NAME" --type=merge -p \
      "{\"spec\":{\"claimRef\":{\"uid\":\"$PVC_UID\",\"namespace\":\"$NAMESPACE\",\"name\":\"$PVC_NAME\"}}}"

    echo "Step 5: Verifying Rebind..."
    for attempt in $(seq 1 15); do
        STATUS=$(oc get pvc "$PVC_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
        if [ "$STATUS" = "Bound" ]; then
            echo "SUCCESS: $PVC_NAME is Bound."
            break
        fi
        sleep 2
    done
done

echo ""
echo "=== Final Status Check ==="
oc get pvc -n "$NAMESPACE"
```

### To use it:
**Single PVC:**
```bash
./0-pv-patch.sh -n <namespace> -p <pvc-name> <new-volume-handle>
```

**All PVCs in namespace (positional order = `oc get pvc` order):**
```bash
./0-pv-patch.sh -n <namespace> <handle-1> <handle-2> <handle-3> ...
```

- `-n` omitted → uses current `oc project`
- In non-p mode, the number of handles you pass must equal the number of PVCs in the namespace. The order matters too: handle 1 goes to the first PVC from oc get pvc, handle 2 to the second, and so on. Before applying anything, the script prints this PVC-to-handle mapping so you can check it's correct.

---

## Method 2: Use custom image with fix & patch it in ramen cluster operator

```go
CSV=$(oc get deploy ramen-dr-cluster-operator \
  -n openshift-dr-system \
  -o jsonpath='{.metadata.ownerReferences[?(@.kind=="ClusterServiceVersion")].name}')

oc patch csv "$CSV" \
  -n openshift-dr-system \
  --type=json \
  -p='[
    {
      "op":"replace",
      "path":"/spec/install/spec/deployments/0/spec/template/spec/containers/0/image",
      "value":"quay.io/egershko/ramen-operator:silver"
    }
  ]'
```