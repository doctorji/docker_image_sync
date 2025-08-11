#!/bin/bash
set -eux  # -u: 遇到未定义变量报错；-e: 任何命令失败立即退出；-x: 打印执行的命令

IMAGES_FILE="images.txt"

# 检查配置文件和镜像列表文件是否存在
if [ ! -f "$IMAGES_FILE" ]; then
    echo "Error: images.txt not found! Please create it with a list of images to sync."
    exit 1
fi

# 检查必要的配置变量是否已设置
if [ -z "$ACR_REGISTRY" ] || [ -z "$ACR_NAMESPACE" ]; then
    echo "Error: ACR_REGISTRY or ACR_NAMESPACE not set in GitHub variables. Please check your config."
    exit 1
fi

echo "Starting Docker image synchronization to ACR..."
echo "Target Registry: ${ACR_REGISTRY}"
echo "Target Namespace: ${ACR_NAMESPACE}"
echo "-----------------------------------"

# 遍历 images.txt，逐行处理镜像
while IFS= read -r image; do
    # 跳过空行或以 # 开头的注释行
    if [[ -z "$image" || "$image" =~ ^# ]]; then
        continue
    fi

    echo "--- Processing image: ${image} ---"

    # 分离原始镜像的仓库名和标签
    original_repo=$(echo "$image" | cut -d ':' -f1)
    original_tag=$(echo "$image" | cut -d ':' -f2)

    # 构造目标 ACR 完整镜像路径
    target_full_image_path="${ACR_REGISTRY}/${ACR_NAMESPACE}/${original_repo}:${original_tag}"

    echo "Original image full path: ${image}"
    echo "Target ACR image full path: ${target_full_image_path}"

    # 检查阿里云仓库是否已有该tag
    if docker manifest inspect "${target_full_image_path}" > /dev/null 2>&1; then
        echo "${target_full_image_path} already exists in ACR, skipping synchronization."
        echo "-----------------------------------"
        continue # 跳过当前循环的后续步骤
    fi

    echo "Image ${target_full_image_path} not found in ACR. Proceeding with sync..."

    # 拉取原始镜像
    echo "Pulling original image: ${image}..."
    docker pull "${image}"

    # 打上阿里云 ACR 的标签
    echo "Tagging image ${image} to ${target_full_image_path}..."
    docker tag "${image}" "${target_full_image_path}"

    # 推送到阿里云 ACR
    echo "Pushing image ${target_full_image_path} to ACR..."
    docker push "${target_full_image_path}"

    # 清理本地拉取和打标签的镜像，释放 GitHub Actions Runner 的磁盘空间
    echo "Cleaning up local images..."
    docker rmi "${image}" || true
    docker rmi "${target_full_image_path}" || true

    echo "Successfully synced: ${image} to ${target_full_image_path}"
    echo "-----------------------------------"
done < "$IMAGES_FILE"

echo "All specified images processed successfully."
echo "Synchronization process finished."
