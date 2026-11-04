# Arborescence /sys et /dev USB factice pour tests/usb/test_usb.al : contrôleur racine usb1 (2 ports), clavier
# 1-1, concentrateur 1-2 (4 ports) portant une clé de stockage 1-2.3.
import os, struct, sys
root = sys.argv[1]
def w(path, text, binary=False):
    full = os.path.join(root, path.lstrip('/'))
    os.makedirs(os.path.dirname(full), exist_ok=True)
    open(full, 'wb' if binary else 'w').write(text)
def dev_desc(cls, vid, pid, mp=64):
    return bytes([18, 1, 0, 2, cls, 0, 0, mp]) + struct.pack('<HHH', vid, pid, 0x0100) + bytes([1, 2, 3, 1])
def cfg(ifaces):
    body = b''
    for (num, cls, sub, proto, eps, hid) in ifaces:
        body += bytes([9, 4, num, 0, len(eps), cls, sub, proto, 0])
        if hid:
            body += bytes([9, 0x21, 0x11, 1, 0, 1, 0x22, 63, 0])
        for (addr, attr, size, interval) in eps:
            body += bytes([7, 5, addr, attr]) + struct.pack('<H', size) + bytes([interval])
    total = 9 + len(body)
    return bytes([9, 2]) + struct.pack('<H', total) + bytes([len(ifaces), 1, 0, 0xA0, 50]) + body
def device(name, bus, devnum, vid, pid, cls, ifaces, product, maker, maxchild=0, speed='12'):
    base = '/sys/bus/usb/devices/' + name
    w(base + '/busnum', '%d\n' % bus)
    w(base + '/devnum', '%d\n' % devnum)
    w(base + '/idVendor', '%04x\n' % vid)
    w(base + '/idProduct', '%04x\n' % pid)
    w(base + '/product', product + '\n')
    w(base + '/manufacturer', maker + '\n')
    w(base + '/speed', speed + '\n')
    w(base + '/version', ' 2.00\n')
    w(base + '/bConfigurationValue', '1\n')
    w(base + '/maxchild', '%d\n' % maxchild)
    w(base + '/descriptors', dev_desc(cls, vid, pid) + cfg(ifaces), True)
    w('/dev/bus/usb/%03d/%03d' % (bus, devnum), b'', True)
    for (num, c, s, p, eps, hid) in ifaces:
        w(base + ':1.%d/bInterfaceClass' % num, '%02x\n' % c)
device('usb1', 1, 1, 0x1d6b, 0x0002, 9, [(0, 9, 0, 0, [(0x81, 3, 4, 12)], False)], 'EHCI Host Controller', 'Linux Foundation', 2, '480')
w('/sys/bus/usb/devices/usb1/usb1:1.0/usb1-port1/connect_type', 'hotplug\n')
device('1-1', 1, 2, 0x046d, 0xc31c, 0, [(0, 3, 1, 1, [(0x81, 3, 8, 10)], True)], 'USB Keyboard', 'Logitech')
device('1-2', 1, 3, 0x05e3, 0x0608, 9, [(0, 9, 0, 0, [(0x81, 3, 1, 12)], False)], 'USB2.0 Hub', 'Genesys', 4, '480')
device('1-2.3', 1, 4, 0x0781, 0x5567, 0, [(0, 8, 6, 0x50, [(0x81, 2, 512, 0), (0x02, 2, 512, 0)], False)], 'Cruzer Blade', 'SanDisk', 0, '480')
w('/sys/bus/usb/devices/1-1/serial', 'KB0001\n')
