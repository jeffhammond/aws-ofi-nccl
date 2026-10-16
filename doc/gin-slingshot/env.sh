# Source this inside a job on a compute node (GH200/aarch64). Edit ROOT and the module line for your site.
export ROOT=${ROOT:-$HOME/NCCL/work}          # holds nccl-build, lf-install, ofi-install, ext-build
module load GPU/buildtool-easybuild/5.2.1-hpca3ef7d197 GCC/14.3.0 CUDA/12.9.1 GDRCopy/2.5 \
            MPICH/4.3.2-CUDA-12.9.1 hwloc/2.12.1 >/dev/null 2>&1
export CUDA_HOME=$EBROOTCUDA MPI_HOME=$EBROOTMPICH
export NCCL_HOME=$ROOT/nccl-build NCCL_EP_BUILDDIR=$ROOT/ext-build NCCL_EP_HOME=$ROOT/ext-build
export OFI_PREFIX=$ROOT/ofi-install LF_PREFIX=$ROOT/lf-install

# ---- libraries: our NCCL, our aws-ofi-nccl plugin, our libfabric (stub libs removed from the path)
export LD_LIBRARY_PATH=$NCCL_EP_HOME/lib:$NCCL_HOME/lib:$OFI_PREFIX/lib:$LF_PREFIX/lib64:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=$(echo $LD_LIBRARY_PATH | tr ':' '\n' | grep -v stubs | paste -sd:)
export LD_LIBRARY_PATH=/usr/lib64:$LD_LIBRARY_PATH
export LD_PRELOAD=/usr/lib64/libnvidia-ml.so.1   # the CUDA stub libnvidia-ml breaks NVML otherwise

# ---- REQUIRED for GIN over CXI
export NCCL_NET_PLUGIN=ofi            # load libnccl-net-ofi.so
export NCCL_GIN_TYPE=2                # NCCL proxy GIN (the plugin's RMA backend); 3 = GDAKI (not used here)
export OFI_NCCL_PROTOCOL=RDMA
export FI_PROVIDER=cxi
export FI_CXI_ENABLE_WRITEDATA=1      # CXI fi_writedata (remote CQ data) -- GIN signals depend on it

# ---- used in all validated runs (not individually proven necessary)
export FI_MR_CACHE_MONITOR=userfaultfd FI_CXI_DISABLE_HOST_REGISTER=1
export FI_CXI_DEFAULT_CQ_SIZE=131072 FI_CXI_DEFAULT_TX_SIZE=2048
export NCCL_CROSS_NIC=1 NCCL_NET_GDR_LEVEL=PHB
export UCX_NET_DEVICES=nsc-eth UCX_TLS=tcp,self,sm   # only matters for MPI/UCX-based launch paths
export NCCL_DEBUG=${NCCL_DEBUG:-WARN}

# ---- NCCL EP JIT-compiles kernels at run time and needs these
export NCCL_EP_JIT_SOURCE_DIR=$NCCL_EP_BUILDDIR/include/nccl_ep
export NCCL_EP_JIT_BUILD_INCLUDE_DIR=$NCCL_HOME/include
export NCCL_EP_JIT_CUDA_INCLUDE_DIR=$CUDA_HOME/include
export PATH=$CUDA_HOME/bin:$PATH
export EP_TEST=$NCCL_EP_BUILDDIR/test/nccl_ep/ep_test EP_BENCH=$NCCL_EP_BUILDDIR/test/nccl_ep/ep_bench

# Multi-node launch: epsrun <nodes> <tasks-per-node> <cmd...>
# --network=disable_rdzv_get is required on this system; --mpi=pmi2 (the repo's CI uses pmix).
# Use --cpu-bind=cores -c 72 instead of --cpu-bind=none for 15-22% better EP performance.
epsrun() { local n=$1 t=$2; shift 2
  srun --network=disable_rdzv_get --mpi=pmi2 -N$n --ntasks-per-node=$t --gpus-per-node=4 --gpu-bind=none \
       ${EP_BIND:---cpu-bind=none} --export=ALL timeout ${TMO:-600} "$@" </dev/null; }
