"""Index original Open English Wordnet 2025+ glosses for offline lookups."""
from pathlib import Path
import sqlite3
import sys
import zipfile


def build(archive_path: Path, output: Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    database = output / "WordNet.sqlite3"
    temporary = output / "WordNet.sqlite3.new"
    temporary.unlink(missing_ok=True)
    with zipfile.ZipFile(archive_path) as archive, sqlite3.connect(temporary) as db:
        db.execute("CREATE TABLE lexicon (term TEXT PRIMARY KEY, entry TEXT NOT NULL) WITHOUT ROWID")
        db.execute("CREATE TABLE inflections (form TEXT, lemma TEXT, PRIMARY KEY (form, lemma)) WITHOUT ROWID")
        entries: dict[str, list[str]] = {}
        for word_class, label in (("noun", "n."), ("verb", "v."), ("adj", "adj."), ("adv", "adv.")):
            with archive.open(f"oewn2025-plus/data.{word_class}") as data:
                glosses = {}
                for raw in data:
                    line = raw.decode("utf-8")
                    if line[0].isdigit() and "|" in line:
                        header, gloss = line.split("|", 1)
                        glosses[header.split()[0]] = gloss.strip()
            with archive.open(f"oewn2025-plus/index.{word_class}") as index:
                for raw in index:
                    line = raw.decode("utf-8")
                    if not line.strip() or line.startswith(" "):
                        continue
                    fields = line.split()
                    lemma = fields[0]
                    number = int(fields[2])
                    for rank, offset in enumerate(fields[-number:]):
                        entries.setdefault(lemma, []).append(f"{rank + 1}. {label} {glosses[offset]}")
            with archive.open(f"oewn2025-plus/{word_class}.exc") as exceptions:
                for raw in exceptions:
                    fields = raw.decode("utf-8").split()
                    if fields:
                        form, *lemmas = fields
                        db.executemany("INSERT OR IGNORE INTO inflections VALUES (?, ?)", [(form, lemma) for lemma in lemmas])
        db.executemany("INSERT INTO lexicon VALUES (?, ?)", ((key, "\n\n".join(value)) for key, value in sorted(entries.items())))
        assert len(entries) > 100_000 and "neighborhood" in entries
        assert db.execute("PRAGMA quick_check").fetchone() == ("ok",)
    temporary.replace(database)


if __name__ == "__main__":
    build(Path(sys.argv[1]), Path(sys.argv[2]))
