.PHONY: setup check lint test integration

setup:
	mix deps.get
	mix assets.setup

check:
	mix compile --warnings-as-errors
	mix format --check-formatted
	mix credo --strict
	scripts/ci/unsafe-grep.sh
	scripts/ci/sobelow-skips.sh
	bash scripts/ci/test/sobelow-skips_test.sh
	mix sobelow --exit --threshold low --strict
	mix deps.audit
	mix hex.audit
	mix deps.unlock --check-unused
	mix test --warnings-as-errors
	scripts/ci/test/scan_test.sh

lint:
	mix format
	mix credo --strict
	mix sobelow --exit --threshold low --strict

test:
	mix test

integration:
	scripts/ci/integration.sh
