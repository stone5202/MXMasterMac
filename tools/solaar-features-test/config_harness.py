# Isolate the production Codable settings struct; no app, user settings, or HID access.
import sys
from pathlib import Path
source = Path(sys.argv[1]).read_text()
a = source.index('struct DeviceSettings:')
b = source.index('// MX Flow', a)
Path(sys.argv[2]).write_text('import Foundation\n' + source[a:b])
