Botworld.pdf: Botworld.tex
	pdflatex Botworld.tex >/dev/null
	pdflatex Botworld.tex >/dev/null

Botworld.tex: Botworld.lhs
	lhs2TeX -o Botworld.tex Botworld.lhs

.PHONY: clean cleanall
clean:
	rm -rf Botworld.tex Botworld.aux Botworld.log Botworld.ptb Botworld.toc

cleanall:
	make clean
	rm -rf Botworld.pdf
