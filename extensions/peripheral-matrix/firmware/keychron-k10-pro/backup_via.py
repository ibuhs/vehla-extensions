"""Read-only VIA backup for the verified K10 Pro ANSI white (3434:02a3)."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import hid

READ_COMMANDS = {0x01, 0x0c, 0x0d, 0x0e, 0x11, 0x12}

def exchange(device, command, payload=()):
    assert command in READ_COMMANDS
    packet = bytes([command, *payload]).ljust(32, b'\0')
    if device.write(b'\0' + packet) != 33:
        raise RuntimeError('Could not send VIA read request')
    for _ in range(5):
        response = bytes(device.read(32, 1000))
        if len(response) == 32 and response[0] == command:
            return response
    raise RuntimeError(f'No valid VIA response for read command {command:#x}')

def read_buffer(device, command, size):
    result = bytearray()
    for offset in range(0, size, 28):
        length = min(28, size - offset)
        reply = exchange(device, command, [offset >> 8, offset & 255, length])
        if reply[1:4] != bytes([offset >> 8, offset & 255, length]):
            raise RuntimeError('VIA response offset did not match request')
        result.extend(reply[4:4+length])
    return bytes(result)

def backup(destination):
    devices = [d for d in hid.enumerate(0x3434, 0x02a3)
               if d['usage_page'] == 0xff60 and d['usage'] == 0x61]
    if len(devices) != 1:
        raise RuntimeError('Connect exactly one K10 Pro ANSI white by USB in Cable mode')
    if hasattr(hid, 'device'):
        device = hid.device()
        device.open_path(devices[0]['path'])
    else:
        device = hid.Device(path=devices[0]['path'])
    try:
        protocol = int.from_bytes(exchange(device, 0x01)[1:3], 'big')
        layers = exchange(device, 0x11)[1]
        if layers != 4:
            raise RuntimeError(f'Expected four existing layers, got {layers}; stop before changing firmware')
        matrix = read_buffer(device, 0x12, layers * 6 * 21 * 2)
        count = exchange(device, 0x0c)[1]
        macro_size = int.from_bytes(exchange(device, 0x0d)[1:3], 'big')
        if macro_size > 8192:
            raise RuntimeError('Unexpected macro buffer size')
        macros = read_buffer(device, 0x0e, macro_size)
        # Read twice: only save a coherent snapshot, never an in-progress edit.
        if matrix != read_buffer(device, 0x12, len(matrix)) or macros != read_buffer(device, 0x0e, macro_size):
            raise RuntimeError('Mapping changed during backup; close VIA/Launcher and retry')
        snapshot = dict(target='keychron/k10_pro/ansi/white', vendor_id=0x3434,
                        product_id=0x02a3, via_protocol=protocol, layers=layers,
                        rows=6, columns=21, keymap_hex=matrix.hex(), macro_count=count,
                        macro_hex=macros.hex(), captured=datetime.datetime.now(datetime.timezone.utc).isoformat())
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(json.dumps(snapshot, indent=2) + '\n')
        destination.chmod(0o600)
        print(f'Backed up {layers} layers and {macro_size} macro bytes to {destination}')
        print('Keymap SHA-256:', hashlib.sha256(matrix).hexdigest())
    finally:
        device.close()

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    if args.destination.exists():
        raise SystemExit('Backup already exists; choose a new filename rather than overwriting')
    backup(args.destination)
