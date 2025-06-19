# RunMintTest.ps1
# This script runs the mod testing process when F7 is pressed, even when window is not in focus

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
    public const int SW_RESTORE = 9;
}
"@

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$automationScriptsPath = "..\..\DRGModdingAutomationScripts"
$mintPath = "C:\Mint"

# Function to run the mod testing process
function Run-MintTest {
    # Get and focus the console window
    $consoleHandle = [HotKeyHandler]::GetConsoleWindow()
    [HotKeyHandler]::ShowWindow($consoleHandle, [HotKeyHandler]::SW_RESTORE)
    [HotKeyHandler]::SetForegroundWindow($consoleHandle)

    # Wait half a second, then send F7 to the foreground window
    Start-Sleep -Milliseconds 500
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.SendKeys]::SendWait("{F7}")

    Write-Host "Starting mod testing process..."

    # Get the current folder name
    $localFolder = Split-Path -Leaf $scriptPath

    # Set up paths
    $globalTemplate = Join-Path $automationScriptsPath "Configs\Templates\GlobalConfig.ini"
    $whitelistTemplate = Join-Path $automationScriptsPath "Configs\Templates\PakWhiteList.ini"
    $globalOutput = Join-Path $automationScriptsPath "Configs\GlobalConfig.ini"
    $whitelistOutput = Join-Path $automationScriptsPath "Configs\PakWhiteList.ini"

    # Copy template contents and append folder name
    $globalContent = Get-Content $globalTemplate -Raw
    $globalContent = $globalContent.TrimEnd() + $localFolder
    Set-Content -Path $globalOutput -Value $globalContent -NoNewline

    $whitelistContent = Get-Content $whitelistTemplate -Raw
    $whitelistContent = $whitelistContent.TrimEnd() + $localFolder
    Set-Content -Path $whitelistOutput -Value $whitelistContent -NoNewline

    # Run the mod test batch file
    Write-Host "Running mod test process..."
    & (Join-Path $automationScriptsPath "RunModTest.bat")
    if ($LASTEXITCODE -ne 0) { throw "Mod test process failed" }

    # Copy the pak file
    $sourcePak = Join-Path $automationScriptsPath "Temp\$localFolder.pak"
    $destPak = "C:\DRGmodding\FSD\testmod.pak"
    Copy-Item -Path $sourcePak -Destination $destPak -Force

    # Run Mint and start the game
    & (Join-Path $mintPath "drg_mod_integration.exe") "profile" "Testing"
    Start-Process "steam://rungameid/548430"
    Start-Process "python" -ArgumentList "`"$scriptPath\process_uassets.py`""

    Write-Host "Mod testing process completed. Press F7 to run again or Ctrl+C to exit."
}

# Register the hotkey
$hWnd = [System.Diagnostics.Process]::GetCurrentProcess().MainWindowHandle
$hotkeyId = 1
$f7Key = 0x76  # Virtual key code for F7

if (-not [HotKeyHandler]::RegisterHotKey($hWnd, $hotkeyId, [HotKeyHandler]::MOD_NOREPEAT, $f7Key)) {
    Write-Host "Failed to register hotkey. Exiting..."
    exit 1
}

Write-Host "Press F7 to run the mod testing process or Ctrl+C to exit"

# Main message loop
$msg = New-Object HotKeyHandler+MSG
while ([HotKeyHandler]::GetMessage([ref] $msg, [IntPtr]::Zero, 0, 0)) {
    if ($msg.message -eq [HotKeyHandler]::WM_HOTKEY) {
        Start-Sleep -Seconds 0.1
        Run-MintTest
    }
    [HotKeyHandler]::TranslateMessage([ref] $msg)
    [HotKeyHandler]::DispatchMessage([ref] $msg)
}

# Cleanup
[HotKeyHandler]::UnregisterHotKey($hWnd, $hotkeyId)
pause