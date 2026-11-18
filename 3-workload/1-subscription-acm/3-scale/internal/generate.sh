#!/bin/bash
set -euo pipefail

MODE="${1:?Usage: ./generate.sh <partition|non-partition>}"
if [ "$MODE" != "partition" ] && [ "$MODE" != "non-partition" ]; then
  echo "MODE must be 'partition' or 'non-partition'"
  exit 1
fi

# Layout: 30 PVCs, 15 pods (5 writers, 10 readers), 2 PVCs per pod.
# Each StorageClass/VG gets 6 PVCs: 1 writer pod (2 PVCs) + 2 reader pods (2 PVCs each),
# so every VG has write I/O during replication.
NUM_SC=5
PVCS_PER_POD=2
WRITER_PODS_PER_SC=1
READER_PODS_PER_SC=2
PODS_PER_SC=$((WRITER_PODS_PER_SC + READER_PODS_PER_SC))
PER_SC=$((PODS_PER_SC * PVCS_PER_POD))
TOTAL=$((NUM_SC * PER_SC))
SIZE_GI=20
SIZE="${SIZE_GI}Gi"
# Writer chunk = 5% of the volume size (20Gi -> 1024 MB), so it scales with SIZE_GI.
CHUNK_MB=$((SIZE_GI * 1024 / 20))
NAMESPACE="scale-${MODE}-dr"
APPNAME="scale-${MODE}-dr"

SCS=(sc-scale-1-${MODE}-dr sc-scale-2-${MODE}-dr sc-scale-3-${MODE}-dr sc-scale-4-${MODE}-dr sc-scale-5-${MODE}-dr)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTDIR="$SCRIPT_DIR/../${MODE}/generated"
rm -rf "$OUTDIR"

RESOURCE_LIST=()

PVC_IDX=1
WRITER_IDX=1
READER_IDX=1

write_pvc() {
  local sc="$1" i="$2"
  local f="$OUTDIR/pvcs/$sc/pvc-scale-$i.yaml"
  cat > "$f" <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-scale-$i
  labels:
    appname: $APPNAME
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: $sc
  resources:
    requests:
      storage: $SIZE
EOF
  RESOURCE_LIST+=("generated/pvcs/$sc/pvc-scale-$i.yaml")
}

# $1=first PVC index; print volumeMounts/volumes for PVCS_PER_POD consecutive PVCs
mounts_yaml() {
  local first="$1"
  for n in $(seq 1 "$PVCS_PER_POD"); do
    echo "            - name: data$n"
    echo "              mountPath: /data$n"
  done
}
volumes_yaml() {
  local first="$1"
  for n in $(seq 1 "$PVCS_PER_POD"); do
    echo "        - name: data$n"
    echo "          persistentVolumeClaim:"
    echo "            claimName: pvc-scale-$((first + n - 1))"
  done
}

DIRS=""
for n in $(seq 1 "$PVCS_PER_POD"); do DIRS="$DIRS /data$n"; done
DIRS="${DIRS# }"

