"""Live "Obsidian-style" Markdown highlighter for a QML TextEdit.

One editable block whose Markdown renders as you type: heading/**bold**/*italic*/
`code`/~~strike~~/> quote/lists/[links] style live, and — crucially — the syntax
markers (`#`, `**`, backticks, link brackets…) are HIDDEN on every line except the
one the caret is on. Qt can't delete characters from a live editor, so hidden
markers are collapsed to zero width (transparent + ~0pt) instead; the caret's own
line reveals them full-size so you can still edit the raw source. List bullets,
numbers, checkboxes and the quote '>' stay visible — they ARE the rendered mark.

Line spacing is widened via a proportional block line-height (TextEdit has no
lineHeight of its own), re-applied on every edit through reflow().

Registered to QML as `Disponera.MarkdownHighlighter` (app.py). Wire it up in
MarkdownField.qml: bind `document`, forward the caret via setCursor() and edits
via reflow(), and bind the colours from Theme so it follows the wallust palette.
"""

import re

from PySide6.QtCore import Property, Signal, Slot
from PySide6.QtGui import (
    QColor,
    QFont,
    QSyntaxHighlighter,
    QTextBlockFormat,
    QTextCharFormat,
    QTextCursor,
    QTextFormat,
)
from PySide6.QtQuick import QQuickTextDocument

_HEADING = re.compile(r"^(#{1,6})(\s+)(.*)$")
_QUOTE = re.compile(r"^(\s*>\s?)(.*)$")
_LIST = re.compile(r"^(\s*)([-*+]|\d+\.)(\s+)")
_TASK = re.compile(r"\[([ xX])\]")
_BOLD = re.compile(r"(\*\*|__)(.+?)\1")
_ITALIC = re.compile(r"(?<![*_\w])([*_])(?!\s)(.+?)(?<!\s)\1(?![*_\w])")
_STRIKE = re.compile(r"(~~)(.+?)(~~)")
_CODE = re.compile(r"(`+)([^`]+?)\1")
_LINK = re.compile(r"(\[)([^\]]+)(\]\()([^)]+)(\))")

_LINE_HEIGHT_PCT = 150   # proportional line spacing in the editor


