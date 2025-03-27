import tkinter as tk
from tkinter import filedialog, messagebox, scrolledtext
import subprocess
import threading
import ctypes
import os
import sys

def run_as_admin():
    if sys.platform != 'win32':
        return
    if ctypes.windll.shell32.IsUserAnAdmin():
        return
    script = os.path.abspath(sys.argv[0])
    params = ' '.join([script] + sys.argv[1:])
    ctypes.windll.shell32.ShellExecuteW(None, "runas", sys.executable, params, None, 1)
    sys.exit(0)

run_as_admin()

class ISOCreatorGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("ExactISO - Bootable ISO Creator")

        # Source drive input
        tk.Label(root, text="Source Drive:").grid(row=0, column=0, sticky='w')
        self.source_drive = tk.Entry(root, width=30)
        self.source_drive.grid(row=0, column=1, padx=5, pady=5)
        tk.Button(root, text="Browse", command=self.select_source_drive).grid(row=0, column=2)

        # Working/output directory
        tk.Label(root, text="Working Directory:").grid(row=1, column=0, sticky='w')
        self.work_dir = tk.Entry(root, width=30)
        self.work_dir.grid(row=1, column=1, padx=5, pady=5)
        tk.Button(root, text="Browse", command=self.select_working_dir).grid(row=1, column=2)

        # Boot mode override
        self.override_mode = tk.BooleanVar()
        self.override_mode.set(False)
        self.boot_mode = tk.StringVar()
        self.boot_mode.set("BIOS")  # Default if overridden

        tk.Checkbutton(root, text="Override Boot Mode", variable=self.override_mode).grid(row=2, column=0, sticky='w')
        tk.OptionMenu(root, self.boot_mode, "BIOS", "UEFI").grid(row=2, column=1, sticky='w')

        # Start button
        self.start_button = tk.Button(root, text="Create Bootable ISO", command=self.start_process)
        self.start_button.grid(row=3, column=0, columnspan=3, pady=10)

        # Output window
        self.output = scrolledtext.ScrolledText(root, width=80, height=20)
        self.output.grid(row=4, column=0, columnspan=3, padx=10, pady=5)

    def log(self, message):
        self.output.insert(tk.END, message + '\n')
        self.output.see(tk.END)

    def select_source_drive(self):
        path = filedialog.askdirectory()
        if path:
            self.source_drive.delete(0, tk.END)
            self.source_drive.insert(0, path)

    def select_working_dir(self):
        path = filedialog.askdirectory()
        if path:
            self.work_dir.delete(0, tk.END)
            self.work_dir.insert(0, path)

    def start_process(self):
        src = self.source_drive.get().strip()
        work = self.work_dir.get().strip()

        if not os.path.exists(src):
            messagebox.showerror("Error", "Invalid source drive!")
            return

        if not os.path.exists(work):
            messagebox.showerror("Error", "Working directory doesn't exist!")
            return

        self.start_button.config(state='disabled')
        thread = threading.Thread(target=self.run_script, args=(src, work))
        thread.start()

    def run_script(self, src, work):
        try:
            script_path = os.path.join(os.getcwd(), "CreateDriveISO.ps1")
            command = [
                "pwsh.exe",
                "-ExecutionPolicy", "Bypass",
                "-File", f'"{script_path}"',
                "-SourceDrive", f'"{src}"',
                "-WorkingDir", f'"{work}"'
            ]

            if self.override_mode.get():
                command += ["-ForceBootMode", self.boot_mode.get()]

            process = subprocess.Popen(" ".join(command), stdout=subprocess.PIPE,
                                       stderr=subprocess.STDOUT, text=True, shell=True)

            for line in process.stdout:
                self.log(line.strip())

        except Exception as e:
            self.log(f"[ERROR] {e}")
        finally:
            self.start_button.config(state='normal')

if __name__ == "__main__":
    root = tk.Tk()
    app = ISOCreatorGUI(root)
    root.mainloop()