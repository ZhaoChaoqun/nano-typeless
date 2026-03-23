#!/bin/bash
# Generate XOR-obfuscated API key from .env file
# Called as an Xcode Run Script Build Phase
# Output: Sources/GeneratedSecrets.swift (gitignored)

set -euo pipefail

ENV_FILE="${SRCROOT}/.env"
OUTPUT_FILE="${SRCROOT}/Sources/GeneratedSecrets.swift"

# Read API key from .env
API_KEY=""
if [ -f "$ENV_FILE" ]; then
    API_KEY=$(grep -E '^CLOUD_REWRITE_API_KEY=' "$ENV_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'" | tr -d '[:space:]')
fi

# Generate Swift file
if [ -z "$API_KEY" ]; then
    # No key — generate stub that returns nil
    cat > "$OUTPUT_FILE" << 'SWIFT'
// Auto-generated — DO NOT EDIT, DO NOT COMMIT
// No API key found in .env
enum GeneratedSecrets {
    static var cloudRewriteAPIKey: String? { nil }
}
SWIFT
    echo "generate-secrets: no API key found, generated nil stub"
else
    # XOR obfuscate the key with a random mask
    KEY_LEN=${#API_KEY}

    # Generate random mask bytes
    MASK_BYTES=""
    CIPHER_BYTES=""
    for (( i=0; i<KEY_LEN; i++ )); do
        # Random byte 1-255
        MASK_BYTE=$(( (RANDOM % 254) + 1 ))
        CHAR="${API_KEY:$i:1}"
        CHAR_BYTE=$(printf '%d' "'$CHAR")
        CIPHER_BYTE=$(( CHAR_BYTE ^ MASK_BYTE ))

        if [ $i -gt 0 ]; then
            MASK_BYTES+=", "
            CIPHER_BYTES+=", "
        fi
        MASK_BYTES+="0x$(printf '%02x' $MASK_BYTE)"
        CIPHER_BYTES+="0x$(printf '%02x' $CIPHER_BYTE)"
    done

    cat > "$OUTPUT_FILE" << SWIFT
// Auto-generated — DO NOT EDIT, DO NOT COMMIT
// API key is XOR-obfuscated to avoid plaintext exposure in binary
enum GeneratedSecrets {
    private static let _m: [UInt8] = [$MASK_BYTES]
    private static let _c: [UInt8] = [$CIPHER_BYTES]

    static var cloudRewriteAPIKey: String? {
        guard _m.count == _c.count, !_m.isEmpty else { return nil }
        let bytes = zip(_c, _m).map { \$0 ^ \$1 }
        return String(bytes: bytes, encoding: .utf8)
    }
}
SWIFT
    echo "generate-secrets: obfuscated ${KEY_LEN}-char key"
fi
