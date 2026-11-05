# Windows Copy Scripts

Three double-click scripts that turn a cloned Windows drive into a second, bootable copy of Windows, while your original Windows keeps starting by default. For people who keep a spare copy of their Windows on a second SSD.

## What it does
- Gives the cloned drive a new disk ID and brings it online, so Windows can use both drives at once.
- Makes the copy use `C:` for itself when it starts.
- Builds the copy's own startup files and adds the copy to the Windows startup menu.
- Keeps your original Windows first in the boot order, with no menu shown at startup.
- Turns Windows Recovery back on inside the copy, so BitLocker can be used there.
- Saves a backup of the boot settings before it changes them, and shows the command that puts them back.

| Script | Run it from | What it does |
|---|---|---|
| `1-setup-copy.bat` | your **original** Windows, right after cloning | Everything above except Windows Recovery. |
| `2-fix-recovery-in-copy.bat` | **inside the copy**, the first time you start it | Turns Windows Recovery (Windows RE) back on, using the recovery partition on the copy's own disk. |
| `fix-boot-order.bat` | either Windows | Only if the PC starts the copy by default again (for example after a BIOS or Windows update): puts the original first again and hides the startup menu. |

## What you need
- Windows 10 or 11 on a **UEFI PC with GPT disks**. Older BIOS (MBR) setups are not supported.
- A second SSD with a full clone of your Windows drive, made with a cloning program (for example Samsung Magician).
- The Windows partition on the copy must be **larger than 50 GB**. The script looks for Windows only on partitions above that size.
- **BitLocker turned off** on the original before you clone it. A clone of an encrypted drive cannot be set up.
- An account with administrator rights. Each script asks for them by itself.
- Nothing else: the scripts use only programs that come with Windows (`diskpart`, `bcdboot`, `bcdedit`, `reagentc`, `reg` and PowerShell).

## Install
1. Download this project (green **Code** button, then **Download ZIP**) and unzip it, for example to your Desktop.
2. Nothing else needs to be installed.

## How to use
1. **Before cloning:** turn off BitLocker on the original Windows (Settings, then Privacy & security, then Device encryption, or BitLocker in Control Panel). Wait until decryption has finished.
2. **Clone** the original drive to the second SSD with your cloning program.
3. Start your **original** Windows and double-click **`1-setup-copy.bat`**. Click **Yes** when Windows asks for administrator rights.
   - It lists the disks on the PC.
   - It shows the disk your Windows runs from. Type `YES` if this is the original.
   - Type the **disk number of the copy**. Check its size and name in the list first: this disk gets changed.
   - Type `YES` to start.
   - Write down the backup file name it prints (for example `C:\bcd-backups\bcd-before-setup-copy-20260101-120000`).
4. **To start the copy:** hold **Shift** and click **Restart**, then choose **Use another operating system**. Or press your PC's **boot-menu key** right after you switch it on. This key depends on the maker of the PC or motherboard: it is often **F8**, **F11**, **F12** or **Esc**. Look it up in your PC's manual if none of these work.
5. The first time you are in the copy, double-click **`2-fix-recovery-in-copy.bat`**. When it says "Windows RE status: Enabled", you can turn on BitLocker in the copy (and again in the original).
6. If the PC later starts the copy instead of the original, double-click **`fix-boot-order.bat`** and type the disk number of your original Windows.

## Safety notes
- **What changes:** the copy's disk ID, the copy's saved drive letters (in the copy's registry), the startup files on the copy's EFI partition, the boot settings (BCD) of the running Windows, and the PC's firmware boot order. The original's files are not touched.
- **Backup of the boot settings:** `1-setup-copy.bat` and `fix-boot-order.bat` save the boot settings with `bcdedit /export` before they change anything, in `C:\bcd-backups`. To undo the boot changes, open Command Prompt as administrator and run the command the script printed, for example:
  ```
  bcdedit /import "C:\bcd-backups\bcd-before-setup-copy-20260101-120000"
  ```
  If Windows does not start, you can run the same command from Windows Recovery (Troubleshoot, then Command Prompt). There the Windows drive may have another letter, such as `D:`.
- **Checks:** the scripts stop with an explanation when a disk, partition or Windows folder is not where they expect it, or when `diskpart`, `reg`, `bcdboot` or `bcdedit` reports an error. They never just print OK.
- **Pick the right disk.** The copy's disk number is the one thing you type. The script refuses the disk Windows is running from, but it cannot tell two other disks apart for you.
- **Language:** the scripts read `bcdedit` output to find the original's boot entry. They look only at values, not at the labels, so they should work on Windows in any language. They were written and used on English Windows. If the entry is not found, the script says so and you can set the boot order in the BIOS or UEFI setup instead.

## Troubleshooting
- **"No Windows found on the copy"**: BitLocker was probably still on when you cloned, or the Windows partition is 50 GB or smaller. Turn off BitLocker, clone again, and run the script again.
- **"No EFI partition on the copy"**: the clone did not finish, or the disk is MBR, not GPT. These scripts need a UEFI (GPT) setup.
- **"Could not find the original's boot entry"**: open your PC's BIOS or UEFI setup and move the original drive to the top of the boot order.
- **The PC starts the copy instead of the original**: run `fix-boot-order.bat`.
- **The boot-menu key does nothing**: try F8, F11, F12 and Esc right after power-on, or use Shift + Restart from inside Windows.

## How it works
Each `.bat` file is also a PowerShell script: the first lines (the batch part) ask for administrator rights and then run the rest of the same file in PowerShell, so everything a script does can be read in the file itself. `1-setup-copy.bat` uses `diskpart uniqueid` for a new disk ID, clears the `MountedDevices` values in the copy's registry so it takes `C:`, and runs `bcdboot` twice: once to build the copy's own EFI startup files, once to add it to the original's boot menu. The firmware boot order is set with `bcdedit /set {fwbootmgr} displayorder ... /addfirst`. `2-fix-recovery-in-copy.bat` points `reagentc` at the `Winre.wim` on the copy's own recovery partition.

## License

MIT. See [LICENSE](LICENSE).
