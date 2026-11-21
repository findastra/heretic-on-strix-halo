"""Run Heretic without a Windows console (e.g. from a script or over SSH with output to a log).

Heretic 2.1.0 builds its questionary menus even when config.toml presets the answer, and
prompt_toolkit then raises NoConsoleScreenBufferError on Windows when stdout is not a console.
This wrapper swaps the menu builders for stubs: preset answers pass straight through (Heretic
never calls .ask() for them), and any question that is NOT preset fails with a clear message
instead of hanging or crashing deep inside prompt_toolkit.

Usage: python heretic_headless.py [heretic arguments...]   (run from the folder holding config.toml)
"""
import sys

import questionary


class _NoConsoleQuestion:
    def __init__(self, message: str = "", *args, **kwargs):
        self.message = message

    def ask(self, *args, **kwargs):
        raise RuntimeError(
            f"Heretic asked {self.message!r}, but no console is attached. "
            "Preset the answer in config.toml and run again."
        )

    unsafe_ask = ask


def _stub(message: str = "", *args, **kwargs):
    return _NoConsoleQuestion(message)


for _name in ("select", "rawselect", "checkbox", "text", "path", "password", "confirm", "autocomplete"):
    setattr(questionary, _name, _stub)

from heretic.main import main  # noqa: E402  (import after patching on purpose)

sys.exit(main())
