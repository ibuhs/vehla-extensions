"""Restore only the matching, locally backed-up K10 Pro mapping after flashing."""
import argparse
import json
from pathlib import Path
import hid
from backup_via import exchange, read_buffer


def write_buffer(device, command, before, saved):
    assert command in (0x13, 0x0f)
    for offset in range(0, len(saved), 28):
        chunk = saved[offset:offset+28]
        if before[offset:offset+28] == chunk:
            continue
        packet = bytes([command, offset >> 8, offset & 255, len(chunk)]) + chunk
        packet = packet.ljust(32, b'\0')
        device.write(b'\0' + packet)
        for attempt in range(5):
            reply = bytes(device.read(32, 1000))
            if reply == packet:
                break
        else:
            raise RuntimeError('No confirmation for saved-map restore; stop and re-read the keyboard')


def restore(backup):
    saved = json.loads(backup.read_text())
    assert saved['target'] == 'keychron/k10_pro/ansi/white'
    assert saved['layers'] == 4 and saved['rows'] == 6 and saved['columns'] == 21
    devices = [d for d in hid.enumerate(0x3434, 0x02a3) if d['usage_page'] == 0xff60 and d['usage'] == 0x61]
    if len(devices) != 1:
        raise RuntimeError('Expected exactly one matching keyboard')
    if hasattr(hid, 'device'):
        device = hid.device(); device.open_path(devices[0]['path'])
    else:
        device = hid.Device(path=devices[0]['path'])
    try:
        if int.from_bytes(exchange(device, 1)[1:3], 'big') != saved['via_protocol']:
            raise RuntimeError('VIA protocol mismatch')
        if exchange(device, 0x11)[1] != 4 or exchange(device, 0x0c)[1] != saved['macro_count']:
            raise RuntimeError('Layer/macro count mismatch')
        matrix = bytes.fromhex(saved['keymap_hex']); macros = bytes.fromhex(saved['macro_hex'])
        if int.from_bytes(exchange(device, 0x0d)[1:3], 'big') != len(macros):
            raise RuntimeError('Macro buffer size mismatch; no data written')
        old_matrix = read_buffer(device, 0x12, len(matrix)); old_macros = read_buffer(device, 0x0e, len(macros))
        write_buffer(device, 0x13, old_matrix, matrix)
        write_buffer(device, 0x0f, old_macros, macros)
        if read_buffer(device, 0x12, len(matrix)) != matrix or read_buffer(device, 0x0e, len(macros)) != macros:
            raise RuntimeError('Readback did not match backup')
        print('Verified all four layers and all macro bytes match the pre-flash backup exactly.')
    finally:
        device.close()

if __name__ == '__main__':
    p = argparse.ArgumentParser(); p.add_argument('backup', type=Path)
    restore(p.parse_args().backup)