write_writer() {
  local sc="$1" name="$2" first="$3"
  local f="$OUTDIR/deployments/writer/$sc/$name.yaml"
  cat > "$f" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $name
  labels:
    appname: $APPNAME
spec:
  replicas: 1
  selector:
    matchLabels:
      app-key: $name
  template:
    metadata:
      labels:
        app-key: $name
        appname: $APPNAME
        scale-test: spread
    spec:
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              scale-test: spread
      containers:
        - name: logger
          image: quay.io/nirsof/busybox:stable
          imagePullPolicy: IfNotPresent
          command:
            - sh
            - -c
            - |
              # One write loop per volume. Each loop writes ${CHUNK_MB} MB chunks (5% of $SIZE),
              # and when the volume reaches 90% it deletes oldest chunks down to 50%.
              usage() { df "\$1" | awk 'NR==2 {gsub("%","",\$5); print \$5}'; }
              emit() {
                  echo "\$(date) \$2" | tee -a "\$1/ramen.log"
                  sync
              }
              writer() {
                  d=\$1
                  emit "\$d" START
                  i=0
                  while true; do
                      u=\$(usage "\$d")
                      if [ "\$u" -ge 90 ]; then
                          emit "\$d" "usage \${u}%, cleaning up to 50%"
                          while [ "\$u" -ge 50 ]; do
                              oldest=\$(ls -tr "\$d"/chunk_*.bin 2>/dev/null | head -1)
                              [ -z "\$oldest" ] && break
                              rm -f "\$oldest"
                              u=\$(usage "\$d")
                          done
                          emit "\$d" "usage now \${u}%"
                      fi
                      dd if=/dev/zero of="\$d/chunk_\$i.bin" bs=1M count=$CHUNK_MB status=none
                      sync
                      i=\$((i+1))
                      emit "\$d" "UPDATE usage \$(usage "\$d")%"
                      sleep 10
                  done
              }
              pids=""
              trap 'kill \$pids 2>/dev/null; for d in $DIRS; do emit "\$d" STOP; done; exit' TERM
              for d in $DIRS; do
                  writer "\$d" &
                  pids="\$pids \$!"
              done
              wait
          volumeMounts:
$(mounts_yaml "$first")
      volumes:
$(volumes_yaml "$first")
EOF
  RESOURCE_LIST+=("generated/deployments/writer/$sc/$name.yaml")
}

write_reader() {
  local sc="$1" name="$2" first="$3"
  local f="$OUTDIR/deployments/reader/$sc/$name.yaml"
  cat > "$f" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $name
  labels:
    appname: $APPNAME
spec:
  replicas: 1
  selector:
    matchLabels:
      app-key: $name
  template:
    metadata:
      labels:
        app-key: $name
        appname: $APPNAME
        scale-test: spread
    spec:
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              scale-test: spread
      containers:
        - name: busybox
          image: quay.io/nirsof/busybox:stable
          command: ["tail", "-f", "/dev/null"]
          volumeMounts:
$(mounts_yaml "$first")
      volumes:
$(volumes_yaml "$first")
EOF
  RESOURCE_LIST+=("generated/deployments/reader/$sc/$name.yaml")
}

for sc_idx in $(seq 0 $((NUM_SC - 1))); do
  SC="${SCS[$sc_idx]}"
  mkdir -p "$OUTDIR/pvcs/$SC"

  for _ in $(seq 1 "$WRITER_PODS_PER_SC"); do
    mkdir -p "$OUTDIR/deployments/writer/$SC"
    first=$PVC_IDX
    for _ in $(seq 1 "$PVCS_PER_POD"); do write_pvc "$SC" "$PVC_IDX"; PVC_IDX=$((PVC_IDX + 1)); done
    write_writer "$SC" "deploy-scale-writer-$WRITER_IDX" "$first"
    WRITER_IDX=$((WRITER_IDX + 1))
  done

  for _ in $(seq 1 "$READER_PODS_PER_SC"); do
    mkdir -p "$OUTDIR/deployments/reader/$SC"
    first=$PVC_IDX
    for _ in $(seq 1 "$PVCS_PER_POD"); do write_pvc "$SC" "$PVC_IDX"; PVC_IDX=$((PVC_IDX + 1)); done
    write_reader "$SC" "deploy-scale-reader-$READER_IDX" "$first"
    READER_IDX=$((READER_IDX + 1))
  done
done

KFILE="$SCRIPT_DIR/../${MODE}/kustomization.yaml"
{
  echo "resources:"
  for f in "${RESOURCE_LIST[@]}"; do
    echo "  - $f"
  done
  echo "namespace: $NAMESPACE"
} > "$KFILE"

echo "Generated $TOTAL PVCs x $SIZE across $NUM_SC storage classes for mode=$MODE."
echo "  Namespace: $NAMESPACE"
echo "  Per SC: $WRITER_PODS_PER_SC writer + $READER_PODS_PER_SC reader pods, $PVCS_PER_POD PVCs each ($PER_SC PVCs)"
echo "  Pods: $((WRITER_IDX - 1)) writers, $((READER_IDX - 1)) readers; writer chunk ${CHUNK_MB} MB"
echo "Structure: ../$MODE/generated/pvcs/<sc>/... and ../$MODE/generated/deployments/<role>/<sc>/..."
echo "kustomization.yaml written to $KFILE"
