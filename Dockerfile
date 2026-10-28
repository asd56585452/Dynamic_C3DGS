# ==============================================================================
# Dynamic_C3DGS Dockerfile
# Based on asdggg/gscodec-studio:latest
# Provides PyTorch 2.9 (CUDA 13.0, sm_120 / RTX 5070 support), GCC, CMake, COLMAP.
# ==============================================================================

ARG BASE_IMAGE=asdggg/gscodec-studio:latest
FROM ${BASE_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive
ENV TORCH_CUDA_ARCH_LIST="8.6;8.9;12.0"
ENV TCNN_CUDA_ARCHITECTURES="86;89;120"
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics

WORKDIR /workspace

# 1. Install Python dependencies
COPY requirements.txt /tmp/requirements.txt
RUN pip install --upgrade pip && \
    pip install --no-cache-dir -r /tmp/requirements.txt && \
    rm -rf /tmp/requirements.txt

# 2. Install mmcv without build isolation
RUN pip install --no-cache-dir --no-build-isolation mmcv

# 3. Install tiny-cuda-nn
RUN pip install --no-cache-dir --no-build-isolation git+https://github.com/NVlabs/tiny-cuda-nn/#subdirectory=bindings/torch

# 4. Copy submodules and compile CUDA rasterizer + simple-knn
COPY thirdparty/gaussian_splatting/submodules/gaussian_rasterization_ch9 /tmp/gaussian_rasterization_ch9
COPY thirdparty/gaussian_splatting/submodules/simple-knn /tmp/simple-knn

RUN pip install --no-cache-dir --no-build-isolation /tmp/gaussian_rasterization_ch9 && \
    pip install --no-cache-dir --no-build-isolation /tmp/simple-knn && \
    rm -rf /tmp/gaussian_rasterization_ch9 /tmp/simple-knn

WORKDIR /workspace
CMD ["/bin/bash"]
