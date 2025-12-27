# shellcheck shell=bash
# Download utilities

# Download file with retry. $1=output_path, $2=url
download_file() {
  local output_file="$1"
  local url="$2"
  local max_retries="${DOWNLOAD_RETRY_COUNT:-3}"
  local retry_delay="${DOWNLOAD_RETRY_DELAY:-2}"
  local retry_count=0

  while [ "$retry_count" -lt "$max_retries" ]; do
    if wget -q -O "$output_file" "$url"; then
      if [ -s "$output_file" ]; then
        # Check file integrity - verify it's not corrupted/empty
        local file_type
        file_type=$(file "$output_file" 2>/dev/null || printf '\n')

        # For files detected as "empty" or suspicious "data", verify size
        if echo "$file_type" | grep -q "empty"; then
          print_error "Downloaded file is empty: $output_file"
          retry_count=$((retry_count + 1))
          continue
        fi

        return 0
      else
        print_error "Downloaded file is empty: $output_file"
      fi
    else
      print_warning "Download failed (attempt $((retry_count + 1))/$max_retries): $url"
    fi
    retry_count=$((retry_count + 1))
    [ "$retry_count" -lt "$max_retries" ] && sleep "$retry_delay"
  done

  log "ERROR: Failed to download $url after $max_retries attempts"
  return 1
}
