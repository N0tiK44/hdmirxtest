# Operations — hdmirxtest V1.1.1

Repository: `https://github.com/N0tiK44/hdmirxtest`

## First clone on the Orange Pi

```bash
mkdir -p ~/src
cd ~/src
git clone https://github.com/N0tiK44/hdmirxtest.git
cd hdmirxtest
bash scripts/install-deps.sh
```

## Normal test

```bash
cd ~/src/hdmirxtest
bash scripts/pi-cycle.sh baseline
```

## Debug only

```bash
cd ~/src/hdmirxtest
bash scripts/pi-cycle.sh debug
```

Every cycle syncs the SBC checkout to `origin/main`, safely stashes uncommitted changes, preserves divergent committed state on a backup branch, and packages results as `~/hdmirxtest-latest.tar.gz`.

## Windows-controlled workflow

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\host-cycle.ps1 -Mode baseline
```

Or double-click `RUN-BASELINE.cmd`. Use `RUN-DEBUG.cmd` for debug-only collection and `FETCH-RESULTS.cmd` to copy an existing result archive.

Manual PowerShell copy:

```powershell
scp visionseek@192.168.20.35:~/hdmirxtest-latest.tar.gz "$env:USERPROFILE\Downloads\hdmirxtest-latest.tar.gz"
```

## 240 Hz

After the baseline passes, use `RUN-240-WIZARD.cmd`. Manual modes are `prepare240`, `probe240`, and `240`.

## EDID restore

```bash
cd ~/src/hdmirxtest
sudo bash scripts/restore-rx-edid.sh
```

On systems using `doas`, replace `sudo` with `doas`.
