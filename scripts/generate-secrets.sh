#!/bin/bash
# Generate XOR-obfuscated API keys from .env file
# Called as an Xcode Run Script Build Phase
# Output: Sources/GeneratedSecrets.swift (gitignored)

set -euo pipefail

ENV_FILE="${SRCROOT}/.env"
OUTPUT_FILE="${SRCROOT}/Sources/GeneratedSecrets.swift"

# Read values from .env
AZURE_API_KEY=""
AZURE_ENDPOINT=""
if [ -f "$ENV_FILE" ]; then
    AZURE_API_KEY=$(grep -E '^AZURE_OPENAI_API_KEY=' "$ENV_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'" | tr -d '[:space:]' || true)
    AZURE_ENDPOINT=$(grep -E '^AZURE_OPENAI_ENDPOINT=' "$ENV_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'" | tr -d '[:space:]' || true)
fi

# XOR obfuscation helper: outputs Swift array literal for the given string
# Usage: xor_obfuscate "plaintext" mask_var cipher_var
xor_obfuscate() {
    local INPUT="$1"
    local INPUT_LEN=${#INPUT}
    local MASK_BYTES=""
    local CIPHER_BYTES=""
    for (( i=0; i<INPUT_LEN; i++ )); do
        MASK_BYTE=$(( (RANDOM % 254) + 1 ))
        CHAR="${INPUT:$i:1}"
        CHAR_BYTE=$(printf '%d' "'$CHAR")
        CIPHER_BYTE=$(( CHAR_BYTE ^ MASK_BYTE ))
        if [ $i -gt 0 ]; then
            MASK_BYTES+=", "
            CIPHER_BYTES+=", "
        fi
        MASK_BYTES+="0x$(printf '%02x' $MASK_BYTE)"
        CIPHER_BYTES+="0x$(printf '%02x' $CIPHER_BYTE)"
    done
    eval "$2='$MASK_BYTES'"
    eval "$3='$CIPHER_BYTES'"
}

# Build the Swift file
{
    echo "// Auto-generated — DO NOT EDIT, DO NOT COMMIT"
    echo "enum GeneratedSecrets {"

    # Azure OpenAI API Key
    if [ -n "$AZURE_API_KEY" ]; then
        xor_obfuscate "$AZURE_API_KEY" KEY_MASK KEY_CIPHER
        cat << SWIFT
    private static let _akm: [UInt8] = [$KEY_MASK]
    private static let _akc: [UInt8] = [$KEY_CIPHER]

    static var azureOpenAIAPIKey: String? {
        guard _akm.count == _akc.count, !_akm.isEmpty else { return nil }
        let bytes = zip(_akc, _akm).map { \$0 ^ \$1 }
        return String(bytes: bytes, encoding: .utf8)
    }
SWIFT
    else
        echo "    static var azureOpenAIAPIKey: String? { nil }"
    fi

    # Azure OpenAI Endpoint
    if [ -n "$AZURE_ENDPOINT" ]; then
        xor_obfuscate "$AZURE_ENDPOINT" EP_MASK EP_CIPHER
        cat << SWIFT
    private static let _epm: [UInt8] = [$EP_MASK]
    private static let _epc: [UInt8] = [$EP_CIPHER]

    static var azureOpenAIEndpoint: String? {
        guard _epm.count == _epc.count, !_epm.isEmpty else { return nil }
        let bytes = zip(_epc, _epm).map { \$0 ^ \$1 }
        return String(bytes: bytes, encoding: .utf8)
    }
SWIFT
    else
        echo "    static var azureOpenAIEndpoint: String? { nil }"
    fi

    echo "}"
} > "$OUTPUT_FILE"

echo "generate-secrets: Azure API key=${#AZURE_API_KEY} chars, endpoint=${#AZURE_ENDPOINT} chars"
