#!/bin/sh
set -eu

if [ "$#" -ne 3 ]; then
    echo "usage: $0 <package.apk> <output.run> <apk-architecture>" >&2
    exit 2
fi

apk_path="$1"
output_path="$2"
expected_arch="$3"

if [ ! -f "$apk_path" ]; then
    echo "APK not found: $apk_path" >&2
    exit 1
fi

payload_name="$(basename "$apk_path")"
payload_sha256="$(sha256sum "$apk_path" | awk '{print $1}')"

cat > "$output_path" <<EOF
#!/bin/sh
set -eu

EXPECTED_ARCH='$expected_arch'
PAYLOAD_NAME='$payload_name'
PAYLOAD_SHA256='$payload_sha256'
TMP_APK="/tmp/\${PAYLOAD_NAME}.\$\$.apk"

cleanup() {
    rm -f "\$TMP_APK"
}

trap cleanup 0
trap 'exit 1' HUP INT TERM

if ! command -v apk >/dev/null 2>&1; then
    echo "This installer requires an APK-based OpenWrt system." >&2
    exit 1
fi

actual_arch="\$(apk --print-arch 2>/dev/null || true)"
if [ "\$actual_arch" != "\$EXPECTED_ARCH" ]; then
    echo "Architecture mismatch: expected \$EXPECTED_ARCH, got \${actual_arch:-unknown}." >&2
    exit 1
fi

payload_line="\$(awk '/^__APK_PAYLOAD_BELOW__/ { print NR + 1; exit }' "\$0")"
if [ -z "\$payload_line" ]; then
    echo "Embedded APK payload was not found." >&2
    exit 1
fi

tail -n "+\$payload_line" "\$0" > "\$TMP_APK"
echo "\$PAYLOAD_SHA256  \$TMP_APK" | sha256sum -c - >/dev/null

if ! apk add --allow-untrusted "\$TMP_APK"; then
    echo "Initial install failed; refreshing package indexes and retrying." >&2
    apk update
    apk add --allow-untrusted "\$TMP_APK"
fi

rm -rf /tmp/luci-indexcache /tmp/luci-modulecache
/etc/init.d/rpcd restart >/dev/null 2>&1 || true
echo "Installed \$PAYLOAD_NAME successfully."
exit 0
__APK_PAYLOAD_BELOW__
EOF

cat "$apk_path" >> "$output_path"
chmod 0755 "$output_path"