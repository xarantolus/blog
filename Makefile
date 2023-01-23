.PHONY: build clean serve

write:
	$(MAKE) -j2 serve watch

serve:
	cd _site && vite --open

build:
	docker run -it -v ${PWD}:/srv/jekyll jekyll/jekyll:pages jekyll build

watch:
	docker run -it -v ${PWD}:/srv/jekyll jekyll/jekyll:pages jekyll build --watch --incremental --force_polling

clean:
	rm -rf _site

