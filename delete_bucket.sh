#!/bin/bash

echo "---"
echo "S3 Bucket 刪除工具 (互動式)"
echo "---"

# 提示使用者輸入要搜尋的關鍵字
read -p "請輸入要搜尋的 S3 Bucket 名稱關鍵字 (例如: loghub): " search_keyword

if [ -z "$search_keyword" ]; then
    echo "錯誤：未輸入搜尋關鍵字。操作已取消。"
    exit 1
fi

echo "---"
echo "正在搜尋以 '$search_keyword' 開頭或包含 '$search_keyword' 的 S3 Bucket..."
echo "---"

# 找到所有匹配的 Bucket 名稱
# 使用 awk 提取 Bucket 名稱，然後用 grep 過濾
# 注意：這裡的 grep 會匹配 Bucket 名稱中包含關鍵字的部分，不限於開頭
matching_buckets=$(aws s3 ls | awk '{print $NF}' | grep "$search_keyword")

# 將匹配到的 Bucket 放入陣列中，以便後續處理
IFS=$'\n' read -r -d '' -a buckets_to_delete <<< "$matching_buckets"

if [ ${#buckets_to_delete[@]} -eq 0 ]; then
    echo "沒有找到任何符合 '$search_keyword' 的 S3 Bucket。操作已取消。"
    echo "---"
    exit 0
fi

echo "---"
echo "以下 S3 Bucket 將被刪除：(共 ${#buckets_to_delete[@]} 個)"
echo "---"
for bucket in "${buckets_to_delete[@]}"; do
    echo "- $bucket"
done
echo "---"

# 再次確認是否執行刪除
read -p "警告：刪除 S3 Bucket 及其內容是不可逆的！你確定要永久刪除上述 Bucket 嗎？ (輸入 'yes' 確認): " confirm_delete

if [[ "$confirm_delete" != "yes" ]]; then
    echo "操作已取消。"
    echo "---"
    exit 0
fi

echo "---"
echo "正在執行刪除操作..."
echo "---"

# 逐一刪除 Bucket
for bucket_name in "${buckets_to_delete[@]}"; do
    echo "正在刪除 Bucket: $bucket_name..."
    aws s3 rb "s3://$bucket_name" --force
    if [ $? -eq 0 ]; then
        echo "成功刪除 Bucket: $bucket_name"
    else
        echo "刪除 Bucket 失敗: $bucket_name (請檢查權限或 Bucket 狀態)"
    fi
done

echo "---"
echo "所有符合條件的 Bucket 刪除作業已完成。"
echo "---"