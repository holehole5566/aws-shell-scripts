#!/bin/bash

echo "---"
echo "S3 Bucket Force Delete Tool (with Versioning Support)"
echo "---"

# Get search keyword
read -p "Enter S3 Bucket name keyword to search: " search_keyword

if [ -z "$search_keyword" ]; then
    echo "Error: No search keyword provided. Operation cancelled."
    exit 1
fi

echo "---"
echo "Searching for S3 Buckets containing '$search_keyword'..."
echo "---"

# Find matching buckets
matching_buckets=$(aws s3 ls | awk '{print $NF}' | grep "$search_keyword")
IFS=$'\n' read -r -d '' -a buckets_to_delete <<< "$matching_buckets"

if [ ${#buckets_to_delete[@]} -eq 0 ]; then
    echo "No S3 Buckets found matching '$search_keyword'. Operation cancelled."
    exit 0
fi

echo "---"
echo "The following S3 Buckets will be deleted: (${#buckets_to_delete[@]} total)"
echo "---"
for bucket in "${buckets_to_delete[@]}"; do
    echo "- $bucket"
done
echo "---"

# Confirmation
read -p "WARNING: Deleting S3 Buckets and their contents is irreversible! Are you sure? (type 'yes' to confirm): " confirm_delete

if [[ "$confirm_delete" != "yes" ]]; then
    echo "Operation cancelled."
    exit 0
fi

echo "---"
echo "Starting force deletion process..."
echo "---"

# Function to force delete bucket with versioning support
force_delete_bucket() {
    local bucket_name=$1
    echo "Processing bucket: $bucket_name"
    
    # Check if versioning is enabled
    versioning_status=$(aws s3api get-bucket-versioning --bucket "$bucket_name" --query 'Status' --output text 2>/dev/null)
    
    if [[ "$versioning_status" == "Enabled" ]]; then
        echo "  Versioning is enabled. Deleting all object versions..."
        
        # Delete all object versions and delete markers
        aws s3api list-object-versions --bucket "$bucket_name" --output json | \
        jq -r '.Versions[]?, .DeleteMarkers[]? | "\(.Key)\t\(.VersionId)"' | \
        while IFS=$'\t' read -r key version_id; do
            if [[ -n "$key" && -n "$version_id" ]]; then
                echo "    Deleting: $key (version: $version_id)"
                aws s3api delete-object --bucket "$bucket_name" --key "$key" --version-id "$version_id" >/dev/null 2>&1
            fi
        done
    else
        echo "  Versioning not enabled. Deleting all objects..."
        # Delete all objects normally
        aws s3 rm "s3://$bucket_name" --recursive >/dev/null 2>&1
    fi
    
    # Delete incomplete multipart uploads
    echo "  Cleaning up incomplete multipart uploads..."
    aws s3api list-multipart-uploads --bucket "$bucket_name" --query 'Uploads[].{Key:Key,UploadId:UploadId}' --output text | \
    while read -r key upload_id; do
        if [[ -n "$key" && -n "$upload_id" ]]; then
            echo "    Aborting multipart upload: $key"
            aws s3api abort-multipart-upload --bucket "$bucket_name" --key "$key" --upload-id "$upload_id" >/dev/null 2>&1
        fi
    done
    
    # Finally delete the bucket
    echo "  Deleting bucket: $bucket_name"
    aws s3api delete-bucket --bucket "$bucket_name"
    
    if [ $? -eq 0 ]; then
        echo "  ✓ Successfully deleted bucket: $bucket_name"
    else
        echo "  ✗ Failed to delete bucket: $bucket_name"
    fi
    echo ""
}

# Delete each bucket
for bucket_name in "${buckets_to_delete[@]}"; do
    force_delete_bucket "$bucket_name"
done

echo "---"
echo "Force deletion process completed."
echo "---"