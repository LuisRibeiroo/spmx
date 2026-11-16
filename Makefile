.PHONY: bench bench-quick site site-dev

bench:
	bench/run.sh

bench-quick:
	bench/run.sh --quick

site:
	cd website && npm ci && npm run build

site-dev:
	cd website && npm install && npm run dev
