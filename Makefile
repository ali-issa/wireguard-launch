.PHONY: all build test lint clean help

help:
	@echo "make build   - assemble lightsail-launch.sh from src/"
	@echo "make test    - run the full test suite (tests/run.sh)"
	@echo "make lint    - syntax-check shell + python sources"
	@echo "make clean   - remove build/test artifacts"

all: build

build:
	./build.sh

test:
	./tests/run.sh

lint:
	./tests/test-lint.sh

clean:
	rm -rf src/__pycache__ tests/__pycache__
