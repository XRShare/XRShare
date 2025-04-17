
SWIFTLINT := swiftlint

.PHONY: lint autocorrect ingest-docset query-docset assist

lint:
	$(SWIFTLINT) lint --strict

autocorrect:
	$(SWIFTLINT) autocorrect --format
ingest-docset:
	@echo "Usage: make ingest-docset DOCSET=/path/to/Apple_API_Reference.docset OUTPUT=path/to/index.faiss"
	@if [ -z "$(DOCSET)" ] || [ -z "$(OUTPUT)" ]; then \
	  echo "Error: specify DOCSET and OUTPUT"; exit 1; \
	fi
	python3 scripts/ingest_docset.py --docset $(DOCSET) --output $(OUTPUT)
query-docset:
   @echo "Usage: make query-docset INDEX=path/to/index.faiss META=path/to/index.faiss.meta.json QUERY='Your question'"
   @if [ -z "$(INDEX)" ] || [ -z "$(META)" ] || [ -z "$(QUERY)" ]; then \
       echo "Error: specify INDEX, META, and QUERY"; exit 1; \
   fi
	python3 scripts/query_docset.py --index $(INDEX) --meta $(META) --query "$(QUERY)"
assist:
	@echo "Usage: make assist INDEX=path/to/index.faiss META=path/to/index.faiss.meta.json QUESTION='Your question' [OPENAI_API_KEY=...]"
	@if [ -z "$(INDEX)" ] || [ -z "$(META)" ] || [ -z "$(QUESTION)" ]; then \
    echo "Error: specify INDEX, META, and QUESTION"; exit 1; \
	fi
	python3 scripts/query_docset.py --index $(INDEX) --meta $(META) --query "$(QUESTION)"