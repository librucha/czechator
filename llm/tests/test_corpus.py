from czllm.data.corpus import collect, document_lines, keep_document

ACCENTED = "Včera jsem koupil nový počítač a přinesl ho domů."
PLAIN = "Vcera jsem koupil novy pocitac a prinesl ho domu."


def test_keep_document_rejects_text_typed_without_diacritics():
    assert keep_document(ACCENTED)
    assert not keep_document(PLAIN)


def test_document_lines_filters_length_and_unaccented_lines():
    text = "\n".join([
        "Krátké",                      # under 20 chars
        ACCENTED,
        PLAIN,                         # >= 4 words, no diacritics: typed without them
        "Na shledanou v pondělí, Petr",
        "x" * 700,                     # over 600 chars
    ])
    assert document_lines(text) == [ACCENTED, "Na shledanou v pondělí, Petr"]


def test_spell_filter_drops_lines_with_disputed_diacritics_and_empty_docs():
    from czllm.data.corpus import spell_filter

    docs = [
        {"source": "s", "doc_id": "a", "lines": ["plavky male holky – album", "Včera jsem koupil nový počítač."]},
        {"source": "s", "doc_id": "b", "lines": ["Mame radi kafe."]},
    ]

    class Checker:
        def suggestions(self, words):
            table = {"male": ["malé"], "Mame": ["Máme"], "radi": ["rádi"]}
            return {w: table.get(w) for w in words}

    out = spell_filter(docs, Checker())
    assert out == [{"source": "s", "doc_id": "a", "lines": ["Včera jsem koupil nový počítač."]}]


def test_collect_dedups_by_fold_key_and_respects_limit():
    docs = [
        ("d1", ACCENTED + "\n" + ACCENTED.lower()),
        ("d2", PLAIN),
        ("d3", "Dnes je krásně a slunce září nad městem."),
        ("d4", "Zítra bude pršet a budeme sedět doma u čaje."),
    ]
    out = list(collect(docs, "test", limit=2))
    assert [d["doc_id"] for d in out] == ["d1", "d3"]
    assert out[0]["lines"] == [ACCENTED]
    assert out[0]["source"] == "test"
