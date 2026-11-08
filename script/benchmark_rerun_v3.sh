#!/usr/bin/env bash
# Dynamic_C3DGS N3DV rerun (protocol v3, 2026-11-07).
#   benchmark_rerun_v3.sh RUN_ROOT full         [SCENES="a b"] [GOFS="0 1 ..."]
#   benchmark_rerun_v3.sh RUN_ROOT colmap_only  SCENE GOF     (Init_Time only, no training)
# - Frozen, hashed code copy under RUN_ROOT/code, mounted read-only.
# - Raw datasets mounted :ro; pre_n3d output (colmap_N) goes to RUN_ROOT/work/<scene> and is
#   deleted after each GoF is validated. Old results are never touched.
# - Init_Time = wall clock of pre_n3d.py (frame copy + per-frame COLMAP triangulation + undistorter).
# - No Google Sheets sync.
set -Eeuo pipefail
RUN="$1"; MODE="$2"
REPO=/home/tsaichenghan/Dynamic_C3DGS
RAW=/media/tsaichenghan/2TBSSD/datasets
IMAGE=asdggg/dynamic_c3dgs:latest
case "$RUN" in /media/tsaichenghan/2TBSSD/Dynamic_C3DGS/benchmark_*) ;; *) echo "Use a dedicated benchmark_* dir" >&2; exit 1;; esac
mkdir -p "$RUN/output" "$RUN/work"
CODE="$RUN/code"
if [ ! -d "$CODE" ]; then
  mkdir -p "$CODE"
  rsync -a --exclude __pycache__ --exclude .git "$REPO"/{configs,script,thirdparty,helper_model.py,helper_train.py,train.py,test.py} "$CODE/"
  (cd "$CODE" && find . -type f -print0 | sort -z | xargs -0 sha256sum) > "$RUN/code_sha256.txt"
  git -C "$REPO" rev-parse HEAD > "$RUN/code_git_head.txt"
  git -C "$REPO" diff > "$RUN/code_git_diff.patch"
else
  (cd "$CODE" && sha256sum -c --quiet "$RUN/code_sha256.txt") || { echo "Frozen code modified" >&2; exit 1; }
fi

D=(docker run --rm --gpus all --user "$(id -u):$(id -g)" --shm-size 8g --ipc host
   --ulimit nofile=65536:65536 -w /workspace
   -e DISPLAY="${DISPLAY:-:0}" -v /tmp/.X11-unix:/tmp/.X11-unix -e QT_QPA_PLATFORM=offscreen -e TQDM_MININTERVAL=10 -e PYTHONUNBUFFERED=1 -e PYTHONDONTWRITEBYTECODE=1
   -v "$CODE:/workspace:ro"
   -v "$REPO/cache:/root/.cache" -v "$REPO/cache:/home/ubuntu/.cache"
   -v "$RAW:$RAW:ro" -v "$RUN:$RUN" "$IMAGE")
TIMER='import subprocess,sys,time
t=time.perf_counter(); r=subprocess.run(sys.argv[2:])
if r.returncode==0: open(sys.argv[1],"w").write(f"{time.perf_counter()-t:.4f}\n")
sys.exit(r.returncode)'

status(){ printf '{"state":"%s","scene":"%s","gof":"%s","stage":"%s","time":"%s"}\n' "$1" "${2:-}" "${3:-}" "${4:-}" "$(date -Is)" > "$RUN/status.json"; }
trap 'status failed "${S:-}" "${G:-}" "${STAGE:-}"' ERR

setup_work(){  # $1 scene, $2 work dir
  mkdir -p "$2"
  for c in "$RAW/$1"/cam[0-9][0-9]; do ln -sfn "$c" "$2/$(basename "$c")"; done
  for m in "$RAW/$1"/cam*.mp4; do ln -sfn "$m" "$2/$(basename "$m")"; done
  cp -n "$RAW/$1/poses_bounds.npy" "$2/"
}

