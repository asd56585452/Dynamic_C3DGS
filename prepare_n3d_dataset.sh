#!/bin/bash
# ==============================================================================
# Helper script to prepare N3D datasets from /media/tsaichenghan/HardDisk
# Usage:
#   ./prepare_n3d_dataset.sh sear_steak
#   ./prepare_n3d_dataset.sh coffee_martini
# ==============================================================================

set -e

SOURCE_DIR="/media/tsaichenghan/HardDisk"
TARGET_DIR="./datasets"

SCENE=$1

if [ -z "$SCENE" ]; then
    echo "Usage: $0 [SCENE_NAME]"
    echo "Available N3D scenes on HardDisk:"
    echo "  - coffee_martini"
    echo "  - cook_spinach"
    echo "  - cut_roasted_beef"
    echo "  - flame_salmon_1"
    echo "  - flame_steak"
    echo "  - sear_steak"
    exit 1
fi

mkdir -p "$TARGET_DIR"

if [ "$SCENE" == "flame_salmon_1" ]; then
    ZIP_PATH="$SOURCE_DIR/flame_salmon_1_split.zip"
    if [ ! -f "$ZIP_PATH" ]; then
        echo "Error: $ZIP_PATH not found on $SOURCE_DIR!"
        exit 1
    fi
    echo "Unzipping multi-part archive flame_salmon_1 into $TARGET_DIR..."
    # 7z can seamlessly unpack split zip files
    if command -v 7z &> /dev/null; then
        7z x "$ZIP_PATH" -o"$TARGET_DIR" -y
    else
        unzip -q "$ZIP_PATH" -d "$TARGET_DIR"
    fi
else
    ZIP_PATH="$SOURCE_DIR/${SCENE}.zip"
    if [ ! -f "$ZIP_PATH" ]; then
        echo "Error: $ZIP_PATH not found on $SOURCE_DIR!"
        exit 1
    fi
    echo "Unzipping $ZIP_PATH into $TARGET_DIR..."
    unzip -q "$ZIP_PATH" -d "$TARGET_DIR"
fi

echo "Successfully extracted $SCENE into $TARGET_DIR/$SCENE"
echo ""
echo "Next step (extract frames and run COLMAP preprocessing inside Docker):"
echo "  ./run_docker.sh python script/pre_n3d.py --videopath datasets/$SCENE"
echo ""
echo "Then start original training:"
echo "  ./run_docker.sh python train.py --quiet --eval \\"
echo "      --config configs/n3d_ours/${SCENE}.json \\"
echo "      --model_path output/${SCENE}_original \\"
echo "      --source_path datasets/${SCENE}/colmap_0"
