# HopToDesk Session Panel Tray Support (Patch Series)

Windows system-tray minimize/restore support for the HopToDesk session connection-manager panel, extracted as a focused patch series and source diff against upstream HopToDesk.

## Upstream base & license

- **Upstream repository:** `https://gitlab.com/hoptodesk/hoptodesk.git`
- **Base commit:** `5bb08d7afcf4fc828da3e48f14c03a28416459c3`
- **License:** GNU Affero General Public License v3.0 (`AGPL-3.0`) - see [LICENSE](LICENSE), carried over directly from upstream HopToDesk.

## What changed

- **`src/ui/cm_tray.rs` & `src/ui.rs`:** Adds a dedicated Windows tray icon (`HopToDesk - active session controls`) owned by the session panel process so restoring the panel does not depend on the main window or separate `--tray` process.
- **`src/ui/cm.rs` & `src/ui/cm.tis`:** Adds `can_hide_to_tray()` gated on `allow-session-panel-tray` (`Y`) and hides the panel to tray instead of minimizing when enabled; adds `showSessionPanel` synchronization on restore.
- **`src/ui/index.tis`:** Adds the **Minimize session panel to tray** toggle in Windows Appearance settings.
- **`libs/clipboard/src/windows/wf_cliprdr.c` (patch 03):** Adds `#include <wchar.h>` needed for local Windows MSVC/MinGW builds.

## Contents

- `patches/` - Git-applyable patches (`01-session-panel-tray.patch`, `02-cm-tray-rs.patch`, `03-windows-wf-cliprdr-wchar.patch`).
- `src/` - Full copies of the modified and added source files for direct reading.
- `scripts/` - Local Windows build and safe-replacement install/rollback helpers (`Build-CustomHopToDesk.ps1`, `Install-CustomHopToDesk.ps1`).

## Applying & building

Clone upstream HopToDesk at `5bb08d7afcf4fc828da3e48f14c03a28416459c3` and apply the patches:

```powershell
git clone https://gitlab.com/hoptodesk/hoptodesk.git
cd hoptodesk
git checkout 5bb08d7afcf4fc828da3e48f14c03a28416459c3
git apply ..\patches\01-session-panel-tray.patch
git apply ..\patches\02-cm-tray-rs.patch
git apply ..\patches\03-windows-wf-cliprdr-wchar.patch
```

No prebuilt binaries are included in this repository. Anyone redistributing compiled binaries must build fresh from a clean upstream checkout and comply with the AGPL-3.0 source-availability requirements.
