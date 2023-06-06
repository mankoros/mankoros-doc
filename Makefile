DOCS := $(shell find doc -name "*.typ"|sort -d)

pdf: docs-all
	@typst compile main.typ
	

watch: docs-all
	@typst watch main.typ
	
docs-all:
	@ > doc-all.typ
	@for file in $(DOCS); do \
  		echo "#include \"$$file\"" >> doc-all.typ; \
	done

clean:
	@rm -rf *.pdf
	@rm -rf doc-all.typ
	@rm -rf doc/*.pdf

format-lint:
	@autocorrect --lint *.typ doc/*.typ
	
format-fix:
	@autocorrect --fix *.typ doc/*.typ