.PHONY: test check install

PREFIX ?= /usr/local

test:
	sh test/run.sh

check: test
	shellcheck -s sh gostodian-svc test/run.sh test/mocks/*

install:
	install -d -m 0755 $(DESTDIR)$(PREFIX)/libexec
	install -m 0755 gostodian-svc $(DESTDIR)$(PREFIX)/libexec/gostodian-svc