class MarkdownHighlighter(QSyntaxHighlighter):
    IN_CODE = 1

    documentChanged = Signal()
    colorsChanged = Signal()

    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        self._doc: QQuickTextDocument | None = None
        self._active = -1          # block the caret is on (-1 ⇒ none ⇒ hide all markers)
        self._reflowing = False
        self._base = QColor("#e8ebf2")
        self._muted = QColor("#7f889b")
        self._accent = QColor("#e5c07b")
        self._link = QColor("#61afef")

    # ── document wiring (QML passes textEdit.textDocument) ──────────────────
    def _get_doc(self):
        return self._doc

    def _set_doc(self, d) -> None:
        if d is self._doc:
            return
        self._doc = d
        self.setDocument(d.textDocument() if d is not None else None)
        if d is not None:
            self.reflow()
        self.documentChanged.emit()

    document = Property(QQuickTextDocument, _get_doc, _set_doc, notify=documentChanged)

    # ── caret line: forwarded from QML so we know which line to reveal ──────
    @Slot(int)
    def setCursor(self, pos: int) -> None:
        if self._doc is None:
            return
        blk = -1 if pos < 0 else self._doc.textDocument().findBlock(pos).blockNumber()
        if blk != self._active:
            self._active = blk
            self.rehighlight()

    # ── widen line spacing (TextEdit has no lineHeight); re-run on each edit ─
    @Slot()
    def reflow(self) -> None:
        if self._reflowing or self._doc is None:
            return
        self._reflowing = True
        try:
            doc = self._doc.textDocument()
            cur = QTextCursor(doc)
            cur.select(QTextCursor.SelectionType.Document)
            bf = QTextBlockFormat()
            bf.setLineHeight(_LINE_HEIGHT_PCT,
                             QTextBlockFormat.LineHeightTypes.ProportionalHeight.value)
            cur.mergeBlockFormat(bf)     # format-only → doesn't change `text`, no QML loop
        finally:
            self._reflowing = False

    # ── themable colours ────────────────────────────────────────────────────
    def _bump(self) -> None:
        self.colorsChanged.emit()
        if self._doc is not None:
            self.rehighlight()

    def _get_base(self):   return self._base
    def _get_muted(self):  return self._muted
    def _get_accent(self): return self._accent
    def _get_link(self):   return self._link

    def _set_base(self, v):
        v = QColor(v)
        if self._base != v: self._base = v; self._bump()

    def _set_muted(self, v):
        v = QColor(v)
        if self._muted != v: self._muted = v; self._bump()

    def _set_accent(self, v):
        v = QColor(v)
        if self._accent != v: self._accent = v; self._bump()

    def _set_link(self, v):
        v = QColor(v)
        if self._link != v: self._link = v; self._bump()

    baseColor = Property(QColor, _get_base, _set_base, notify=colorsChanged)
    mutedColor = Property(QColor, _get_muted, _set_muted, notify=colorsChanged)
    accentColor = Property(QColor, _get_accent, _set_accent, notify=colorsChanged)
    linkColor = Property(QColor, _get_link, _set_link, notify=colorsChanged)

    # ── formatting helpers ──────────────────────────────────────────────────
    def _fmt(self, color=None, *, bold=False, italic=False, strike=False,
             mono=False, underline=False, size_adjust=0) -> QTextCharFormat:
        f = QTextCharFormat()
        if color is not None:
            f.setForeground(color)
        if bold:
            f.setFontWeight(QFont.Weight.Bold)
        if italic:
            f.setFontItalic(True)
        if strike:
            f.setFontStrikeOut(True)
        if underline:
            f.setFontUnderline(True)
        if mono:
            f.setFontFamilies(["monospace"])
        if size_adjust:
            f.setProperty(QTextFormat.Property.FontSizeAdjustment, size_adjust)
        return f

    def _marker(self, hide: bool) -> QTextCharFormat:
        """Format for a syntax marker: dimmed when its line is active, collapsed
        to zero width (transparent + ~0pt) when it isn't — so finished lines read
        as rendered while the caret's line still shows the raw source."""
        f = QTextCharFormat()
        if hide:
            f.setForeground(QColor(0, 0, 0, 0))
            f.setFontPointSize(0.01)
        else:
            f.setForeground(self._muted)
        return f

    # ── main entry ──────────────────────────────────────────────────────────
    def highlightBlock(self, text: str) -> None:  # noqa: N802 (Qt override)
        hide = self.currentBlock().blockNumber() != self._active
        marker = self._marker(hide)

        # fenced code blocks (``` … ```), tracked across blocks via block state
        is_fence = text.lstrip().startswith("```")
        if self.previousBlockState() == self.IN_CODE:
            self.setFormat(0, len(text), self._fmt(self._base, mono=True))
            self.setCurrentBlockState(-1 if is_fence else self.IN_CODE)
            return
        if is_fence:
            self.setFormat(0, len(text), marker)
            self.setCurrentBlockState(self.IN_CODE)
            return
        self.setCurrentBlockState(-1)

        # heading — bigger + bold; hash markers hidden/dimmed
        h = _HEADING.match(text)
        if h:
            adj = max(1, 4 - len(h.group(1)))
            self.setFormat(0, len(text), self._fmt(self._base, bold=True, size_adjust=adj))
            self.setFormat(0, h.start(3), marker)      # '### ' incl. the space
            self._inline(h.start(3), h.group(3), hide)
            return

        # blockquote — muted + italic (the '>' stays as the visible cue)
        q = _QUOTE.match(text)
        if q:
            self.setFormat(0, len(text), self._fmt(self._muted, italic=True))
            self._inline(q.start(2), q.group(2), hide, base_italic=True)
            return

        # list bullet / number (+ task-list checkbox) — these stay visible
        lm = _LIST.match(text)
        if lm:
            self.setFormat(lm.start(2), len(lm.group(2)), self._fmt(self._accent, bold=True))
            cb = _TASK.match(text, lm.end())
            if cb:
                checked = cb.group(1) in "xX"
                self.setFormat(cb.start(), 3,
                               self._fmt(self._accent if checked else self._muted, bold=True))
                if checked:
                    self.setFormat(cb.end(), len(text) - cb.end(),
                                   self._fmt(self._muted, strike=True))
                    return

        self._inline(0, text, hide)

    # inline emphasis in a run at `off`; masks consumed spans so an inner rule
    # can't re-match an outer one's delimiters (italic clobbering **bold**).
    def _inline(self, off: int, text: str, hide: bool, *, base_italic=False) -> None:
        marker = self._marker(hide)
        chars = list(text)

        def mask(a, b):
            for i in range(a, b):
                chars[i] = " "

        for m in _LINK.finditer(text):
            self.setFormat(off + m.start(2), len(m.group(2)), self._fmt(self._link, underline=True))
            self.setFormat(off + m.start(1), 1, marker)
            self.setFormat(off + m.start(3), len(m.group(3)), marker)
            self.setFormat(off + m.start(4), len(m.group(4)), marker)
            self.setFormat(off + m.start(5), 1, marker)
            mask(m.start(), m.end())

        for m in _CODE.finditer("".join(chars)):
            n = len(m.group(1))
            self.setFormat(off + m.start(), len(m.group(0)), self._fmt(self._accent, mono=True))
            self.setFormat(off + m.start(), n, marker)
            self.setFormat(off + m.end() - n, n, marker)
            mask(m.start(), m.end())

        for m in _BOLD.finditer("".join(chars)):
            self.setFormat(off + m.start(), len(m.group(0)),
                           self._fmt(self._base, bold=True, italic=base_italic))
            self.setFormat(off + m.start(), 2, marker)
            self.setFormat(off + m.end() - 2, 2, marker)
            mask(m.start(), m.end())

        for m in _STRIKE.finditer("".join(chars)):
            self.setFormat(off + m.start(), len(m.group(0)),
                           self._fmt(self._muted, strike=True, italic=base_italic))
            self.setFormat(off + m.start(1), 2, marker)
            self.setFormat(off + m.start(3), 2, marker)
            mask(m.start(), m.end())

        for m in _ITALIC.finditer("".join(chars)):
            self.setFormat(off + m.start(), len(m.group(0)),
                           self._fmt(self._base, italic=True))
            self.setFormat(off + m.start(), 1, marker)
            self.setFormat(off + m.end() - 1, 1, marker)
            mask(m.start(), m.end())
