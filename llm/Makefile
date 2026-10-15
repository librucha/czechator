UV ?= uv
PY := $(UV) run

.PHONY: test
test:
	$(PY) pytest -q

DICT_URL := https://raw.githubusercontent.com/LibreOffice/dictionaries/master/cs_CZ

.PHONY: dict
dict:
	mkdir -p data/dict
	curl -fsSL -o data/dict/cs_CZ.aff $(DICT_URL)/cs_CZ.aff
	curl -fsSL -o data/dict/cs_CZ.dic $(DICT_URL)/cs_CZ.dic
