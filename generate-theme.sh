#!/bin/bash
# Generate a pi-vault session theme based on session ID.
# Picks a unique hue from the session ID to tint accent colors.
# Usage: generate-theme.sh <session_id> <output_path>

set -e

SESSION_ID="${1:?Usage: generate-theme.sh <session_id> <output_path>}"
OUTPUT_PATH="${2:?Usage: generate-theme.sh <session_id> <output_path>}"

# Convert session ID (hex) to a hue (0-359)
HUE=$(( 16#${SESSION_ID} % 360 ))

# Generate HSL-based colors using the hue
# We use python for the HSL→hex conversion
python3 -c "
import colorsys, json

hue = ${HUE} / 360.0

def hsl_to_hex(h, s, l):
    r, g, b = colorsys.hls_to_rgb(h, l, s)
    return '#{:02x}{:02x}{:02x}'.format(int(r*255), int(g*255), int(b*255))

# Session accent colors derived from hue
accent = hsl_to_hex(hue, 0.55, 0.65)
border = hsl_to_hex(hue, 0.60, 0.55)
border_accent = hsl_to_hex(hue, 0.80, 0.70)
custom_label = hsl_to_hex((hue + 0.1) % 1.0, 0.50, 0.60)

theme = {
    '\$schema': 'https://raw.githubusercontent.com/earendil-works/pi-mono/main/packages/coding-agent/src/modes/interactive/theme/theme-schema.json',
    'name': 'pi-vault-${SESSION_ID}',
    'vars': {
        'accent': accent,
        'border': border,
        'borderAccent': border_accent,
        'green': '#b5bd68',
        'red': '#cc6666',
        'yellow': '#ffff00',
        'gray': '#808080',
        'dimGray': '#666666',
        'darkGray': '#505050',
        'selectedBg': '#3a3a4a',
        'userMsgBg': '#343541',
        'toolPendingBg': '#282832',
        'toolSuccessBg': '#283228',
        'toolErrorBg': '#3c2828',
        'customMsgBg': '#2d2838'
    },
    'colors': {
        'accent': 'accent',
        'border': 'border',
        'borderAccent': 'borderAccent',
        'borderMuted': 'darkGray',
        'success': 'green',
        'error': 'red',
        'warning': 'yellow',
        'muted': 'gray',
        'dim': 'dimGray',
        'text': '',
        'thinkingText': 'gray',
        'selectedBg': 'selectedBg',
        'userMessageBg': 'userMsgBg',
        'userMessageText': '',
        'customMessageBg': 'customMsgBg',
        'customMessageText': '',
        'customMessageLabel': custom_label,
        'toolPendingBg': 'toolPendingBg',
        'toolSuccessBg': 'toolSuccessBg',
        'toolErrorBg': 'toolErrorBg',
        'toolTitle': '',
        'toolOutput': 'gray',
        'mdHeading': '#f0c674',
        'mdLink': accent,
        'mdLink' + 'Url': 'dimGray',
        'mdCode': 'accent',
        'mdCodeBlock': 'green',
        'mdCodeBlockBorder': 'gray',
        'mdQuote': 'gray',
        'mdQuoteBorder': 'gray',
        'mdHr': 'gray',
        'mdListBullet': 'accent',
        'toolDiffAdded': 'green',
        'toolDiffRemoved': 'red',
        'toolDiffContext': 'gray',
        'syntaxComment': '#6A9955',
        'syntaxKeyword': '#569CD6',
        'syntaxFunction': '#DCDCAA',
        'syntaxVariable': '#9CDCFE',
        'syntaxString': '#CE9178',
        'syntaxNumber': '#B5CEA8',
        'syntaxType': '#4EC9B0',
        'syntaxOperator': '#D4D4D4',
        'syntaxPunctuation': '#D4D4D4',
        'thinkingOff': 'darkGray',
        'thinkingMinimal': '#6e6e6e',
        'thinkingLow': border,
        'thinkingMedium': accent,
        'thinkingHigh': border_accent,
        'thinkingXhigh': hsl_to_hex((hue + 0.05) % 1.0, 0.85, 0.75),
        'bashMode': 'green'
    },
    'export': {
        'pageBg': '#18181e',
        'cardBg': '#1e1e24',
        'infoBg': '#3c3728'
    }
}

print(json.dumps(theme, indent=2))
" > "${OUTPUT_PATH}"
