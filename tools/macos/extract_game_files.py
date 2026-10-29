"""Extract default.xex + shader.ar (XGD2 ISO) and default.xexp (STFS title update) from your own game files."""
import struct, sys, os

XGD_OFFSETS = (0xFD90000, 0x2080000, 0x18300000, 0)  # XGD2, XGD1, XGD3, plain XISO


def iso_files(path, wanted):
    f = open(path, 'rb')
    for base in XGD_OFFSETS:
        f.seek(base + 0x10000)
        if f.read(20) == b'MICROSOFT*XBOX*MEDIA':
            break
    else:
        sys.exit('no XDVDFS volume found')
    root_sector, root_size = struct.unpack('<II', f.read(8))
    f.seek(base + root_sector * 2048)
    table = f.read(root_size)
    out = {}

    def walk(off):
        left, right, sector, size, attr, nlen = struct.unpack_from('<HHIIBB', table, off)
        name = table[off + 14:off + 14 + nlen].decode('latin-1')
        if name.lower() in wanted:
            f.seek(base + sector * 2048)
            out[name.lower()] = f.read(size)
        if left and left != 0xFFFF:
            walk(left * 4)
        if right and right != 0xFFFF:
            walk(right * 4)

    walk(0)
    return out


def stfs_file(path, wanted):
    d = open(path, 'rb').read()
    header_size = struct.unpack_from('>I', d, 0x340)[0]
    sep = d[0x37B]
    ft_count = struct.unpack_from('<H', d, 0x37C)[0]
    ft_block = int.from_bytes(d[0x37E:0x381], 'little')
    first = (header_size + 0xFFF) & 0xF000
    shift = 0 if sep & 1 else 1

    def block_off(b):
        r = b + (((b + 0xAA) // 0xAA) << shift)
        if b >= 0xAA:
            r += ((b + 0x70E4) // 0x70E4) << shift
        if b >= 0x70E4:
            r += ((b + 0x4AF768) // 0x4AF768) << shift
        return first + (r << 12)

    for i in range(ft_count):
        blk = block_off(ft_block + i)
        for e in range(0, 0x1000, 0x40):
            ent = d[blk + e:blk + e + 0x40]
            nlen = ent[0x28] & 0x3F
            if not nlen:
                continue
            name = ent[:nlen].decode('latin-1').lower()
            if name != wanted:
                continue
            nblocks = int.from_bytes(ent[0x29:0x2C], 'little')
            start = int.from_bytes(ent[0x2F:0x32], 'little')
            size = struct.unpack_from('>I', ent, 0x34)[0]
            # ponytail: assumes consecutive blocks (flag 0x40), true for TUs; follow hash chain if not
            assert ent[0x28] & 0x40, 'non-consecutive STFS file'
            data = b''.join(d[block_off(start + k):block_off(start + k) + 0x1000] for k in range(nblocks))
            return data[:size]
    sys.exit(f'{wanted} not in STFS')


if __name__ == '__main__':
    iso, tu, outdir = sys.argv[1:4]
    os.makedirs(outdir, exist_ok=True)
    files = iso_files(iso, {'default.xex', 'shader.ar'})
    files['default.xexp'] = stfs_file(tu, 'default.xexp')
    for name, data in files.items():
        assert data[:4] in (b'XEX2', b'XEX?') or name == 'shader.ar', name
        open(os.path.join(outdir, name), 'wb').write(data)
        print(name, len(data))
