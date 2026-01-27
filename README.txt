🚀 Features

🔧 Automatic CPU Affinity Assignment
Detects the number of logical CPU cores on your system.
Builds an affinity mask that enables all cores except the last one.
Applies the mask to cs2.exe as soon as the game starts.
Reapplies the setting every time CS2 is launched.

🕵️ Continuous Process Monitoring
Displays CS2’s resource usage (PID, memory, etc.) in a live‑updating loop.
Refreshes every 5 seconds.

♻️ Persistent Loop
If CS2 closes, the script waits for the next launch and reapplies affinity automatically.

🧠 How It Works

1. PowerShell Affinity Manager
The script:
Waits for cs2.exe to appear.
Calculates a CPU affinity mask based on your system’s logical cores.
Applies the mask using PowerShell’s ProcessorAffinity property.
Monitors until CS2 exits, then resets and waits again.

2. Batch‑Side Resource Display
While PowerShell handles affinity, the batch script:
Clears the console
Shows CS2’s current tasklist entry
Updates every 5 seconds

📌 Why Use This?
Some players prefer to:
Reserve a CPU core for background tasks
Improve system responsiveness while gaming
Experiment with performance tuning for Source 2 titles
This script automates that process with zero manual intervention.

📝 Notes
Requires Windows with PowerShell available.
No installation needed — just run the .exe file.
Affinity mask logic can be customized if you want different core layouts.

Versions
CS2 Core Affinity Manager - No Window.exe (Runs in background. No Pop-up Window. If you wanted to add it as a start-up app/service)
CS2 Core Affinity Manager.exe (Exe version to add to to Steam Library as you cannot add .bat)
CS2-Core-Affinity-Manager.bat (Raw script)
