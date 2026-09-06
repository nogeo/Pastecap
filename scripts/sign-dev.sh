#!/bin/sh
# 为本地开发构建签名，使屏幕录制等 TCC 权限跨重建保留。
#
# 背景：SwiftPM/Xcode 直接跑的裸二进制是 ad-hoc 签名且标识符每次编译都变，
# 系统 TCC 每次都当成新程序，屏幕录制权限要反复授权。签上固定的自签证书后
# （证书公开密钥不变），授权一次即可长期有效。
#
# 用法:
#   scripts/sign-dev.sh                    # 签 .build/debug/Pastecap
#   scripts/sign-dev.sh .build/release/Pastecap
#   scripts/sign-dev.sh dist/Pastecap.app  # 签打包产物（含 entitlements）
#
# 证书名可用环境变量覆盖: PASTECA_SIGN_IDENTITY="My Cert" scripts/sign-dev.sh
set -eu

IDENTITY="${PASTECA_SIGN_IDENTITY:-Pastecap Local}"
BUNDLE_ID="com.wwm.Pastecap"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

have_identity() {
    security find-identity -v -p codesigning 2>/dev/null | grep -qF "\"$IDENTITY\""
}

create_identity() {
    echo "创建自签代码签名证书: $IDENTITY"
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT

    cat > "$TMP/req.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $IDENTITY
[v3]
keyUsage = critical, digitalSignature
extendedKeyUsage = codeSigning
basicConstraints = critical, CA:true
subjectKeyIdentifier = hash
EOF

    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/req.cnf"
    openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
        -out "$TMP/identity.p12" -password pass:pastecap-local

    # -T 授权 codesign 免密使用私钥
    security import "$TMP/identity.p12" -P pastecap-local -T /usr/bin/codesign
    # 用户域信任该证书用于代码签名
    security add-trusted-cert -p codeSign "$TMP/cert.pem"

}

if ! have_identity; then
    create_identity
fi

sign() {
    local target="$1"
    if [ "${target##*.}" = "app" ]; then
        codesign --force --deep --options runtime --entitlements "$ROOT/Packaging/Pastecap.entitlements" \
            --identifier "$BUNDLE_ID" --sign "$IDENTITY" "$target"
    else
        codesign --force --identifier "$BUNDLE_ID" --sign "$IDENTITY" "$target"
    fi
    echo "已签名: $target"
}

if [ $# -ge 1 ]; then
    TARGETS="$1"
else
    # 默认同时签 SwiftPM 产物与 Xcode DerivedData 产物（Debug/Release）
    TARGETS="$ROOT/.build/debug/Pastecap"
    for product in \
        "$HOME"/Library/Developer/Xcode/DerivedData/Pastecap-*/Build/Products/Debug/Pastecap \
        "$HOME"/Library/Developer/Xcode/DerivedData/Pastecap-*/Build/Products/Release/Pastecap; do
        if [ -f "$product" ]; then
            TARGETS="$TARGETS
$product"
        fi
    done
fi

printf '%s\n' "$TARGETS" | while IFS= read -r target; do
    if [ -n "$target" ] && [ -e "$target" ]; then
        sign "$target"
    fi
done

echo "首次运行请在 系统设置 › 隐私与安全性 › 屏幕录制 中授权一次，之后重建不再弹窗。"
