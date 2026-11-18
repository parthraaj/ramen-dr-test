## Generate Specs for partition & non-partition modes
```go
cd internal
chmod +x generate.sh
./generate.sh partition
./generate.sh non-partition
```

#### Layout (per mode): 30 PVCs x 20Gi, 15 pods (5 writers, 10 readers), 2 PVCs per pod
Each of the 5 StorageClasses/VGs holds 6 PVCs: 1 writer pod (2 PVCs) + 2 reader pods (2 PVCs each).
Writers write chunks of 5% of the volume size to each of their volumes, and delete the oldest chunks from 90% down to 50% usage.

#### NOTE: 30 PVCs x 20Gi = 600Gi provisioned per site. Size of CSI_Parent_Pool should be minimum 1 TB on both Primary & Secondary Storages (leaves headroom for replication snapshots)