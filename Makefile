
APPS := node-a1 node-gs node-gw node-infr
.PHONY: all verify test validate clean $(APPS)

all: verify test validate

verify:
	./tools/verify-sanitization.sh

test:
	python3 -m unittest discover -s tests -q

validate:
	python3 libs/scripts/ci/validate-images.py

app-%:
	@for app in $(APPS); do \
		echo "== $$app: $* =="; \
		$(MAKE) -C apps/$$app $* || exit 1; \
	done

clean:
	find . -name '*.pyc' -type f -delete
	find . -type d -name __pycache__ -prune -exec rm -rf -- {} +
	rm -rf .pytest_cache
