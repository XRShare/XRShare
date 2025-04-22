.PHONY: codex-summary

# Regenerate codex.md and CODEBASE_SUMMARY.md for Codex CLI context
codex-summary:
	python3 scripts/update_codex_summary.py