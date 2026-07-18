"""Serialized script runner — one QProcess at a time, FIFO.

Mirrors the shell's CalDavService queue semantics (a fast double-click on two
todos must not kill the first PUT mid-flight) and replaces the skeleton's
blocking `subprocess.run` on the GUI thread. Every backend script prints its
full JSON cache on stdout; consumers get it via the `finished` signal.
"""

from PySide6.QtCore import QObject, QProcess, QProcessEnvironment, Signal


class ScriptQueue(QObject):
    """FIFO queue of argv lists; emits finished(stdout, exitCode) per command."""

    finished = Signal(str, int)
    busyChanged = Signal()

    def __init__(self, parent: QObject | None = None) -> None:
        super().__init__(parent)
        # each item is (argv, env-overrides|None); env carries secrets (CD_PASS)
        # that must never sit on a shared argv.
        self._queue: list[tuple[list[str], dict | None]] = []
        self._proc: QProcess | None = None

    @property
    def busy(self) -> bool:
        return self._proc is not None or bool(self._queue)

    def has_queued(self, verb: str) -> bool:
        """True when a command with this verb is queued or running (debounce).
        argv shape is ["python3", <script>, <verb>, …] → verb sits at index 2
        (index 1 of QProcess.arguments())."""
        if any(len(a) > 2 and a[2] == verb for a, _env in self._queue):
            return True
        p = self._proc
        return p is not None and len(p.arguments()) > 1 and p.arguments()[1] == verb

    def run(self, argv: list[str], env: dict | None = None) -> None:
        self._queue.append((list(argv), dict(env) if env else None))
        self.busyChanged.emit()
        self._pump()

    def _pump(self) -> None:
        if self._proc is not None or not self._queue:
            return
        argv, env = self._queue.pop(0)
        proc = QProcess(self)
        self._proc = proc
        proc.setProgram(argv[0])
        proc.setArguments(argv[1:])
        if env:
            pe = QProcessEnvironment.systemEnvironment()
            for k, v in env.items():
                pe.insert(k, v)
            proc.setProcessEnvironment(pe)
        proc.finished.connect(lambda code, _status: self._done(code))
        proc.start()

    def _done(self, code: int) -> None:
        proc = self._proc
        self._proc = None
        out = ""
        if proc is not None:
            out = bytes(proc.readAllStandardOutput()).decode(errors="replace")
            proc.deleteLater()
        self.finished.emit(out, int(code))
        self.busyChanged.emit()
        self._pump()
