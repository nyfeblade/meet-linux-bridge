.PHONY: install setup devices selftest route-on route-off join clean

install:
	./install.sh

setup:
	./setup.sh

devices:
	./devices.sh create

selftest:
	./selftest

route-on:
	./route on

route-off:
	./route off

join:
	@test -n "$(URL)" || (echo 'usage: make join URL=https://meet.google.com/xxx-xxxx-xxx' >&2; exit 2)
	node scripts/join-meet.mjs "$(URL)"

clean:
	./route off || true
	./devices.sh destroy || true
