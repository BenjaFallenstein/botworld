BotWorld.pdf: BotWorld.tex
	pdflatex BotWorld.tex >/dev/null
	pdflatex BotWorld.tex >/dev/null

BotWorld.tex: BotWorld.lhs
	lhs2TeX -o BotWorld.tex BotWorld.lhs

.PHONY: clean cleanall
clean:
	rm -rf BotWorld.tex BotWorld.aux BotWorld.log BotWorld.ptb BotWorld.toc

cleanall:
	make clean
	rm -rf BotWorld.pdf
