# Switch the ImageBuilder default repositories to a mirror to avoid download failures
#OFFICIAL="https://downloads.immortalwrt.org"
#MIRROR="https://mirrors.cernet.edu.cn/immortalwrt"
#echo ">>> official failed, switching to mirror"
#BASE_URL="$MIRROR"
#echo "Using BASE_URL = $BASE_URL"
echo "========================================"
echo "Updating repositories.conf"
echo "========================================"
# Restore the default repositories
#sed -i "s#${OFFICIAL}#${BASE_URL}#g" repositories.conf
cat repositories.conf