prep_gof(){  # $1 scene, $2 work, $3 start, $4 end, $5 init_time file, $6 log
  local k ncam; ncam=$(ls -d "$RAW/$1"/cam[0-9][0-9] | wc -l)
  for ((k=$3; k<$4; k++)); do rm -rf "$2/colmap_$k"; done   # never trust partial COLMAP output
  "${D[@]}" python -c "$TIMER" "$5.tmp" python script/pre_n3d.py --videopath "$2" --startframe "$3" --endframe "$4" > "$6" 2>&1
  for ((k=$3; k<$4; k++)); do
    [ -f "$2/colmap_$k/sparse/0/points3D.bin" ] && [ "$(ls "$2/colmap_$k/images" | wc -l)" -eq "$ncam" ] \
      || { echo "COLMAP output incomplete for frame $k" >&2; return 1; }
  done
  mv "$5.tmp" "$5"
}

if [ "$MODE" = colmap_only ]; then
  S="$3"; G="$4"; ST=$((G*50)); EN=$((ST+50)); STAGE=colmap
  M="$RUN/output/${S}_gof${G}_colmap_only"; W="$RUN/work/${S}_colmap_only"
  mkdir -p "$M"; status running "$S" "$G" colmap; setup_work "$S" "$W"
  prep_gof "$S" "$W" "$ST" "$EN" "$M/init_time.txt" "$M/pre_n3d.log"
  rm -rf "$W"; status complete "$S" "$G" colmap_only
  echo "INIT_TIME $S gof$G $(cat "$M/init_time.txt")"; exit 0
fi

[ "$MODE" = full ] || { echo "unknown mode $MODE" >&2; exit 1; }
SCENES="${SCENES:-coffee_martini cook_spinach cut_roasted_beef flame_salmon_1 flame_steak}"
GOFS="${GOFS:-0 1 2 3 4 5}"
for S in $SCENES; do
  W="$RUN/work/$S"; setup_work "$S" "$W"
  CFG="configs/n3d_ours/$S.json"
  for G in $GOFS; do
    ST=$((G*50)); EN=$((ST+50)); M="$RUN/output/${S}_gof$G"
    [ -f "$M/done.txt" ] && { echo "SKIP $S gof$G"; continue; }
    AVAIL=$(df -BG --output=avail "$RUN" | tail -1 | tr -dc 0-9); [ "$AVAIL" -ge 30 ] || { echo "Disk < 30G" >&2; exit 1; }
    mkdir -p "$M"
    if [ ! -f "$M/init_time.txt" ]; then
      STAGE=colmap; status running "$S" "$G" colmap
      prep_gof "$S" "$W" "$ST" "$EN" "$M/init_time.txt" "$M/pre_n3d.log"
    fi
    for attempt in 1 2; do
      STAGE=train; status running "$S" "$G" "train_attempt$attempt"
      rm -rf "$M/point_cloud" "$M/test" "$M"/*_runtime*.json "$M/total_time.txt" "$M/vram_peak.txt"
      if "${D[@]}" python train.py -s "$W/colmap_$ST" -m "$M" --configpath "$CFG" \
           --eval --comp --store_npz --data_device cpu > "$M/train.log" 2>&1 \
         && [ -f "$M/point_cloud/iteration_25000/point_cloud_pp.npz" ] && [ -f "$M/total_time.txt" ]; then
        break
      fi
      echo "attempt $attempt failed $(date -Is)" >> "$M/retries.txt"; cp "$M/train.log" "$M/train_failed_$attempt.log"
      [ "$attempt" = 2 ] && { echo "Training failed twice: $S gof$G" >&2; false; }
    done
    STAGE=test; status running "$S" "$G" test
    "${D[@]}" python test.py -s "$W/colmap_$ST" -m "$M" --configpath "$CFG" \
      --skip_train --valloader colmapvalid --data_device cpu > "$M/test.log" 2>&1
    python3 -I -c "import json,math,sys;d=json.load(open(sys.argv[1]));v=list(list(d.values())[0].values())[0];assert math.isfinite(v['PSNR']) and 'LPIPS_ALEX_NORM' in v,v;print('RESULT',sys.argv[2],{k:round(x,4) for k,x in v.items()})" \
      "$M/25000_runtimeresults.json" "${S}_gof$G"
    for ((k=ST; k<EN; k++)); do rm -rf "$W/colmap_$k"; done
    date -Is > "$M/done.txt"
  done
done
status complete "" "" "$SCENES"
echo "ALL DONE $(date -Is)"
