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

LLAMA_TAG := b11429

.PHONY: llamacpp
llamacpp:
	test -d .cache/llama.cpp || git clone --depth 1 --branch $(LLAMA_TAG) https://github.com/ggml-org/llama.cpp .cache/llama.cpp
	$(UV) venv .cache/convert-venv --python 3.12
	VIRTUAL_ENV=.cache/convert-venv $(UV) pip install -r .cache/llama.cpp/requirements/requirements-convert_hf_to_gguf.txt
	# llama.cpp pins transformers 4.57, which has no Qwen3_5Tokenizer; use the
	# version mlx-lm trains with so the converter reads the same tokenizer.
	VIRTUAL_ENV=.cache/convert-venv $(UV) pip install "transformers==$$($(PY) python -c 'import transformers; print(transformers.__version__)' 2>/dev/null)"
