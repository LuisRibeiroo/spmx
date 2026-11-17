.PHONY: bench bench-quick site site-dev

bench:
	bench/run.sh

bench-quick:
	bench/run.sh --quick

site:
	cd website && pnpm install --frozen-lockfile && pnpm run build

site-dev:
	cd website && pnpm install && pnpm run dev
