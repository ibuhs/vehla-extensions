// QMK keymap integration: add this source to SRC, enable RAW_ENABLE = yes.
// If raw_hid_receive already exists, dispatch matching VHLA packets to
// vehla_raw_hid_receive there instead of defining a second callback.
#include QMK_KEYBOARD_H
#include "raw_hid.h"
#include "keymap_introspection.h"
#include "string.h"

bool vehla_raw_hid_receive(uint8_t *data, uint8_t length) {
    const uint8_t magic[] = {0x56, 0x48, 0x4c, 0x41, 1};
    if (length != 32 || memcmp(data, magic, sizeof(magic)) != 0) return false;
    const uint8_t opcode = data[5];
    const uint8_t requested = data[6];
    const uint8_t count = (uint8_t)keymap_layer_count();
    if (opcode != 1 && opcode != 2) return true;
    uint8_t status = 0;
    if (opcode == 2) {
        if (requested >= count) status = 1;
        else {
#ifdef VEHLA_KEYCHRON_OS_LAYERS
            // Keychron's stock layers are Mac/Mac Fn/Windows/Windows Fn.
            // Keep transparent Fn keys falling through to the matching OS base.
            default_layer_set((layer_state_t)1 << (requested & ~1));
            layer_clear();
            if (requested & 1) layer_on(requested);
#else
            layer_move(requested);
#endif
            // Runtime state only; no EEPROM write.
        }
    }
    memset(data, 0, length);
    memcpy(data, magic, sizeof(magic));
    data[5] = opcode | 0x80;
    data[6] = get_highest_layer(layer_state | default_layer_state);
    data[7] = count;
    data[8] = status;
    raw_hid_send(data, length);
    return true;
}

#ifndef VEHLA_EXISTING_RAW_HANDLER
void raw_hid_receive(uint8_t *data, uint8_t length) {
    vehla_raw_hid_receive(data, length);
}
#endif
