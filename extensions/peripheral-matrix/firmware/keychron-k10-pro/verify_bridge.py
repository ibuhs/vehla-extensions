"""Verify a live VHLA handshake; optional runtime layer test restores the initial layer."""
import argparse
import hid


def request(device, opcode, layer=0):
    packet = bytes([0x56, 0x48, 0x4c, 0x41, 1, opcode, layer]).ljust(32, b'\0')
    if device.write(b'\0' + packet) != 33:
        raise RuntimeError('HID request failed')
    for _ in range(5):
        reply = bytes(device.read(32, 1000))
        if len(reply) == 32 and reply[:5] == packet[:5] and reply[5] == opcode | 0x80:
            if reply[8] or reply[7] != 4 or reply[6] >= reply[7]:
                raise RuntimeError('Unexpected bridge state')
            return reply[6]
    raise RuntimeError('Keyboard did not confirm VHLA request')


def verify(exercise):
    devices = [d for d in hid.enumerate(0x3434, 0x02a3) if d['usage_page'] == 0xff60 and d['usage'] == 0x61]
    if len(devices) != 1:
        raise RuntimeError('Expected exactly one K10 Pro ANSI white Raw HID interface')
    if hasattr(hid, 'device'):
        device = hid.device(); device.open_path(devices[0]['path'])
    else:
        device = hid.Device(path=devices[0]['path'])
    try:
        initial = request(device, 1)
        print(f'VHLA version 1 confirmed: four layers, active layer {initial}.')
        if exercise:
            try:
                for layer in range(4):
                    if request(device, 2, layer) != layer or request(device, 1) != layer:
                        raise RuntimeError('Layer selection did not match readback')
            finally:
                if request(device, 2, initial) != initial:
                    raise RuntimeError('Initial layer could not be restored')
            print(f'All four runtime layer switches confirmed; initial layer {initial} restored.')
    finally:
        device.close()


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--exercise-layer-switching', action='store_true')
    verify(p.parse_args().exercise_layer_switching)
