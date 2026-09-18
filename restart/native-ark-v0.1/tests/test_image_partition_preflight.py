from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class NativeImagePartitionPreflightTests(unittest.TestCase):
    def test_raw_image_parent_exists_before_truncate(self):
        script = (ROOT / "build/build-image.sh").read_text()
        mkdir = script.index('mkdir -p "$OUT" "$MNT" "$(dirname "$IMG")"')
        truncate = script.index('truncate -s "${SIZE_GIB}G" "$IMG"')
        self.assertLess(mkdir, truncate)

    def test_partition_table_is_written_to_attached_loop(self):
        script = (ROOT / "build/build-image.sh").read_text()
        attach = script.index('LOOP="$(losetup --find --show "$IMG")"')
        zap = script.index('sgdisk --zap-all "$LOOP"')
        first = script.index('sgdisk -n 1:1MiB:+1GiB -t 1:ef00 -c 1:ARKESP "$LOOP"')
        second = script.index('sgdisk -n 2:0:0 -t 2:8300 -c 2:ARKROOT "$LOOP"')
        self.assertLess(attach, zap)
        self.assertLess(zap, first)
        self.assertLess(first, second)
        self.assertNotIn('sgdisk --zap-all "$IMG"', script)


if __name__ == "__main__":
    unittest.main()
