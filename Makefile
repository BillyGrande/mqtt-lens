.PHONY: setup check lint test tamper integration

setup:
	mix deps.get
	mix assets.setup
	scripts/ci/tool-sums.sh
	mix assets.build

check:
	mix compile --warnings-as-errors
	mix format --check-formatted
	mix credo --strict
	scripts/ci/unsafe-grep.sh
	scripts/ci/sobelow-skips.sh
	scripts/ci/tool-sums.sh
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

# Local run of the CI test-tamper gate: make tamper BASE=<sha> HEAD=<sha>
tamper:
	scripts/ci/test-tamper.sh "$(BASE)" "$(HEAD)"

integration:
	scripts/ci/integration.sh
