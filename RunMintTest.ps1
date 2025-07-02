# RunMintTest.ps1
# This script runs the mod testing process when F7 is pressed, even when window is not in focus
# Ctrl+F7 uses PakWhiteList_Release.ini instead of PakWhiteList.ini

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Runtime.InteropServices;

public class HotKeyHandler {
    [DllImport("user32.dll")]
    public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    
    [DllImport("user32.dll")]
    public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    
    [DllImport("user32.dll")]
    public static extern bool GetMessage(out MSG lpMsg, IntPtr hWnd, uint wMsgFilterMin, uint wMsgFilterMax);
    
    [DllImport("user32.dll")]
    public static extern bool TranslateMessage([In] ref MSG lpMsg);
    
    [DllImport("user32.dll")]
    public static extern IntPtr DispatchMessage([In] ref MSG lpMsg);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    
    [StructLayout(LayoutKind.Sequential)]
    public struct MSG {
        public IntPtr hwnd;
        public uint message;
        public IntPtr wParam;
        public IntPtr lParam;
        public uint time;
        public POINT pt;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT {
        public int x;
        public int y;
    }
    
    public const int WM_HOTKEY = 0x0312;
    public const int MOD_NOREPEAT = 0x4000;
    public const int MOD_CONTROL = 0x0002;
    public const int SW_RESTORE = 9;
}
"@

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$automationScriptsPath = "..\..\DRGModdingAutomationScripts"
$mintPath = "C:\Mint"

# Function to run the mod testing process
function Run-MintTest {
    param(
        [bool]$UseReleaseWhitelist = $false
    )
    
    # Get and focus the console window
    $consoleHandle = [HotKeyHandler]::GetConsoleWindow()
    [HotKeyHandler]::ShowWindow($consoleHandle, [HotKeyHandler]::SW_RESTORE)
    [HotKeyHandler]::SetForegroundWindow($consoleHandle)

    # Wait half a second, then send F7 to the foreground window
    Start-Sleep -Milliseconds 500
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.SendKeys]::SendWait("{F7}")

    if ($UseReleaseWhitelist) {
        Write-Host "Starting mod testing process (Release mode)..."
    } else {
        Write-Host "Starting mod testing process..."
    }

    # Get the current folder name
    $localFolder = Split-Path -Leaf $scriptPath

    # Set up paths
    $globalTemplate = Join-Path $automationScriptsPath "Configs\Templates\GlobalConfig.ini"
    $globalOutput = Join-Path $automationScriptsPath "Configs\GlobalConfig.ini"
    
    # Choose whitelist template based on parameter
    if ($UseReleaseWhitelist) {
        $whitelistTemplate = Join-Path $automationScriptsPath "Configs\Templates\PakWhiteList_Release.ini"
        Write-Host "Using PakWhiteList_Release.ini template"
    } else {
        $whitelistTemplate = Join-Path $automationScriptsPath "Configs\Templates\PakWhiteList.ini"
        Write-Host "Using PakWhiteList.ini template"
    }
    
    $whitelistOutput = Join-Path $automationScriptsPath "Configs\PakWhiteList.ini"

    # Copy template contents and append folder name
    $globalContent = Get-Content $globalTemplate -Raw
    $globalContent = $globalContent.TrimEnd() + $localFolder
    Set-Content -Path $globalOutput -Value $globalContent -NoNewline

    $whitelistContent = Get-Content $whitelistTemplate -Raw
    $whitelistContent = $whitelistContent.TrimEnd() + $localFolder
    Set-Content -Path $whitelistOutput -Value $whitelistContent -NoNewline

    # Run the mod test batch file with error handling
    Write-Host "Running mod test process..."
    
    # Run the full process
    & (Join-Path $automationScriptsPath "RunModTest.bat")
    $modTestExitCode = $LASTEXITCODE
    
    if ($modTestExitCode -ne 0) {
        Write-Host "Mod test process failed with exit code: $modTestExitCode"
        Write-Host "Press F7 to retry the full process or Ctrl+C to exit."
        return
    }

    # Copy the pak file
    $sourcePak = Join-Path $automationScriptsPath "Temp\$localFolder.pak"
    $destPak = "C:\DRGmodding\FSD\testmod.pak"
    
    if (Test-Path $sourcePak) {
        Copy-Item -Path $sourcePak -Destination $destPak -Force
        Write-Host "Pak file copied successfully."
    } else {
        Write-Host "Warning: Pak file not found at $sourcePak"
    }

    # Run Mint and start the game
    & (Join-Path $mintPath "drg_mod_integration.exe") "profile" "Testing"
    Start-Process "steam://rungameid/548430"
    Start-Process "python" -ArgumentList "`"$scriptPath\process_uassets.py`""

    if ($UseReleaseWhitelist) {
        Write-Host "Mod testing process completed (Release mode). Press F7 for normal mode, Ctrl+F7 for release mode, or Ctrl+C to exit."
    } else {
        Write-Host "Mod testing process completed. Press F7 for normal mode, Ctrl+F7 for release mode, or Ctrl+C to exit."
    }
}

# Register the hotkeys
$hWnd = [System.Diagnostics.Process]::GetCurrentProcess().MainWindowHandle
$f7Key = 0x76  # Virtual key code for F7

# Register F7 (normal mode)
$normalHotkeyId = 1
if (-not [HotKeyHandler]::RegisterHotKey($hWnd, $normalHotkeyId, [HotKeyHandler]::MOD_NOREPEAT, $f7Key)) {
    Write-Host "Failed to register F7 hotkey. Exiting..."
    exit 1
}

# Register Ctrl+F7 (release mode)
$releaseHotkeyId = 2
$ctrlModifier = [HotKeyHandler]::MOD_CONTROL -bor [HotKeyHandler]::MOD_NOREPEAT
if (-not [HotKeyHandler]::RegisterHotKey($hWnd, $releaseHotkeyId, $ctrlModifier, $f7Key)) {
    Write-Host "Failed to register Ctrl+F7 hotkey. Exiting..."
    [HotKeyHandler]::UnregisterHotKey($hWnd, $normalHotkeyId)
    exit 1
}

Write-Host "Press F7 for normal mode or Ctrl+F7 for release mode (using PakWhiteList_Release.ini) or Ctrl+C to exit"

# Main message loop
$msg = New-Object HotKeyHandler+MSG
while ([HotKeyHandler]::GetMessage([ref] $msg, [IntPtr]::Zero, 0, 0)) {
    if ($msg.message -eq [HotKeyHandler]::WM_HOTKEY) {
        Start-Sleep -Seconds 0.1
        
        # Check which hotkey was pressed
        if ($msg.wParam -eq $normalHotkeyId) {
            Run-MintTest -UseReleaseWhitelist $false
        } elseif ($msg.wParam -eq $releaseHotkeyId) {
            Run-MintTest -UseReleaseWhitelist $true
        }
    }
    [HotKeyHandler]::TranslateMessage([ref] $msg)
    [HotKeyHandler]::DispatchMessage([ref] $msg)
}

# Cleanup
[HotKeyHandler]::UnregisterHotKey($hWnd, $normalHotkeyId)
[HotKeyHandler]::UnregisterHotKey($hWnd, $releaseHotkeyId)
pause