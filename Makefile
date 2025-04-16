SWIFTLINT := swiftlint

.PHONY: lint autocorrect

lint:
	$(SWIFTLINT) lint --strict

autocorrect:
	$(SWIFTLINT) autocorrect --format