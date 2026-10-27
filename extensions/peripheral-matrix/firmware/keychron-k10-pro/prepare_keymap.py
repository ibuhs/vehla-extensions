"""Prepare the verified ANSI white target from a private VIA backup; never flash."""
import argparse
import json
import shutil
import subprocess
from pathlib import Path

REVISION = '618127a725a1773e85f13455602cf6f72ab4de17'
TARGET = 'keychron/k10_pro/ansi/white'


def prepare(checkout, backup):
    revision = subprocess.check_output(['git', '-C', str(checkout), 'rev-parse', 'HEAD'], text=True).strip()
    if revision != REVISION:
        raise RuntimeError('Use the documented, verified Keychron source revision')
    saved = json.loads(backup.read_text())
    if (saved['target'], saved['layers'], saved['rows'], saved['columns']) != (TARGET, 4, 6, 21):
        raise RuntimeError('Backup does not match the verified keyboard')
    matrix = bytes.fromhex(saved['keymap_hex'])
    if len(matrix) != 1008 or len(bytes.fromhex(saved['macro_hex'])) != 3050:
        raise RuntimeError('Unexpected matrix or macro buffer size')
    destination = checkout / 'keyboards' / TARGET / 'keymaps/vehla'
    destination.mkdir(parents=True, exist_ok=True)
    rows = []
    for layer in range(4):
        rows.append(f'    [{layer}] = {{')
        for row in range(6):
            start = (layer * 6 + row) * 21 * 2
            values = [int.from_bytes(matrix[i:i+2], 'big') for i in range(start, start+42, 2)]
            rows.append('        {' + ', '.join(f'0x{v:04x}' for v in values) + '},')
        rows.append('    },')
    (destination / 'keymap.c').write_text('#include QMK_KEYBOARD_H\nconst uint16_t PROGMEM keymaps[][MATRIX_ROWS][MATRIX_COLS] = {\n' + '\n'.join(rows) + '\n};\n')
    (destination / 'rules.mk').write_text('VIA_ENABLE = yes\nRAW_ENABLE = yes\nSRC += $(KEYMAP_PATH)/vehla_layer_bridge.c\nOPT_DEFS += -DVEHLA_EXISTING_RAW_HANDLER\nOPT_DEFS += -DVEHLA_KEYCHRON_OS_LAYERS\n')
    (destination / 'config.h').write_text('#pragma once\n#undef FEE_DENSITY_BYTES\n#define FEE_DENSITY_BYTES 4096\n#undef DYNAMIC_KEYMAP_EEPROM_MAX_ADDR\n#define DYNAMIC_KEYMAP_EEPROM_MAX_ADDR 4095\n')
    shutil.copyfile(Path(__file__).resolve().parent.parent / 'vehla_layer_bridge.c', destination / 'vehla_layer_bridge.c')
    keyboard = checkout / 'keyboards/keychron/k10_pro/k10_pro.c'
    code = keyboard.read_text()
    hook = 'bool via_command_kb(uint8_t *data, uint8_t length) {'
    if 'if (vehla_raw_hid_receive(data, length)) return true;' not in code:
        if code.count(hook) != 1:
            raise RuntimeError('Existing VIA handler did not match; no handler replaced')
        code = code.replace(hook, 'bool vehla_raw_hid_receive(uint8_t *data, uint8_t length);\n' + hook + '\n    if (vehla_raw_hid_receive(data, length)) return true;')
        keyboard.write_text(code)
    print('Prepared saved four-layer mapping and bridge; VIA and Keychron handlers retained.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('checkout', type=Path)
    parser.add_argument('backup', type=Path)
    args = parser.parse_args()
    prepare(args.checkout, args.backup)
