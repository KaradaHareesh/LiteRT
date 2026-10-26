#!/usr/bin/env bash
# Copyright 2026 The AI Edge LiteRT Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ==============================================================================
set -e
set -x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${LITERT_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
LITERT_DIR="${ROOT_DIR}"

ESDK_DEFAULT_ROOT="/opt/toolchains/qcom-esdk-gcc11.2"
ESDK_URL="https://artifacts.codelinaro.org/artifactory/qli-ci/flashable-binaries/qimpsdk/qcs8275-iq-8275-evk-pro-sku/x86-qcom-6.6.119-QLI.1.8-Ver.1.0_qim-product-sdk-esdk-2.3.0.zip"
ESDK_INSTALLER_REL="target/qcs8275-iq-8275-evk-pro-sku/sdk/qcom-wayland-x86_64-qcom-multimedia-image-armv8-2a-qcs8275-iq-8275-evk-pro-sku-toolchain-ext-1.8-ver.1.0.sh"

install_and_prune_esdk() {
  local esdk_root="${LINUX_AARCH64_ESDK:-${ESDK_DEFAULT_ROOT}}"
  local esdk_gcc="${esdk_root}/tmp/sysroots/x86_64/usr/bin/aarch64-qcom-linux/aarch64-qcom-linux-gcc"
  if [[ -x "${esdk_gcc}" ]]; then
    echo "Qualcomm OpenEmbedded eSDK already present at ${esdk_root}"
    mkdir -p "${esdk_root}/tmp/sysroots-uninative/x86_64-linux/lib"
    ln -sf /lib64/ld-linux-x86-64.so.2 "${esdk_root}/tmp/sysroots-uninative/x86_64-linux/lib/ld-linux-x86-64.so.2"
    return 0
  fi

  local esdk_parent
  esdk_parent="$(dirname "${esdk_root}")"
  local tmp_esdk="/tmp/esdk11_2"
  rm -rf "${tmp_esdk}"
  mkdir -p "${esdk_parent}" "${tmp_esdk}"

  echo "Downloading Qualcomm OpenEmbedded eSDK from ${ESDK_URL}..."
  pushd "${tmp_esdk}" > /dev/null
  wget -q "${ESDK_URL}" -O esdk.zip
  unzip -q esdk.zip "target/qcs8275-iq-8275-evk-pro-sku/sdk/*.sh"
  rm -f esdk.zip
  chmod +x "./${ESDK_INSTALLER_REL}"

  # Yocto/eSDK installers forbid execution as root (UID 0).
  if [[ "$(id -u)" -eq 0 ]]; then
    if ! id -u builder >/dev/null 2>&1; then
      groupadd builder 2>/dev/null || true
      useradd -m -g builder -s /bin/bash builder
    fi
    mkdir -p "${esdk_root}"
    chown builder:builder "${esdk_parent}"
    chown -R builder:builder "${esdk_root}" "${tmp_esdk}"
    su -s /bin/bash builder -c 'sh "$1" -y -d "$2"' _ "${tmp_esdk}/${ESDK_INSTALLER_REL}" "${esdk_root}"
  else
    sh "./${ESDK_INSTALLER_REL}" -y -d "${esdk_root}"
  fi
  popd > /dev/null

  echo "Pruning non-compiler/sysroot overhead in ${esdk_root}..."
  rm -rf "${esdk_root}/sstate-cache" \
         "${esdk_root}/layers" \
         "${esdk_root}/bitbake" \
         "${esdk_root}/downloads" \
         "${esdk_root}/buildtools" \
         "${esdk_root}/tmp-qcom-guestvm" \
         "${esdk_root}/tmp/work" \
         "${esdk_root}/tmp/work-shared" \
         "${esdk_root}/tmp/sysroots-components" \
         "${esdk_root}/tmp/sysroots-uninative" \
         "${esdk_root}/tmp/deploy" \
         "${esdk_root}/tmp/cache" \
         "${esdk_root}/tmp/pkgdata" \
         "${esdk_root}/tmp/log" \
         "${esdk_root}/tmp/sstate-control" \
         "${esdk_root}/tmp/stamps" \
         "${esdk_root}/tmp/sysroots/"*/usr/share \
         "${esdk_root}/tmp/sysroots/"*/manifest-* \
         "${esdk_root}/tmp/sysroots/"*/sysroot-providers \
         "${esdk_root}/tmp/sysroots/"*/etc \
         "${esdk_root}/tmp/sysroots/"*/var
  find "${esdk_root}/tmp/sysroots/x86_64/usr/bin" -mindepth 1 -maxdepth 1 ! -name "aarch64-qcom-linux" -exec rm -rf {} +
  rm -rf "${esdk_root}/tmp/sysroots/x86_64/usr/include" \
         "${esdk_root}/tmp/sysroots/x86_64/usr/sbin" \
         "${esdk_root}/tmp/sysroots/x86_64/bin" \
         "${esdk_root}/tmp/sysroots/x86_64/sbin" \
         "${esdk_root}/tmp/sysroots/x86_64/lib"
  find "${esdk_root}/tmp/sysroots/x86_64/usr/lib" -mindepth 1 -maxdepth 1 -type d ! -name "aarch64-qcom-linux" -exec rm -rf {} +
  rm -f "${esdk_root}/tmp/sysroots/x86_64/usr/lib/"*.a \
        "${esdk_root}/tmp/sysroots/x86_64/usr/lib/librustc"* \
        "${esdk_root}/tmp/sysroots/x86_64/usr/lib/libLLVM"* \
        "${esdk_root}/tmp/sysroots/x86_64/usr/lib/libicudata"* \
        "${esdk_root}/tmp/sysroots/x86_64/usr/lib/libclang"* \
        "${esdk_root}/tmp/sysroots/x86_64/usr/lib/libLTO"*

  local target_sysroot="${esdk_root}/tmp/sysroots/qcs8275-iq-8275-evk-pro-sku"
  rm -rf "${target_sysroot}/usr/bin" \
         "${target_sysroot}/usr/sbin" \
         "${target_sysroot}/usr/libexec" \
         "${target_sysroot}/usr/src" \
         "${target_sysroot}/usr/games" \
         "${target_sysroot}/bin" \
         "${target_sysroot}/sbin" \
         "${target_sysroot}/usr/include/boost" \
         "${target_sysroot}/usr/include/autogen" \
         "${target_sysroot}/usr/include/opencv4" \
         "${target_sysroot}/usr/include/tensorflow" \
         "${target_sysroot}/usr/include/eigen3" \
         "${target_sysroot}/usr/include/absl" \
         "${target_sysroot}/usr/include/google" \
         "${target_sysroot}/usr/include/gstreamer"* \
         "${target_sysroot}/usr/include/chi-cdk"* \
         "${target_sysroot}/usr/include/camx"* \
         "${target_sysroot}/usr/include/vulkan"
  find "${target_sysroot}/usr/lib" -mindepth 1 -maxdepth 1 -type d ! -name "aarch64-qcom-linux" ! -name "gcc" -exec rm -rf {} +
  find "${target_sysroot}/usr/lib" -maxdepth 1 \( -type f -o -type l \) \
    ! -name "ld-*" ! -name "*crt*.o" \
    ! -name "libc.*" ! -name "libc-*" ! -name "libc_*" \
    ! -name "libm.*" ! -name "libm-*" ! -name "libmvec*" \
    ! -name "libdl*" ! -name "libpthread*" ! -name "librt*" \
    ! -name "libresolv*" ! -name "libutil*" ! -name "libanl*" ! -name "libnsl*" ! -name "libcrypt.*" ! -name "libcrypt-*" ! -name "libnss*" ! -name "libBrokenLocale*" ! -name "libthread_db*" \
    ! -name "libstdc++*" ! -name "libsupc++*" ! -name "libgcc*" ! -name "libatomic*" ! -name "libgomp*" ! -name "libitm*" ! -name "libasan*" ! -name "libtsan*" ! -name "libubsan*" ! -name "liblsan*" ! -name "libhwasan*" ! -name "libssp*" ! -name "libquadmath*" \
    ! -name "libz.*" ! -name "libz-*" \
    -delete

  mkdir -p "${esdk_root}/tmp/sysroots-uninative/x86_64-linux/lib"
  ln -sf /lib64/ld-linux-x86-64.so.2 "${esdk_root}/tmp/sysroots-uninative/x86_64-linux/lib/ld-linux-x86-64.so.2"
  chmod -R a+rX "${esdk_root}"
  rm -rf "${tmp_esdk}"
}

if [[ "${SETUP_ESDK_ONLY:-false}" == "true" ]]; then
  install_and_prune_esdk
  exit 0
fi

OUTPUT_DIR="${OUTPUT_DIR:-/tmp/litert_binaries}"
mkdir -p "${OUTPUT_DIR}"
OUTPUT_DIR="$(cd "${OUTPUT_DIR}" && pwd)"

if [[ ! -d "${LITERT_DIR}/litert" || ! -d "${LITERT_DIR}/tflite" ]]; then
  echo "ERROR: LiteRT source tree ('${LITERT_DIR}') is missing 'litert' or 'tflite' directory." >&2
  echo "Please run this script from the root of the LiteRT repository or specify LITERT_DIR." >&2
  exit 1
fi

run_build_and_stage() {
  local platform="${PLATFORM:-aarch64-oe-linux-gcc11.2}"
  local preset="${PRESET:-linux-aarch64-oe-gcc11.2}"
  local bdir="${BDIR:-cmake_build_linux_aarch64_oe_gcc11_2}"
  local jobs="${JOBS:-$(nproc)}"

  if [[ -z "${LINUX_AARCH64_ESDK:-}" && -d "${ESDK_DEFAULT_ROOT}" ]]; then
    export LINUX_AARCH64_ESDK="${ESDK_DEFAULT_ROOT}"
  fi
  if [[ -n "${LINUX_AARCH64_ESDK:-}" && -d "${LINUX_AARCH64_ESDK}" ]]; then
    mkdir -p "${LINUX_AARCH64_ESDK}/tmp/sysroots-uninative/x86_64-linux/lib"
    ln -sf /lib64/ld-linux-x86-64.so.2 "${LINUX_AARCH64_ESDK}/tmp/sysroots-uninative/x86_64-linux/lib/ld-linux-x86-64.so.2"
    export PATH="${PATH}:${LINUX_AARCH64_ESDK}/tmp/sysroots/x86_64/usr/bin/aarch64-qcom-linux"
  fi

  trap 'if [[ -n "${HOST_UID:-}" && -n "${HOST_GID:-}" ]]; then chown -R "${HOST_UID}:${HOST_GID}" "${OUTPUT_DIR}" "${LITERT_DIR}" 2>/dev/null || true; fi' EXIT

  pushd "${LITERT_DIR}/litert" > /dev/null
  echo "=== Building LiteRT for ${platform} (${preset}) ==="
  cmake --preset "${preset}"
  cmake --build "${bdir}" \
    --target litert_runtime_c_api_shared_lib dispatch_api_qualcomm_so qnn_compiler_plugin run_model apply_plugin_main \
    -j "${jobs}"

  # Stage release binaries
  local plat_out="${OUTPUT_DIR}/${platform}"
  mkdir -p "${plat_out}"
  cp -f "${bdir}/c/libLiteRt.so" "${plat_out}/"
  cp -f "${bdir}/vendors/qualcomm/dispatch/libLiteRtDispatch_Qualcomm.so" "${plat_out}/"
  cp -f "${bdir}/vendors/qualcomm/compiler/libLiteRtCompilerPlugin_Qualcomm.so" "${plat_out}/"
  cp -f "${bdir}/tools/run_model" "${plat_out}/"
  cp -f "${bdir}/tools/apply_plugin_main" "${plat_out}/"

  # Ensure RPATH is exactly $ORIGIN for dynamic shared plugins
  if command -v chrpath >/dev/null 2>&1; then
    chrpath -r '$ORIGIN' "${plat_out}/libLiteRtDispatch_Qualcomm.so"
    chrpath -r '$ORIGIN' "${plat_out}/libLiteRtCompilerPlugin_Qualcomm.so"
  else
    echo "WARNING: chrpath not found; relying on CMake link-time INSTALL_RPATH (\$ORIGIN)" >&2
  fi

  # Strip release binaries using cross-strip
  local strip_bin=""
  if [[ -n "${STRIP:-}" ]] && command -v "${STRIP}" >/dev/null 2>&1; then
    strip_bin="${STRIP}"
  elif command -v aarch64-qcom-linux-strip >/dev/null 2>&1; then
    strip_bin="aarch64-qcom-linux-strip"
  elif [[ -n "${LINUX_AARCH64_ESDK:-}" && -x "${LINUX_AARCH64_ESDK}/tmp/sysroots/x86_64/usr/bin/aarch64-qcom-linux/aarch64-qcom-linux-strip" ]]; then
    strip_bin="${LINUX_AARCH64_ESDK}/tmp/sysroots/x86_64/usr/bin/aarch64-qcom-linux/aarch64-qcom-linux-strip"
  elif command -v aarch64-linux-gnu-strip >/dev/null 2>&1; then
    strip_bin="aarch64-linux-gnu-strip"
  else
    echo "ERROR: No aarch64 strip binary found (aarch64-qcom-linux-strip or aarch64-linux-gnu-strip)" >&2
    exit 1
  fi
  "${strip_bin}" --strip-unneeded \
    "${plat_out}/"*.so \
    "${plat_out}/run_model" \
    "${plat_out}/apply_plugin_main"

  # Log SHA256 checksums
  pushd "${plat_out}" > /dev/null
  sha256sum libLiteRt.so libLiteRtDispatch_Qualcomm.so libLiteRtCompilerPlugin_Qualcomm.so run_model apply_plugin_main
  popd > /dev/null

  popd > /dev/null
}

if [[ "${RUN_DIRECTLY:-false}" == "true" ]]; then
  run_build_and_stage
  echo "Direct build completed. Release packages available at: ${OUTPUT_DIR}"
  exit 0
fi

DOCKER_IMAGE="${DOCKER_IMAGE:-litert-iot-linux:latest}"
DOCKERFILE="${SCRIPT_DIR}/litert-iot-linux.Dockerfile"

if [[ "${FORCE_LOCAL_DOCKER_BUILD:-false}" == "true" ]]; then
  echo "Building Docker container locally..."
  docker build "${SCRIPT_DIR}" -t "${DOCKER_IMAGE}" -f "${DOCKERFILE}"
elif ! docker image inspect "${DOCKER_IMAGE}" >/dev/null 2>&1; then
  if [[ "${DOCKER_IMAGE}" != "litert-iot-linux:latest" ]] && docker pull "${DOCKER_IMAGE}"; then
    echo "Successfully pulled pre-built container: ${DOCKER_IMAGE}"
  else
    echo "Building LiteRT Linux IoT build container (${DOCKER_IMAGE}) from ${DOCKERFILE}..."
    docker build "${SCRIPT_DIR}" -t "${DOCKER_IMAGE}" -f "${DOCKERFILE}"
  fi
fi

echo "Running LiteRT Linux IoT build inside Docker container..."
local_script_copy="/tmp/litert_run_build_${$}.sh"
cp -f "${SCRIPT_DIR}/build_iot_linux_with_docker.sh" "${local_script_copy}"
chmod +x "${local_script_copy}"

docker run --rm \
  -e RUN_DIRECTLY=true \
  -e LITERT_DIR=/litert_src \
  -e OUTPUT_DIR=/output \
  -e PLATFORM="${PLATFORM:-aarch64-oe-linux-gcc11.2}" \
  -e PRESET="${PRESET:-linux-aarch64-oe-gcc11.2}" \
  -e BDIR="${BDIR:-cmake_build_linux_aarch64_oe_gcc11_2}" \
  -e JOBS="${JOBS:-$(nproc)}" \
  -e HOST_UID="$(id -u)" \
  -e HOST_GID="$(id -g)" \
  -v "${LITERT_DIR}:/litert_src" \
  -v "${OUTPUT_DIR}:/output" \
  -v "${local_script_copy}:/tmp/build_iot_linux_with_docker.sh:ro" \
  -w /litert_src \
  "${DOCKER_IMAGE}" \
  bash /tmp/build_iot_linux_with_docker.sh

rm -f "${local_script_copy}" 2>/dev/null || true

echo "Docker build completed. Release packages available at: ${OUTPUT_DIR}"
