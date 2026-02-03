"""
console.py - Refined CLI interaction using ANSI codes (Lightweight Rich alternative).
"""

import sys
import time
import threading
import itertools

# ANSI Colors
C_RESET = "\033[0m"
C_BLUE = "\033[34m"
C_CYAN = "\033[36m"
C_GREEN = "\033[32m"
C_YELLOW = "\033[33m"
C_RED = "\033[31m"
C_BOLD = "\033[1m"
C_DIM = "\033[2m"

class Status:
    """
    Animated spinner context manager.
    """
    def __init__(self, message="Working..."):
        self.message = message
        self.stop_event = threading.Event()
        self.thread = None

    def __enter__(self):
        self.stop_event.clear()
        self.thread = threading.Thread(target=self._spin)
        self.thread.start()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.stop_event.set()
        self.thread.join()
        sys.stdout.write("\r" + " " * (len(self.message) + 10) + "\r") # Clear line
        sys.stdout.flush()

    def update(self, message):
        self.message = message

    def _spin(self):
        spinner = itertools.cycle(["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"])
        while not self.stop_event.is_set():
            sys.stdout.write(f"\r{C_CYAN}{next(spinner)}{C_RESET} {self.message}")
            sys.stdout.flush()
            time.sleep(0.08)

def title(text):
    print(f"\n{C_BOLD}{C_BLUE}ANSWER AGENT{C_RESET} | {text}")
    print(f"{C_DIM}{'='*40}{C_RESET}")

def success(text):
    print(f"{C_GREEN}✔{C_RESET} {text}")

def error(text):
    print(f"{C_RED}✖{C_RESET} {text}")

def info(text):
    print(f"{C_BLUE}ℹ{C_RESET} {text}")

def print_panel(title, lines):
    # Prints a boxed summary
    width = 60
    print(f"\n{C_CYAN}╭{'─'*(width-2)}╮{C_RESET}")
    print(f"{C_CYAN}│{C_RESET} {C_BOLD}{title.center(width-4)}{C_RESET} {C_CYAN}│{C_RESET}")
    print(f"{C_CYAN}├{'─'*(width-2)}┤{C_RESET}")
    for line in lines:
        print(f"{C_CYAN}│{C_RESET} {line.ljust(width-4)} {C_CYAN}│{C_RESET}")
    print(f"{C_CYAN}╰{'─'*(width-2)}╯{C_RESET}\n")
